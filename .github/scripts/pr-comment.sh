#!/usr/bin/env bash
# Keep the single lint report comment on a pull request in sync with lint.
#
# Usage: pr-comment.sh
# Env:
#   GITHUB_REPOSITORY  owner/name.
#   PR_NUMBER          pull request number.
#   LINT_RESULT        needs.lint.result of the lint job.
#   REPORT_FILE        markdown report produced by lint-report.sh.
#   GH_TOKEN           token with pull-requests: write.
# The comment is found by a hidden marker and authored by github-actions[bot].
# When lint did not pass, it is updated, or created if missing. When lint
# passed, it is deleted, so a passing pull request carries no lint comment.
set -euo pipefail

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${LINT_RESULT:?LINT_RESULT is required}"
: "${REPORT_FILE:?REPORT_FILE is required}"

marker='<!-- asakura-actions-lint-report -->'
max_chars=65000

ids=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
    --jq ".[] | select(.user.login == \"github-actions[bot]\" and (.body | contains(\"${marker}\"))) | .id")
id=${ids%%$'\n'*}

if [[ ${LINT_RESULT} == success ]]; then
    if [[ -z ${id} ]]; then
        echo "lint passed and there is no comment to delete"
        exit 0
    fi
    gh api --method DELETE "repos/${GITHUB_REPOSITORY}/issues/comments/${id}" --silent
    echo "deleted comment ${id}"
    exit 0
fi

body="${marker}"$'\n'"$(cat "${REPORT_FILE}")"
if ((${#body} > max_chars)); then
    body="${body:0:max_chars}"$'\n[... report truncated ...]'
fi

bodyfile=$(mktemp)
trap 'rm -f "${bodyfile}"' EXIT
printf '%s\n' "${body}" >"${bodyfile}"

if [[ -n ${id} ]]; then
    gh api --method PATCH "repos/${GITHUB_REPOSITORY}/issues/comments/${id}" \
        -F "body=@${bodyfile}" --silent
    echo "updated comment ${id}"
else
    gh api --method POST "repos/${GITHUB_REPOSITORY}/issues/${PR_NUMBER}/comments" \
        -F "body=@${bodyfile}" --silent
    echo "created comment"
fi
