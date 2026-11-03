#!/usr/bin/env bash
# Offer shfmt and mdformat fixes as suggested changes in a pull request review,
# and retire the suggestions that no longer apply. Comments are never deleted:
# a suggestion that no longer applies gets a reply saying why, then its comment
# is minimized (not the thread resolved: resolving a thread needs a token with
# contents: write, minimizing needs only pull-requests: write).
#
# Usage: pr-suggestions.sh find|sync
#   find  writes work=true|false to GITHUB_OUTPUT: whether sync has anything to
#         do, that is a formatter diff to suggest or an active suggestion
#         thread to retire.
#   sync  posts new suggestions in ONE review and retires stale threads.
#
# Pure steps, usable without network (stdin to stdout, for tests):
#   parse TOOL          unified diff of TOOL (shfmt|mdformat) to one JSON hunk
#                       per line: tool, path (repo-relative), start and end
#                       (old-side lines, which are RIGHT-side lines of the pull
#                       request head), old and new (arrays of lines), marker.
#   ranges              the pulls/{n}/files JSON to "path<TAB>start<TAB>end",
#                       the RIGHT-side line range of each hunk of the pull
#                       request diff.
#   fit RANGES_FILE     keep the hunks whose whole range lies in one range.
#   matches HEAD_FILE   keep the hunks whose old lines equal the lines of
#                       HEAD_FILE at start..end (the file at the head commit).
#   render              hunks to review comments (path, line, side, body).
#
# Env (find and sync):
#   GITHUB_REPOSITORY  owner/name.
#   PR_NUMBER          pull request number.
#   GH_TOKEN           token with pull-requests: read (find) or write (sync).
#   LINT_DIR           directory with the shfmt.txt and mdformat.txt outputs
#                      (default $RUNNER_TEMP/lint). A tool whose file is missing
#                      did not run.
# Env (find):
#   GITHUB_OUTPUT      file receiving the output.
# Env (sync):
#   HEAD_SHA           head commit the lint run checked.
#   LINT_RESULT        needs.lint.result of the lint job.
#   MAX_SUGGESTIONS    cap per review (default 50); the rest stay in the lint
#                      comment only.
# The lint job checks out the merge commit, so a hunk is suggested only when its
# old lines equal the same lines of the head commit. A hunk is posted only when
# it lies inside one hunk of the pull request diff (GitHub rejects comments
# elsewhere); the others stay in the lint comment, which shows the full diff.
# Our review comments are found by a hidden marker on their first line. A finding
# whose marker is on an active, current thread is not posted again. A thread
# is active when it is not resolved (a person may resolve one by hand), its
# first comment is ours and has the marker, and that comment is not minimized.
# An active thread that is outdated, whose finding is gone (only when its tool
# ran to the end), or that duplicates another gets a reply saying why (unless
# it already has one) and its first comment is minimized as RESOLVED, or as
# DUPLICATE. One thread failing does not stop the others; the script then exits
# 1 and says what failed. A
# run whose HEAD_SHA is no longer the pull request's head changes nothing.
set -euo pipefail

marker_prefix='<!-- lint-suggestion '
tools=(shfmt mdformat)

# Print the lines of the arguments as a JSON array of strings.
json_array() {
    if (($# == 0)); then
        echo '[]'
    else
        printf '%s\0' "$@" | jq -Rs 'split("\u0000")[:-1]'
    fi
}

# Print the JSON hunk of tool $1 and file $2 for the lines in arrays ${kinds[@]},
# ${texts[@]} and ${oldnos[@]} (set by parse_diff), between indexes $3 and $4.
emit_hunk() {
    local tool=$1 path=$2 first=$3 last=$4 i
    local -a old=() new=()
    local start=0 end=0
    # A pure insertion has no old line to anchor to: take a neighbouring
    # context line, which stays unchanged in the suggestion.
    local has_old=false
    for ((i = first; i <= last; i++)); do
        if [[ ${kinds[i]} != + ]]; then
            has_old=true
        fi
    done
    if [[ ${has_old} == false ]]; then
        if ((first > 0)); then
            first=$((first - 1))
        elif ((last + 1 < ${#kinds[@]})) && [[ ${kinds[last + 1]} == ' ' ]]; then
            last=$((last + 1))
        fi
    fi
    for ((i = first; i <= last; i++)); do
        case "${kinds[i]}" in
            ' ')
                old+=("${texts[i]}")
                new+=("${texts[i]}")
                ;;
            -) old+=("${texts[i]}") ;;
            +) new+=("${texts[i]}") ;;
            *) ;;
        esac
    done
    if ((${#old[@]} > 0)); then
        # The first line of the range is the first old line in it.
        for ((i = first; i <= last; i++)); do
            if [[ ${kinds[i]} != + ]]; then
                start=${oldnos[i]}
                break
            fi
        done
        end=$((start + ${#old[@]} - 1))
    fi
    local text="" sha
    if ((${#new[@]} > 0)); then
        text=$(printf '%s\n' "${new[@]}")$'\n'
    fi
    sha=$(printf '%s' "${text}" | sha256sum | cut -d' ' -f1)
    local old_json new_json
    old_json=$(json_array "${old[@]}")
    new_json=$(json_array "${new[@]}")
    jq -nc --arg tool "${tool}" --arg path "${path}" \
        --argjson start "${start}" --argjson end "${end}" \
        --argjson old "${old_json}" --argjson new "${new_json}" \
        --arg marker "${marker_prefix}tool=${tool} path=${path} lines=${start}-${end} sha=${sha} -->" \
        '{tool: $tool, path: $path, start: $start, end: $end, old: $old, new: $new, marker: $marker}'
}

# Read a unified diff of tool $1 from stdin and print its hunks (see parse).
# The changed lines of a hunk are trimmed of the context diff adds around them.
parse_diff() {
    local tool=$1 path="" line label
    local -a kinds=() texts=() oldnos=()
    local rem_old=0 rem_new=0 cur_old=0 in_hunk=false
    local header='^@@ -([0-9]+)(,([0-9]+))? \+([0-9]+)(,([0-9]+))? @@'

    # Print the hunk collected so far, if any line changed.
    flush() {
        local i first=-1 last=-1
        for i in "${!kinds[@]}"; do
            if [[ ${kinds[i]} != ' ' ]]; then
                if ((first < 0)); then
                    first=${i}
                fi
                last=${i}
            fi
        done
        if ((first >= 0)); then
            emit_hunk "${tool}" "${path}" "${first}" "${last}"
        fi
        kinds=()
        texts=()
        oldnos=()
        in_hunk=false
    }

    while IFS= read -r line || [[ -n ${line} ]]; do
        if [[ ${in_hunk} == true ]]; then
            case "${line:0:1}" in
                ' ' | '')
                    kinds+=(' ')
                    texts+=("${line:1}")
                    oldnos+=("${cur_old}")
                    cur_old=$((cur_old + 1))
                    rem_old=$((rem_old - 1))
                    rem_new=$((rem_new - 1))
                    ;;
                -)
                    kinds+=(-)
                    texts+=("${line:1}")
                    oldnos+=("${cur_old}")
                    cur_old=$((cur_old + 1))
                    rem_old=$((rem_old - 1))
                    ;;
                +)
                    kinds+=(+)
                    texts+=("${line:1}")
                    oldnos+=("${cur_old}")
                    rem_new=$((rem_new - 1))
                    ;;
                *) ;; # "\ No newline at end of file"
            esac
            if ((rem_old <= 0 && rem_new <= 0)); then
                flush
            fi
        elif [[ ${line} =~ ${header} ]]; then
            cur_old=${BASH_REMATCH[1]}
            rem_old=${BASH_REMATCH[3]:-1}
            rem_new=${BASH_REMATCH[6]:-1}
            in_hunk=true
            if ((rem_old == 0 && rem_new == 0)); then
                in_hunk=false
            fi
        elif [[ ${line} == '+++ '* ]]; then
            # The new-file label, without a timestamp; mdformat-diff.sh labels
            # it "b/<path>", shfmt prints the path as given.
            label=${line#'+++ '}
            label=${label%%$'\t'*}
            if [[ ${tool} == mdformat ]]; then
                label=${label#b/}
            fi
            path=${label#./}
        fi
    done
}

# Read the pulls/{n}/files JSON from stdin and print the RIGHT-side line range
# of each diff hunk: path, first line, last line (tab-separated).
pr_ranges() {
    jq -r '.[] | select(.patch != null) | .filename as $f | .patch | split("\n")[]
        | select(startswith("@@"))
        | capture("^@@ -[0-9]+(,[0-9]+)? \\+(?<s>[0-9]+)(,(?<c>[0-9]+))? @@")
        | [$f, (.s | tonumber), ((.s | tonumber) + ((.c // "1") | tonumber) - 1)]
        | select(.[2] >= .[1]) | @tsv'
}

# Keep the hunks on stdin whose range lies inside one range of file $1.
fit_hunks() {
    local ranges_json
    ranges_json=$(mktemp)
    jq -Rn '[inputs | split("\t") | {f: .[0], s: (.[1] | tonumber), e: (.[2] | tonumber)}]' \
        <"$1" >"${ranges_json}"
    jq -c --slurpfile r "${ranges_json}" \
        'select(.start >= 1 and .start <= .end) as $h
        | select(any($r[0][]; .f == $h.path and .s <= $h.start and $h.end <= .e))'
    rm -f "${ranges_json}"
}

# Keep the hunks on stdin whose old lines equal lines start..end of file $1.
matching_hunks() {
    jq -c --rawfile head "$1" \
        '($head | split("\n")) as $lines
        | select($lines[.start - 1:.end] == .old)'
}

# Turn the hunks on stdin into review comments; also keeps the marker and tool.
render_comments() {
    jq -c '
        ([.new[] | scan("`+") | length] | max // 0) as $longest
        | (if $longest >= 3 then $longest + 1 else 3 end) as $n
        | ("`" * $n) as $fence
        | (.end - .start + 1) as $count
        | (if (.new | length) == 0 then
              (if $count == 1 then "\(.tool) would remove this line:" else "\(.tool) would remove these lines:" end)
          elif $count == 1 then "\(.tool) would format this line like this:"
          else "\(.tool) would format these lines like this:" end) as $sentence
        | {tool: .tool, marker: .marker, comment: ({
              path: .path,
              line: .end,
              side: "RIGHT",
              body: (.marker + "\n" + $sentence + "\n\n" + $fence + "suggestion\n"
                  + (if (.new | length) > 0 then (.new | join("\n")) + "\n" else "" end)
                  + $fence)
          } + (if .start < .end then {start_line: .start, start_side: "RIGHT"} else {} end))}'
}

# Print "yes" when the output file of tool $1 holds at least one hunk.
has_hunks() {
    local file="${lint_dir}/$1.txt"
    if [[ -f ${file} ]] && grep -q '^@@ ' "${file}"; then
        echo yes
    fi
}

# Print the active suggestion threads, one tab-separated line each: thread node
# id, isOutdated, id of the first comment, node id of the first comment,
# whether a later comment of ours already says why it is retired, marker.
# Callers capture
# it into a variable first, so a failed request stops the script instead of
# looking like "no threads".
list_threads() {
    : "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
    : "${PR_NUMBER:?PR_NUMBER is required}"
    local query
    query=$(
        cat <<'EOF'
query($owner: String!, $name: String!, $number: Int!, $endCursor: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      reviewThreads(first: 100, after: $endCursor) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id
          isResolved
          isOutdated
          comments(first: 20) { nodes { id databaseId body isMinimized author { login } } }
        }
      }
    }
  }
}
EOF
    )
    gh api graphql --paginate \
        -F "owner=${GITHUB_REPOSITORY%%/*}" -F "name=${GITHUB_REPOSITORY#*/}" \
        -F "number=${PR_NUMBER}" -f "query=${query}" \
        --jq ".data.repository.pullRequest.reviewThreads.nodes[]
            | select(.isResolved == false and .comments.nodes[0].author.login == \"github-actions\"
                and .comments.nodes[0].isMinimized == false
                and (.comments.nodes[0].body | startswith(\"${marker_prefix}\")))
            | [.id, .isOutdated, .comments.nodes[0].databaseId, .comments.nodes[0].id,
                ([.comments.nodes[1:][] | select(.author.login == \"github-actions\" and (.body | test(\"^(Resolved|Duplicate)\")))] | length > 0),
                (.comments.nodes[0].body | split(\"\\n\")[0])]
            | @tsv"
}

mode=${1:?usage: pr-suggestions.sh find|sync|parse|ranges|fit|matches|render}
lint_dir=${LINT_DIR:-${RUNNER_TEMP:-/nonexistent}/lint}

case "${mode}" in
    parse)
        parse_diff "${2:?usage: pr-suggestions.sh parse shfmt|mdformat}"
        exit 0
        ;;
    ranges)
        pr_ranges
        exit 0
        ;;
    fit)
        fit_hunks "${2:?usage: pr-suggestions.sh fit RANGES_FILE}"
        exit 0
        ;;
    matches)
        matching_hunks "${2:?usage: pr-suggestions.sh matches HEAD_FILE}"
        exit 0
        ;;
    render)
        render_comments
        exit 0
        ;;
    find | sync) ;;
    *)
        echo "unknown mode: ${mode}; expected find or sync" >&2
        exit 2
        ;;
esac

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"

if [[ ${mode} == find ]]; then
    : "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
    work=false
    for tool in "${tools[@]}"; do
        found=$(has_hunks "${tool}")
        if [[ -n ${found} ]]; then
            work=true
        fi
    done
    # Only ask GitHub when the local files have not decided it already.
    if [[ ${work} == false ]]; then
        threads=$(list_threads)
        if [[ -n ${threads} ]]; then
            work=true
        fi
    fi
    echo "work=${work}" | tee -a "${GITHUB_OUTPUT}"
    exit 0
fi

: "${HEAD_SHA:?HEAD_SHA is required}"
: "${LINT_RESULT:?LINT_RESULT is required}"
max_suggestions=${MAX_SUGGESTIONS:-50}
short_sha=${HEAD_SHA:0:7}

current_sha=$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}" --jq '.head.sha')
if [[ ${current_sha} != "${HEAD_SHA}" ]]; then
    echo "lint ran on ${HEAD_SHA}, but the pull request head is ${current_sha}; leaving the suggestions alone"
    exit 0
fi

workdir=$(mktemp -d)
trap 'rm -rf "${workdir}"' EXIT

# Every hunk the formatters report, and whether each tool ran to the end: after
# a pass it did; after a failure it did when its output is empty or a diff (a
# crashed tool prints an error message instead).
: >"${workdir}/all.jsonl"
declare -A conclusive=()
for tool in "${tools[@]}"; do
    conclusive[${tool}]=false
    file="${lint_dir}/${tool}.txt"
    if [[ ${LINT_RESULT} == success ]]; then
        conclusive[${tool}]=true
    elif [[ -f ${file} ]]; then
        found=$(has_hunks "${tool}")
        if [[ ! -s ${file} || -n ${found} ]]; then
            conclusive[${tool}]=true
        fi
    fi
    if [[ -f ${file} ]]; then
        parse_diff "${tool}" <"${file}" >>"${workdir}/all.jsonl"
    fi
done
total=$(wc -l <"${workdir}/all.jsonl")

# The hunks that can be suggested: inside the pull request diff, and matching
# the head commit.
: >"${workdir}/fit.jsonl"
if ((total > 0)); then
    gh api --paginate "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/files" | pr_ranges >"${workdir}/ranges.tsv"
    fit_hunks "${workdir}/ranges.tsv" <"${workdir}/all.jsonl" >"${workdir}/inside.jsonl"
    jq -r '.path' "${workdir}/inside.jsonl" | sort -u >"${workdir}/paths"
    while IFS= read -r path; do
        encoded=$(jq -rn --arg p "${path}" '$p | split("/") | map(@uri) | join("/")')
        gh api -H 'Accept: application/vnd.github.raw+json' \
            "repos/${GITHUB_REPOSITORY}/contents/${encoded}?ref=${HEAD_SHA}" >"${workdir}/head-file"
        jq -c --arg p "${path}" 'select(.path == $p)' <"${workdir}/inside.jsonl" |
            matching_hunks "${workdir}/head-file" >>"${workdir}/fit.jsonl"
    done <"${workdir}/paths"
fi
fit_count=$(wc -l <"${workdir}/fit.jsonl")
echo "${total} formatter hunks, ${fit_count} can be suggested"

# Walk the active suggestion threads: keep one per current finding; retire the
# rest. A failed call is reported at the end and does not stop the walk.
threads=$(list_threads)
declare -A kept=()
failures=0
# Run gh with the arguments after $1 and set ok to true or false; on failure
# print "error: could not <$1>: <gh's message>" and count it.
ok=true
gh_or_report() {
    local what=$1 output
    shift
    ok=true
    if ! output=$(gh "$@" 2>&1); then
        echo "error: could not ${what}: ${output}" >&2
        failures=$((failures + 1))
        ok=false
    fi
}
# Reply on the thread (unless $4 says it has one) with the reason $5, then
# minimize its first comment (node id $3) with classifier $6. No reply, no
# minimizing: the reason always comes first.
retire_thread() {
    local thread_id=$1 comment_id=$2 node_id=$3 replied=$4 text=$5 classifier=$6
    if [[ ${replied} != true ]]; then
        gh_or_report "reply on thread ${thread_id}" api --method POST \
            "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/comments/${comment_id}/replies" \
            -f "body=${text}" --silent
        if [[ ${ok} == false ]]; then
            return 0
        fi
        echo "replied on thread ${thread_id}: ${text}"
    fi
    gh_or_report "minimize the suggestion on thread ${thread_id}" api graphql \
        -f query="mutation(\$id: ID!) { minimizeComment(input: {subjectId: \$id, classifier: ${classifier}}) { minimizedComment { isMinimized } } }" \
        -F "id=${node_id}" --silent
    if [[ ${ok} == false ]]; then
        return 0
    fi
    echo "minimized the suggestion on thread ${thread_id} as ${classifier}"
}
if [[ -n ${threads} ]]; then
    while IFS=$'\t' read -r thread_id outdated comment_id node_id replied marker; do
        thread_tool=""
        if [[ ${marker} =~ tool=([^[:space:]]+) ]]; then
            thread_tool=${BASH_REMATCH[1]}
        fi
        if [[ ${outdated} == true ]]; then
            retire_thread "${thread_id}" "${comment_id}" "${node_id}" "${replied}" \
                "Resolved: superseded; these lines changed at ${short_sha}." RESOLVED
        elif [[ -n ${kept[${marker}]:-} ]]; then
            retire_thread "${thread_id}" "${comment_id}" "${node_id}" "${replied}" \
                "Duplicate of an earlier suggestion." DUPLICATE
        elif jq -e --arg m "${marker}" 'select(.marker == $m)' "${workdir}/all.jsonl" >/dev/null; then
            kept[${marker}]=1
        elif [[ ${conclusive[${thread_tool}]:-false} == true ]]; then
            retire_thread "${thread_id}" "${comment_id}" "${node_id}" "${replied}" \
                "Resolved: ${thread_tool} no longer reports these lines at ${short_sha}." RESOLVED
        else
            echo "left thread ${thread_id} alone: ${thread_tool:-unknown tool} did not finish"
        fi
    done <<<"${threads}"
fi

# Exit 1 when a call above failed, after the review (if any) is posted.
finish() {
    if ((failures > 0)); then
        echo "${failures} call(s) failed; see the errors above." >&2
        exit 1
    fi
    exit 0
}

# Post what is new, in one review.
render_comments <"${workdir}/fit.jsonl" >"${workdir}/rendered.jsonl"
: >"${workdir}/new.jsonl"
while IFS= read -r rendered; do
    marker=$(jq -r '.marker' <<<"${rendered}")
    if [[ -z ${kept[${marker}]:-} ]]; then
        echo "${rendered}" >>"${workdir}/new.jsonl"
    fi
done <"${workdir}/rendered.jsonl"
new_count=$(wc -l <"${workdir}/new.jsonl")
if ((new_count == 0)); then
    echo "no new suggestions to post"
    finish
fi

over_cap=0
if ((new_count > max_suggestions)); then
    over_cap=$((new_count - max_suggestions))
    head -n "${max_suggestions}" "${workdir}/new.jsonl" >"${workdir}/capped.jsonl"
    mv "${workdir}/capped.jsonl" "${workdir}/new.jsonl"
fi
posted=$(wc -l <"${workdir}/new.jsonl")
unfit=$((total - fit_count))
used_tools=$(jq -rs 'map(.tool) | unique | join(" and ")' "${workdir}/new.jsonl")

review_body="${used_tools} would format the lines below differently. Press \"Apply suggestion\" on a comment to take its change, or add several to a batch and commit them together."
if ((unfit > 0)); then
    review_body+=$'\n\n'"${unfit} more formatter hunks cannot be suggested because they are outside the lines this pull request changes, or the lines differ at the head commit. The lint report comment shows every finding."
fi
if ((over_cap > 0)); then
    review_body+=$'\n\n'"Only the first ${max_suggestions} suggestions are posted; ${over_cap} more are in the lint report comment only."
fi

jq -s --arg sha "${HEAD_SHA}" --arg body "${review_body}" \
    '{commit_id: $sha, event: "COMMENT", body: $body, comments: map(.comment)}' \
    "${workdir}/new.jsonl" >"${workdir}/review.json"
gh api --method POST "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/reviews" \
    --input "${workdir}/review.json" --silent
echo "posted a review with ${posted} suggestions"
finish
