#!/usr/bin/env bash
# Fail when a pull request changes the commit of a pin but not its version.
#
# Usage: check-pin-changes.sh | annotate-gcc.sh
# Run from the repository root, checked out at the pull request head.
# Env:
#   GITHUB_REPOSITORY  owner/name.
#   PR_NUMBER          pull request number.
#   BASE_SHA           base branch commit of the pull request event.
#   HEAD_SHA           head commit of the pull request.
#   GH_TOKEN           token with contents: read and pull-requests: read.
# For every workflow and action file the pull request changes, compares its
# "uses: ...@<sha> # vX.Y.Z" pins with the same file where the pull request
# branched off: a pin of the same action with the same version but another
# commit is an error. A release always has a new version, so this is a
# re-pointed tag or rewritten history. The old file comes from the contents
# API at the merge base (BASE_SHA may be newer than the branch point), which
# needs no more than contents: read. Prints gcc-style findings; exits 1 when
# there are any.
set -euo pipefail

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${BASE_SHA:?BASE_SHA is required}"
: "${HEAD_SHA:?HEAD_SHA is required}"

scripts=$(dirname "$0")

merge_base=$(gh api "repos/${GITHUB_REPOSITORY}/compare/${BASE_SHA}...${HEAD_SHA}" --jq '.merge_base_commit.sha')

# Changed workflow and action files that existed before, as "new path<TAB>old
# path" (they differ for a rename).
files=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/files" --jq '
    .[] | select(.status != "added" and .status != "removed")
    | select(.filename | test("^\\.github/(workflows/[^/]+|actions/[^/]+/action)\\.ya?ml$"))
    | [.filename, (.previous_filename // .filename)] | @tsv')

status=0
if [[ -n ${files} ]]; then
    while IFS=$'\t' read -r new_path old_path; do
        old=$(gh api -H 'Accept: application/vnd.github.raw+json' \
            "repos/${GITHUB_REPOSITORY}/contents/${old_path}?ref=${merge_base}" |
            "${scripts}/pin-lines.sh" | jq -s '.')
        # shellcheck disable=SC2094 # jq only gets the name, as a string; nothing is written.
        findings=$("${scripts}/pin-lines.sh" <"${new_path}" |
            jq -r --argjson old "${old}" --arg path "${new_path}" '
                select(.version != null) as $pin
                | ($old | map(select(.action == $pin.action and .version == $pin.version))) as $same
                | select(($same | length) > 0 and ($same | any(.sha == $pin.sha) | not))
                | "\($path):\($pin.line):\($pin.prefix | length): error: \($pin.action) changed from \($same | map(.sha[0:7]) | unique | join(", ")) to \($pin.sha[0:7]) but stays at \($pin.version): the same version must be the same commit, so a tag was re-pointed or history was rewritten [pin-changed]\n\($pin.text)\n"')
        if [[ -n ${findings} ]]; then
            printf '%s\n' "${findings}"
            status=1
        fi
    done <<<"${files}"
fi
exit "${status}"
