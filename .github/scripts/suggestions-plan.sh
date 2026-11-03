#!/usr/bin/env bash
# Decide which formatter suggestions to post on a pull request and which old
# ones to retire. Reads GitHub, writes nothing to it; suggestions-apply.sh
# carries the plan out.
#
# Usage: suggestions-plan.sh
# Env:
#   GITHUB_REPOSITORY  owner/name.
#   PR_NUMBER          pull request number.
#   HEAD_SHA           head commit the formatters ran on.
#   GH_TOKEN           token with pull-requests: read.
#   LINT_DIR           directory with shfmt.txt and mdformat.txt, the
#                      formatters' diffs; a missing file means it did not run.
#   PLAN_DIR           directory to write the plan into; created.
#   GITHUB_OUTPUT      receives work=true when the plan has anything in it.
# The plan:
#   review.json  one review with a suggested change per formatter hunk, except
#                hunks outside the pull request diff (GitHub rejects those; the
#                lint report comment still shows them) and hunks whose exact
#                suggestion is already open. Written only when there is one.
#   retire.tsv   our open suggestion threads that no longer apply, with the
#                reply saying why: thread id, comment id, comment node id,
#                whether we already replied, reply. A thread no longer applies
#                when its lines changed (GitHub marks it outdated), or when its
#                formatter ran cleanly and would not post the same suggestion
#                (same lines, same text) now. Written only when there is one.
set -euo pipefail

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${HEAD_SHA:?HEAD_SHA is required}"
: "${LINT_DIR:?LINT_DIR is required}"
: "${PLAN_DIR:?PLAN_DIR is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

# Our suggestion comments start with "<!-- lint-suggestion tool=TOOL -->".
marker_re='^<!-- lint-suggestion tool=(?<tool>[a-z]+) -->'
scripts=$(dirname "$0")
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
mkdir -p "${PLAN_DIR}"

# Every formatter hunk.
: >"${work}/hunks.jsonl"
if [[ -f ${LINT_DIR}/shfmt.txt ]]; then
    "${scripts}/diff-hunks.sh" shfmt "" <"${LINT_DIR}/shfmt.txt" >>"${work}/hunks.jsonl"
fi
if [[ -f ${LINT_DIR}/mdformat.txt ]]; then
    "${scripts}/diff-hunks.sh" mdformat b/ <"${LINT_DIR}/mdformat.txt" >>"${work}/hunks.jsonl"
fi

# Print the formatters that ran and printed only a diff, as a JSON array. For
# those a missing hunk means the formatter accepts the lines; a formatter that
# failed with an error message proves nothing.
clean_tools() {
    local tool
    for tool in shfmt mdformat; do
        if [[ -f ${LINT_DIR}/${tool}.txt ]] &&
            ! grep -qvE '^(diff |@@ |[-+ \]|$)' "${LINT_DIR}/${tool}.txt"; then
            echo "${tool}"
        fi
    done | jq -Rsc 'split("\n") | map(select(. != ""))'
}

# Our open suggestion threads: not resolved by hand, first comment ours and
# not minimized.
# shellcheck disable=SC2016 # $owner and the rest are GraphQL variables.
query='
query($owner: String!, $name: String!, $number: Int!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id isResolved isOutdated path startLine line
          comments(first: 20) { nodes { id databaseId body isMinimized author { login } } }
        }
      }
    }
  }
}'
gh api graphql --paginate -f query="${query}" \
    -F owner="${GITHUB_REPOSITORY%%/*}" -F name="${GITHUB_REPOSITORY#*/}" -F number="${PR_NUMBER}" |
    jq -c --arg marker_re "${marker_re}" '
        .data.repository.pullRequest.reviewThreads.nodes[]
        | .comments.nodes[0] as $first
        | select((.isResolved | not)
            and $first.author.login == "github-actions"
            and ($first.body | test($marker_re))
            and ($first.isMinimized | not))
        | {id, outdated: .isOutdated, path, start_line: .startLine, line, body: $first.body,
           tool: ($first.body | capture($marker_re).tool),
           comment_id: $first.databaseId, node_id: $first.id,
           replied: any(.comments.nodes[1:][]; .author.login == "github-actions")}' \
        >"${work}/threads.jsonl"

# The suggestion comment for every hunk. The fence is longer than any
# backtick run in the lines, so none closes it.
jq -c 'select(.start >= 1)
    | ("`" * ([([.lines[] | scan("`+") | length] | max // 0) + 1, 3] | max)) as $fence
    | (if .start < .end then "these lines" else "this line" end) as $what
    | {tool, path, line: .end, side: "RIGHT",
       body: "<!-- lint-suggestion tool=\(.tool) -->\n\(.tool) would format \($what) like this:\n\n\($fence)suggestion\n\(.lines | map(. + "\n") | add // "")\($fence)"}
    + (if .start < .end then {start_line: .start, start_side: "RIGHT"} else {} end)' \
    "${work}/hunks.jsonl" >"${work}/suggestions.jsonl"

# A thread and a suggestion are the same when they cover the same lines with
# the same text. A one-line suggestion is posted without start_line, but
# GitHub reports its thread's startLine as the line itself.
# shellcheck disable=SC2016 # $t and $s are jq variables.
same='def same($t; $s): $t.path == $s.path and $t.line == $s.line
    and ($t.start_line // $t.line) == ($s.start_line // $s.line) and $t.body == $s.body;'

clean=$(clean_tools)
jq -r --argjson clean "${clean}" --slurpfile suggestions "${work}/suggestions.jsonl" \
    --arg sha "${HEAD_SHA:0:7}" "${same}"'
    . as $thread
    | if .outdated then
        "Resolved: these lines changed by \($sha), so this suggestion no longer applies."
      elif (.tool | IN($clean[])) and (any($suggestions[]; same($thread; .)) | not) then
        "Resolved: \(.tool) no longer suggests this change at \($sha)."
      else empty end
    | [$thread.id, $thread.comment_id, $thread.node_id, $thread.replied, .] | @tsv' \
    "${work}/threads.jsonl" >"${work}/retire.tsv"

# The lines of the head commit the pull request diff shows; GitHub accepts
# review comments only on those.
: >"${work}/ranges.jsonl"
if [[ -s ${work}/suggestions.jsonl ]]; then
    gh api --paginate "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/files" |
        jq -c '.[] | select(.patch != null) | .filename as $path
            | .patch | split("\n")[]
            | capture("^@@ -[0-9,]+ \\+(?<start>[0-9]+)(,(?<count>[0-9]+))? @@")
            | (.start | tonumber) as $start
            | {path: $path, start: $start, end: ($start + (.count // "1" | tonumber) - 1)}' \
            >"${work}/ranges.jsonl"
fi

# The suggestions that fit a range and are not open already.
jq -c --slurpfile ranges "${work}/ranges.jsonl" --slurpfile threads "${work}/threads.jsonl" "${same}"'
    . as $suggestion
    | select(any($ranges[]; .path == $suggestion.path
        and .start <= ($suggestion.start_line // $suggestion.line) and $suggestion.line <= .end))
    | select(any($threads[]; (.outdated | not) and same(.; $suggestion)) | not)
    | del(.tool)' \
    "${work}/suggestions.jsonl" >"${work}/comments.jsonl"

rm -f "${PLAN_DIR}/review.json" "${PLAN_DIR}/retire.tsv"
if [[ -s ${work}/comments.jsonl ]]; then
    jq -s --arg sha "${HEAD_SHA}" '{
        commit_id: $sha,
        event: "COMMENT",
        body: "The formatters would change the lines below. Press \"Apply suggestion\" to take one change, or add several to a batch and commit them together. Changes outside the lines this pull request touches are only in the lint report comment.",
        comments: .}' "${work}/comments.jsonl" >"${PLAN_DIR}/review.json"
    posted=$(wc -l <"${work}/comments.jsonl")
    total=$(wc -l <"${work}/hunks.jsonl")
    echo "plan: post ${posted} of ${total} formatter hunks as suggestions"
fi
if [[ -s ${work}/retire.tsv ]]; then
    cp "${work}/retire.tsv" "${PLAN_DIR}/retire.tsv"
    retired=$(wc -l <"${work}/retire.tsv")
    echo "plan: retire ${retired} suggestion threads that no longer apply"
fi

has_work=false
if [[ -f ${PLAN_DIR}/review.json || -f ${PLAN_DIR}/retire.tsv ]]; then
    has_work=true
fi
echo "work=${has_work}" | tee -a "${GITHUB_OUTPUT}"
