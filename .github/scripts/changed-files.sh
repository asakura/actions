#!/usr/bin/env bash
# Decide which lint tools must run, from the files a pull request changes.
#
# Usage: changed-files.sh
# Env:
#   EVENT_NAME         github.event_name.
#   PR_NUMBER          pull request number (pull_request only).
#   GITHUB_REPOSITORY  owner/name (pull_request only).
#   GITHUB_OUTPUT      file receiving the outputs.
#   GH_TOKEN           token with pull-requests: read (pull_request only).
# Outputs (true/false):
#   workflows  workflow, action, script or actionlint config files changed:
#              run actionlint and zizmor on every workflow.
#   scripts    a .github/scripts/**/*.sh file changed: run shellcheck and shfmt
#              on every script, and every script test.
#   markdown   a *.md file changed: run mdformat on every tracked Markdown
#              file.
# Outside pull_request events everything is true. A change to _lint.yml itself
# also turns everything on. The file list comes from the pull requests API, so
# no git history or checkout credentials are needed.
set -euo pipefail

: "${EVENT_NAME:?EVENT_NAME is required}"
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

workflows=false
scripts=false
markdown=false

if [[ ${EVENT_NAME} != pull_request ]]; then
    workflows=true
    scripts=true
    markdown=true
else
    : "${PR_NUMBER:?PR_NUMBER is required}"
    : "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"

    # Both the new and the previous name count, so renames and deletions
    # are seen too.
    files=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/files" \
        --jq '.[] | .filename, (.previous_filename // empty)')

    while IFS= read -r file; do
        case "${file}" in
            .github/workflows/_lint.yml)
                workflows=true
                scripts=true
                markdown=true
                ;;
            .github/workflows/* | .github/scripts/* | .github/actionlint.yaml | .github/actionlint.yml | action.yml | action.yaml | */action.yml | */action.yaml)
                workflows=true
                ;;
            *) ;;
        esac
        case "${file}" in
            .github/scripts/*.sh) scripts=true ;;
            *) ;;
        esac
        case "${file}" in
            *.md) markdown=true ;;
            *) ;;
        esac
    done <<<"${files}"
fi

printf '%s\n' "workflows=${workflows}" "scripts=${scripts}" "markdown=${markdown}" | tee -a "${GITHUB_OUTPUT}"
