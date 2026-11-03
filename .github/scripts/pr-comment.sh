#!/usr/bin/env bash
# Keep the single lint report comment on a pull request in sync with lint.
#
# Usage: pr-comment.sh
# Env:
#   GITHUB_REPOSITORY  owner/name.
#   PR_NUMBER          pull request number.
#   HEAD_SHA           head commit the lint run checked.
#   LINT_RESULT        needs.lint.result of the lint job.
#   REPORT_FILE        markdown report produced by lint-report.sh; read only
#                      when lint did not pass.
#   GH_TOKEN           token with pull-requests: write.
# The comment is found by a hidden marker and authored by github-actions[bot].
# When lint did not pass, it is updated, or created if missing. When lint
# passed, it is deleted, so a passing pull request carries no lint comment.
# Extra marker comments (from runs that raced to create one) are deleted. A run
# whose HEAD_SHA is no longer the pull request's head (a re-run of an old run)
# changes nothing.
set -euo pipefail

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${HEAD_SHA:?HEAD_SHA is required}"
: "${LINT_RESULT:?LINT_RESULT is required}"

marker='<!-- asakura-actions-lint-report -->'
max_chars=65000

current_sha=$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}" --jq '.head.sha')
if [[ ${current_sha} != "${HEAD_SHA}" ]]; then
    echo "lint ran on ${HEAD_SHA}, but the pull request head is ${current_sha}; leaving the comment alone"
    exit 0
fi

# Listed into a variable first, so a failed request stops the script instead
# of looking like "no comments" and creating a duplicate.
listing=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
    --jq ".[] | select(.user.login == \"github-actions[bot]\" and (.body | contains(\"${marker}\"))) | .id")
ids=()
if [[ -n ${listing} ]]; then
    mapfile -t ids <<<"${listing}"
fi

# Delete the given comment ids.
delete_comments() {
    local id
    for id in "$@"; do
        gh api --method DELETE "repos/${GITHUB_REPOSITORY}/issues/comments/${id}" --silent
        echo "deleted comment ${id}"
    done
}

if [[ ${LINT_RESULT} == success ]]; then
    if ((${#ids[@]} == 0)); then
        echo "lint passed and there is no comment to delete"
    fi
    delete_comments "${ids[@]}"
    exit 0
fi

: "${REPORT_FILE:?REPORT_FILE is required}"
body="${marker}"$'\n'"$(cat "${REPORT_FILE}")"
if ((${#body} > max_chars)); then
    body="${body:0:max_chars}"$'\n[... report truncated ...]'
fi

bodyfile=$(mktemp)
trap 'rm -f "${bodyfile}"' EXIT
printf '%s\n' "${body}" >"${bodyfile}"

if ((${#ids[@]} > 0)); then
    gh api --method PATCH "repos/${GITHUB_REPOSITORY}/issues/comments/${ids[0]}" \
        -F "body=@${bodyfile}" --silent
    echo "updated comment ${ids[0]}"
    delete_comments "${ids[@]:1}"
else
    gh api --method POST "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
        -F "body=@${bodyfile}" --silent
    echo "created comment"
fi
