#!/usr/bin/env bash
# Require the comment "# vX.Y.Z" on every SHA pin, or the documented exception,
# and find the comment it should be.
#
# Usage: check-pin-comments.sh | annotate-gcc.sh
# Run from the repository root. Checks every "uses: owner/repo[/path]@<sha>" in
# .github/workflows/*.y{a,}ml and .github/actions/*/action.y{a,}ml, whatever
# the action; the line must end with exactly "# vX.Y.Z" (digits only), or with
# "# <ref>" under the exception for an upstream that publishes no vX.Y.Z tag.
# The exception is a marker line directly above the "uses:" line, holding only
# the indentation of that line (the column of its first non-space character)
# and the text:
#   # pin-comment: no vX.Y.Z tag upstream
#   - uses: owner/repo@<sha> # <ref>
# where <ref> is the upstream tag or branch the commit was taken from. The
# marker is not on the "uses:" line, because zizmor reads everything after the
# first "#" there as the version. The exception is accepted only while no
# vX.Y.Z tag of that repository points at the pinned commit; when one does, it
# is an error and the fix is "# vX.Y.Z" and no marker. Also an error: the old
# inline form, a marker that is not directly above a pin, is indented
# differently from it or has other text, and a marker above a pin whose
# comment is not "# <ref>" (a vX.Y.Z or no single word).
# Env:
#   WRITE_PINS_DIFF  "true" to write the suggested fixes to PINS_DIFF, "false"
#                    not to; anything else is an error. Pass true only where
#                    something reads the file: the suggestion plan of a pull
#                    request.
#   PINS_DIFF        file for the suggested fixes, as a unified diff with one
#                    hunk per fixable line (shaped for diff-hunks.sh). Always
#                    required; with WRITE_PINS_DIFF=false it is not touched.
#                    With true it is replaced only when the check completes.
# Prints one gcc-style finding per failing line, with the source line. For a
# pin that is not the inline form it asks "git ls-remote --tags" for the
# vX.Y.Z tags that point at the pinned commit (annotated tags by their peeled
# commit), takes the highest by "sort -V" and suggests replacing only the
# comment with it, and removing the marker above when there is one; with no
# such tag there is no suggestion. The inline form gets the move to its own
# line as the suggestion. Only failing lines and exceptions are looked up.
# Exits 1 when any line fails. The finding's message says what is wrong with
# the line and what the fix changes; the same message is the note on the fix's
# hunk in PINS_DIFF (text after the closing "@@"), which becomes the text of
# the suggestion.
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

# The text of the marker line, which pin-lines.sh recognizes too.
marker="# pin-comment: no vX.Y.Z tag upstream"

# Print the hunk range of $2 lines from line $1: "N" for one line, else "N,C".
range() {
    if (($2 == 1)); then echo "$1"; else echo "$1,$2"; fi
}

# Print member $2 of the JSON object $1.
field() {
    jq -r --arg name "$2" '.[$name]' <<<"$1"
}

shopt -s nullglob
files=(.github/workflows/*.y{a,}ml .github/actions/*/action.y{a,}ml)

status=0
for file in "${files[@]}"; do
    failing=$("${scripts}/pin-lines.sh" <"${file}" | jq -c 'select(.kind == "stray" or .version == null or .marker)')
    [[ -n ${failing} ]] || continue
    while IFS= read -r pin; do
        line=$(field "${pin}" line)
        text=$(field "${pin}" text)
        indent=$(field "${pin}" indent)
        kind=$(field "${pin}" kind)

        if [[ ${kind} == stray ]]; then
            reason=$(field "${pin}" reason)
            expected=$(field "${pin}" expected)
            case "${reason}" in
                text)
                    message="this line starts with \"# pin-comment:\" but is not the marker; the marker line holds only the indentation of the \"uses:\" line below and exactly \"${marker}\""
                    ;;
                target)
                    message='the pin-comment marker is not directly above a SHA-pinned "uses:" line; put it on the line right before the "uses:" line it applies to, with no line between, or remove it'
                    ;;
                *)
                    message="the pin-comment marker is indented ${#indent} spaces, but the \"uses:\" line below is indented ${expected} spaces; indent the marker with exactly ${expected} spaces, aligned with the first non-space character of the \"uses:\" line (the \"-\" of \"- uses:\", or \"uses\" under \"- name:\")"
                    ;;
            esac
            printf '%s:%s:%s: error: %s. [pin-comment]\n%s\n\n' \
                "${file}" "${line}" "$((${#indent} + 1))" "${message}" "${text}"
            status=1
            continue
        fi

        action=$(field "${pin}" action)
        sha=$(field "${pin}" sha)
        prefix=$(field "${pin}" prefix)
        comment=$(field "${pin}" comment)
        exception=$(field "${pin}" exception)
        inline=$(field "${pin}" inline)
        marked=$(field "${pin}" marker)
        pin_name="${action}@${sha:0:7}"
        # The fix as hunk "-old +new" lines: start, old count, new count, old
        # and new lines.
        start=${line}
        old_count=1
        new_count=1
        old="-${text}"
        new=""

        if [[ ${inline} == true ]]; then
            message="${pin_name} has the pin-comment marker on the \"uses:\" line, but zizmor reads everything after the first \"#\" there as the version; move the marker to its own line directly above, indented like the \"uses:\" line, so that the \"uses:\" line ends with \"# <ref>\" only"
            inline_ref=$(field "${pin}" inline_ref)
            if [[ ${inline_ref} != null ]]; then
                message+=" (here \"${marker}\" above, and \"# ${inline_ref}\" at the end of the line)"
                new_count=2
                new="+${indent}${marker}"$'\n'"+${prefix} # ${inline_ref}"
            fi
            message+="."
            tag=""
        elif [[ ${marked} == true && ${exception} == false ]]; then
            message="${pin_name} has the pin-comment marker above, which only applies to a line that ends with \"# <ref>\" (one word, no vX.Y.Z), but its comment is \"${comment}\"; remove the marker, or end the line with the upstream tag or branch as \"# <ref>\"."
            tag=""
        else
            IFS=/ read -r owner repo _ <<<"${action}"
            tag=$(git ls-remote --tags "https://github.com/${owner}/${repo}" |
                awk -v sha="${sha}" '$1 == sha {
                    sub("^refs/tags/", "", $2)
                    sub("\\^\\{\\}$", "", $2)
                    if ($2 ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/) print $2
                }' | sort -V | tail -n 1)

            if [[ ${exception} == true ]]; then
                # Allowed only while upstream has no vX.Y.Z tag at this commit.
                [[ -n ${tag} ]] || continue
                problem="${pin_name} claims \"no vX.Y.Z tag upstream\", but the exception is unnecessary"
                change="remove the marker line above and change the comment to"
                start=$((line - 1))
                old_count=2
                old="-${indent}${marker}"$'\n'"-${text}"
            elif [[ -z ${comment} ]]; then
                problem="${pin_name} has no version comment"
                change=add
            else
                problem="${pin_name} has the comment \"${comment}\", but it must be the exact tag"
                change="change it to"
            fi
            if [[ -n ${tag} ]]; then
                message="${problem}; ${tag} points at this commit, so the fix is to ${change} \"# ${tag}\"."
                new="+${prefix} # ${tag}"
            else
                message="${problem}, and no vX.Y.Z tag of ${owner}/${repo} points at this commit; every pin needs exactly \"# vX.Y.Z\", or, when upstream publishes no vX.Y.Z tag, the line \"${marker}\" directly above the \"uses:\" line and \"# <ref>\" at the end of it."
            fi
        fi
        if [[ -n ${new} ]]; then
            old_range=$(range "${start}" "${old_count}")
            new_range=$(range "${start}" "${new_count}")
            printf -- '--- %s\n+++ %s\n@@ -%s +%s @@ %s\n%s\n%s\n' \
                "${file}" "${file}" "${old_range}" "${new_range}" "${message}" "${old}" "${new}" \
                >>"${work}/fixes.diff"
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
