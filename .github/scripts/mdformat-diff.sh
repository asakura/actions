#!/usr/bin/env bash
# Show what mdformat would change in every tracked Markdown file.
#
# Usage: mdformat-diff.sh
# Run from the repository root. Prints one unified diff per file that is not
# formatted ("a/" is the file as committed, "b/" as mdformat writes it), the
# same way shfmt --diff does, and nothing for formatted files. Exits 1 when
# any file differs or mdformat itself fails (for example, on a missing file).
# Every behavior-affecting mdformat option is spelled out, so a change of its
# defaults cannot change the result: the archive has no extension or code
# formatter plugins, and these two options keep it that way.
set -euo pipefail

mdformat_options=(
    --wrap keep
    --number
    --end-of-line lf
    --no-extensions
    --no-codeformatters
)

# NUL-separated, so names with spaces are safe; a file keeps git's exit status
# visible, which process substitution would hide.
list=$(mktemp)
git ls-files -z -- '*.md' >"${list}"
files=()
while IFS= read -r -d '' file; do
    files+=("${file}")
done <"${list}"
rm -f "${list}"

status=0
for file in "${files[@]}"; do
    formatted=$(mktemp)
    # mdformat reads stdin when given "-", so the file itself is never written.
    if ! mdformat "${mdformat_options[@]}" - <"${file}" >"${formatted}"; then
        echo "mdformat-diff: mdformat failed on ${file}" >&2
        status=1
    elif ! diff -u --label "a/${file}" --label "b/${file}" "${file}" "${formatted}"; then
        status=1
    fi
    rm -f "${formatted}"
done
exit "${status}"
