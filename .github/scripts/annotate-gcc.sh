#!/usr/bin/env bash
# Echo gcc-style findings and add a GitHub annotation per finding.
#
# Usage: shellcheck -f gcc ... | annotate-gcc.sh
#        actionlint -format '<gcc-style template>' | annotate-gcc.sh
# Reads stdin; every line is passed through unchanged, and each
# "file:line:col: level: message" line is followed by an
# "::error|warning|notice file=...,line=...,col=...::message" command.
set -euo pipefail

pattern='^([^:]+):([0-9]+):([0-9]+): ([a-z]+): (.*)$'

while IFS= read -r line; do
    printf '%s\n' "${line}"
    if [[ ${line} =~ ${pattern} ]]; then
        level=${BASH_REMATCH[4]}
        case "${level}" in
            error) ;;
            warning) ;;
            *) level=notice ;;
        esac
        printf '::%s file=%s,line=%s,col=%s::%s\n' \
            "${level}" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" \
            "${BASH_REMATCH[3]}" "${BASH_REMATCH[5]}"
    fi
done
