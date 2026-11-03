#!/usr/bin/env bash
# Require the comment "# vX.Y.Z" on every SHA pin, and find the one it should be.
#
# Usage: check-pin-comments.sh | annotate-gcc.sh
# Run from the repository root. Checks every "uses: owner/repo[/path]@<sha>" in
# .github/workflows/*.y{a,}ml and .github/actions/*/action.y{a,}ml, whatever
# the action; the line must end with exactly "# vX.Y.Z" (digits only).
# Env:
#   PINS_DIFF  file to write the suggested fixes into, as a unified diff with
#              one hunk per fixable line (shaped for diff-hunks.sh). It is
#              replaced only when the check completes.
# Prints one gcc-style finding per failing line, with the source line. For each
# one it asks "git ls-remote --tags" for the vX.Y.Z tags that point at the
# pinned commit (annotated tags by their peeled commit), takes the highest by
# "sort -V" and suggests replacing only the comment with it; with no such tag
# there is no suggestion. Only failing lines are looked up. Exits 1 when any
# line fails.
set -euo pipefail

: "${PINS_DIFF:?PINS_DIFF is required}"

scripts=$(dirname "$0")
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
: >"${work}/fixes.diff"

# Print member $2 of the JSON object $1.
field() {
    jq -r --arg name "$2" '.[$name]' <<<"$1"
}

shopt -s nullglob
files=(.github/workflows/*.y{a,}ml .github/actions/*/action.y{a,}ml)

status=0
for file in "${files[@]}"; do
    failing=$("${scripts}/pin-lines.sh" <"${file}" | jq -c 'select(.version == null)')
    [[ -n ${failing} ]] || continue
    while IFS= read -r pin; do
        line=$(field "${pin}" line)
        action=$(field "${pin}" action)
        sha=$(field "${pin}" sha)
        prefix=$(field "${pin}" prefix)
        text=$(field "${pin}" text)
        comment=$(field "${pin}" comment)

        IFS=/ read -r owner repo _ <<<"${action}"
        tag=$(git ls-remote --tags "https://github.com/${owner}/${repo}" |
            awk -v sha="${sha}" '$1 == sha {
                sub("^refs/tags/", "", $2)
                sub("\\^\\{\\}$", "", $2)
                if ($2 ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/) print $2
            }' | sort -V | tail -n 1)

        if [[ -z ${comment} ]]; then
            problem="has no comment"
        else
            problem="has the comment \"${comment}\""
        fi
        if [[ -n ${tag} ]]; then
            advice="${tag} points at this commit; use \"# ${tag}\""
            printf -- '--- %s\n+++ %s\n@@ -%s +%s @@\n-%s\n+%s # %s\n' \
                "${file}" "${file}" "${line}" "${line}" "${text}" "${prefix}" "${tag}" \
                >>"${work}/fixes.diff"
        else
            advice="no vX.Y.Z tag of ${owner}/${repo} points at this commit"
        fi
        printf '%s:%s:%s: error: %s@%s %s, but every pin needs exactly "# vX.Y.Z"; %s [pin-comment]\n%s\n\n' \
            "${file}" "${line}" "$((${#prefix} + 1))" "${action}" "${sha:0:7}" "${problem}" "${advice}" "${text}"
        status=1
    done <<<"${failing}"
done

mv "${work}/fixes.diff" "${PINS_DIFF}"
exit "${status}"
