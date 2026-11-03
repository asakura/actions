#!/usr/bin/env bash
# Keep the single lint report comment on a pull request in sync with lint.
# Comments are never deleted: a failure report is a record.
#
# Usage: pr-comment.sh find|sync
#   find  writes active=true|false to GITHUB_OUTPUT: whether the pull request
#         has an active lint comment, which a passing run must resolve.
#   sync  creates, updates or resolves the comment (below).
# Env (both):
#   GITHUB_REPOSITORY  owner/name.
#   PR_NUMBER          pull request number.
#   GH_TOKEN           token with pull-requests: read (find) or write (sync).
# Env (find):
#   GITHUB_OUTPUT      file receiving the output.
# Env (sync):
#   HEAD_SHA           head commit the lint run checked.
#   LINT_RESULT        needs.lint.result of the lint job.
#   RUN_URL            URL of the workflow run, linked from resolution notes.
#   REPORT_FILE        markdown report produced by lint-report.sh; read only
#                      when lint did not pass.
# Active comments are found by a hidden marker and authored by
# github-actions[bot] (the legacy unsuffixed marker is matched too).
# When lint did not pass, the first active comment is updated, or one is
# created if none exists. When lint passed, nothing is posted; each active
# comment is edited to say it is resolved, keeps its previous report in a
# details block, and is minimized as RESOLVED. Extra active comments (from runs
# that raced to create one) are edited to point at the kept comment and
# minimized as DUPLICATE. Edited comments carry the resolved marker instead of
# the active one, so later runs ignore them and a later failure posts a fresh
# comment. A run whose HEAD_SHA is no longer the pull request's head (a re-run
# of an old run) changes nothing.
set -euo pipefail

mode=${1:?usage: pr-comment.sh find|sync}
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"

# The active marker must not be a substring of the resolved one, or the lookup
# would find resolved comments.
marker='<!-- asakura-actions-lint-report:active -->'
legacy_marker='<!-- asakura-actions-lint-report -->'
resolved_marker='<!-- asakura-actions-lint-report:resolved -->'
max_chars=65000

# Print the active comments, one tab-separated line each: id, node_id,
# html_url. Callers capture it into a variable first, so a failed request stops
# the script instead of looking like "no comments".
list_active_comments() {
    gh api --paginate "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
        --jq ".[] | select(.user.login == \"github-actions[bot]\" and (.body | (contains(\"${marker}\") or contains(\"${legacy_marker}\")))) | [.id, .node_id, .html_url] | @tsv"
}

case "${mode}" in
    find)
        : "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
        listing=$(list_active_comments)
        active=false
        if [[ -n ${listing} ]]; then
            active=true
        fi
        echo "active=${active}" | tee -a "${GITHUB_OUTPUT}"
        exit 0
        ;;
    sync) ;;
    *)
        echo "unknown mode: ${mode}; expected find or sync" >&2
        exit 2
        ;;
esac

: "${HEAD_SHA:?HEAD_SHA is required}"
: "${LINT_RESULT:?LINT_RESULT is required}"
: "${RUN_URL:?RUN_URL is required}"

current_sha=$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}" --jq '.head.sha')
if [[ ${current_sha} != "${HEAD_SHA}" ]]; then
    echo "lint ran on ${HEAD_SHA}, but the pull request head is ${current_sha}; leaving the comment alone"
    exit 0
fi

listing=$(list_active_comments)
ids=()
node_ids=()
urls=()
if [[ -n ${listing} ]]; then
    while IFS=$'\t' read -r id node_id url; do
        ids+=("${id}")
        node_ids+=("${node_id}")
        urls+=("${url}")
    done <<<"${listing}"
fi

bodyfile=$(mktemp)
trap 'rm -f "${bodyfile}"' EXIT

# Edit comment $1 so it starts with the note $2 and keeps its previous body in
# a details block, under the resolved marker; then minimize it (node id $3)
# with classifier $4.
retire_comment() {
    local id=$1 note=$2 node_id=$3 classifier=$4 previous head tail budget
    previous=$(gh api "repos/${GITHUB_REPOSITORY}/issues/comments/${id}" --jq '.body')
    previous=${previous//"${marker}"/}
    previous=${previous//"${legacy_marker}"/}
    head="${resolved_marker}"$'\n'"${note}"$'\n\n<details><summary>previous report</summary>\n\n'
    tail=$'\n\n</details>'
    budget=$((max_chars - ${#head} - ${#tail} - 50))
    if ((${#previous} > budget)); then
        previous="${previous:0:budget}"$'\n[... previous report truncated ...]'
    fi
    printf '%s%s%s\n' "${head}" "${previous}" "${tail}" >"${bodyfile}"
    gh api --method PATCH "repos/${GITHUB_REPOSITORY}/issues/comments/${id}" \
        -F "body=@${bodyfile}" --silent
    echo "edited comment ${id}: ${note}"
    gh api graphql \
        -f query="mutation(\$id: ID!) { minimizeComment(input: {subjectId: \$id, classifier: ${classifier}}) { minimizedComment { isMinimized } } }" \
        -F "id=${node_id}" --silent
    echo "minimized comment ${id} as ${classifier}"
}

if [[ ${LINT_RESULT} == success ]]; then
    if ((${#ids[@]} == 0)); then
        echo "lint passed and there is no comment to resolve"
    fi
    for i in "${!ids[@]}"; do
        retire_comment "${ids[i]}" "Resolved: lint passed on ${HEAD_SHA} (${RUN_URL})." \
            "${node_ids[i]}" RESOLVED
    done
    exit 0
fi

: "${REPORT_FILE:?REPORT_FILE is required}"
body="${marker}"$'\n'"$(cat "${REPORT_FILE}")"
if ((${#body} > max_chars)); then
    body="${body:0:max_chars}"$'\n[... report truncated ...]'
fi
printf '%s\n' "${body}" >"${bodyfile}"

if ((${#ids[@]} > 0)); then
    gh api --method PATCH "repos/${GITHUB_REPOSITORY}/issues/comments/${ids[0]}" \
        -F "body=@${bodyfile}" --silent
    echo "updated comment ${ids[0]}"
    for ((i = 1; i < ${#ids[@]}; i++)); do
        retire_comment "${ids[i]}" "Duplicate of ${urls[0]}." "${node_ids[i]}" DUPLICATE
    done
else
    gh api --method POST "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
        -F "body=@${bodyfile}" --silent
    echo "created comment"
fi
