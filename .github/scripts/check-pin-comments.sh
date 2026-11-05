#!/usr/bin/env bash
# Require the comment "# vX.Y.Z" on every SHA pin, and find the one it should be.
#
# Usage: check-pin-comments.sh | annotate-gcc.sh
# Run from the repository root. Checks every "uses: owner/repo[/path]@<sha>" in
# .github/workflows/*.y{a,}ml and .github/actions/*/action.y{a,}ml, whatever
# the action; the line must end with exactly "# vX.Y.Z" (digits only).
# Env:
#   WRITE_PINS_DIFF  "true" to write the suggested fixes to PINS_DIFF, "false"
#                    not to; anything else is an error. Pass true only where
#                    something reads the file: the suggestion plan of a pull
#                    request.
#   PINS_DIFF        file for the suggested fixes, as a unified diff with one
#                    hunk per fixable line (shaped for diff-hunks.sh). Always
#                    required; with WRITE_PINS_DIFF=false it is not touched.
#                    With true it is replaced only when the check completes.
# Prints one gcc-style finding per failing line, with the source line. For each
# one it asks "git ls-remote --tags" for the vX.Y.Z tags that point at the
# pinned commit (annotated tags by their peeled commit), takes the highest by
# "sort -V" and suggests replacing only the comment with it; with no such tag
# there is no suggestion. Only failing lines are looked up. Exits 1 when any
# line fails. The finding's message says what is wrong with the line and what
# the fix changes; the same message is the note on the fix's hunk in PINS_DIFF
# (text after the closing "@@"), which becomes the text of the suggestion.
set -euo pipefail

: "${PINS_DIFF:?PINS_DIFF is required}"
: "${WRITE_PINS_DIFF:?WRITE_PINS_DIFF is required}"
case "${WRITE_PINS_DIFF}" in
    true | false) ;;
    *)
        echo "check-pin-comments.sh: WRITE_PINS_DIFF must be true or false, not \"${WRITE_PINS_DIFF}\"" >&2
        exit 2
        ;;
esac

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

        pin="${action}@${sha:0:7}"
        if [[ -z ${comment} ]]; then
            problem="${pin} has no version comment"
            change=add
        else
            problem="${pin} has the comment \"${comment}\", but it must be the exact tag"
            change="change it to"
        fi
        if [[ -n ${tag} ]]; then
            message="${problem}; ${tag} points at this commit, so the fix is to ${change} \"# ${tag}\"."
            printf -- '--- %s\n+++ %s\n@@ -%s +%s @@ %s\n-%s\n+%s # %s\n' \
                "${file}" "${file}" "${line}" "${line}" "${message}" "${text}" "${prefix}" "${tag}" \
                >>"${work}/fixes.diff"
        else
            message="${problem}, and no vX.Y.Z tag of ${owner}/${repo} points at this commit; every pin needs exactly \"# vX.Y.Z\"."
        fi
        printf '%s:%s:%s: error: %s [pin-comment]\n%s\n\n' \
            "${file}" "${line}" "$((${#prefix} + 1))" "${message}" "${text}"
        status=1
    done <<<"${failing}"
done

if [[ ${WRITE_PINS_DIFF} == true ]]; then
    mv "${work}/fixes.diff" "${PINS_DIFF}"
fi
exit "${status}"
