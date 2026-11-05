#!/usr/bin/env bash
# Turn a formatter's unified diff into one JSON object per hunk.
#
# Usage: diff-hunks.sh TOOL PREFIX < diff
#   TOOL    the formatter that printed the diff; copied into every hunk.
#   PREFIX  what to strip from the "+++" file name to get the repository path:
#           "b/" for mdformat-diff.sh, "" for shfmt.
# Prints one line per hunk:
#   {"tool": TOOL, "path": PATH, "start": S, "end": E, "lines": [...],
#    "note": "..."}
# meaning: replace lines S..E of the file with "lines". "note" is the text
# after the closing "@@" of the hunk header, where a tool can say why it
# changes the lines (check-pin-comments.sh does); it is "" when the header has
# none, as with shfmt and mdformat. The hunk keeps the
# context lines diff puts around a change, so even a pure insertion has a line
# to anchor to. A hunk of a new file has start 0.
set -euo pipefail

tool=${1:?usage: diff-hunks.sh TOOL PREFIX}
prefix=${2?usage: diff-hunks.sh TOOL PREFIX}
header='^@@ -([0-9]+)(,([0-9]+))? \+[0-9]+(,([0-9]+))? @@( (.*))?$'

# Print one hunk: tool $1, path $2, first line $3, line count $4, note $5, new
# lines $6...
print_hunk() {
    jq -nc --arg tool "$1" --arg path "$2" --argjson start "$3" --argjson count "$4" --arg note "$5" \
        '{tool: $tool, path: $path, start: $start, end: ($start + $count - 1), lines: $ARGS.positional, note: $note}' \
        --args "${@:6}"
}

path=""
start=0
count=0
note=""
old_left=0
new_left=0
lines=()
while IFS= read -r line || [[ -n ${line} ]]; do
    if ((old_left > 0 || new_left > 0)); then
        # Inside a hunk: count lines down until both sides are complete.
        case "${line:0:1}" in
            ' ' | '')
                lines+=("${line:1}")
                old_left=$((old_left - 1))
                new_left=$((new_left - 1))
                ;;
            -) old_left=$((old_left - 1)) ;;
            +)
                lines+=("${line:1}")
                new_left=$((new_left - 1))
                ;;
            *) ;; # "\ No newline at end of file"
        esac
        if ((old_left == 0 && new_left == 0)); then
            print_hunk "${tool}" "${path}" "${start}" "${count}" "${note}" "${lines[@]}"
        fi
    elif [[ ${line} =~ ${header} ]]; then
        start=${BASH_REMATCH[1]}
        count=${BASH_REMATCH[3]:-1}
        old_left=${count}
        new_left=${BASH_REMATCH[5]:-1}
        note=${BASH_REMATCH[7]}
        lines=()
    elif [[ ${line} == '+++ '* ]]; then
        # The new file's name, without the timestamp some tools add.
        path=${line#'+++ '}
        path=${path%%$'\t'*}
        path=${path#"${prefix}"}
    fi
done
