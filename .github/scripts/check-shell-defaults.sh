#!/usr/bin/env bash
# Find hidden defaults for shell variables in scripts, workflows and actions.
#
# Usage: check-shell-defaults.sh | annotate-gcc.sh
# Run from the repository root. Searches every tracked file under .github, and
# the action.y{a,}ml files elsewhere, for a variable expansion with a default
# (dash, colon-dash, equals or colon-equals after the name). A caller's input
# must be required instead, so a missing one fails loudly.
# Prints one gcc-style finding per match, naming the variable or positional
# parameter, with the source line.
# Exits 1 when anything matches, and with git's status when git grep fails.
# The pattern is assembled from parts so that this file does not match it.
set -euo pipefail

dollar='\$'
brace='\{'
pattern="${dollar}${brace}([A-Za-z_][A-Za-z0-9_]*|[0-9]+):?[-=]"

# git grep exits 1 when nothing matches; anything higher is its own failure,
# which must not read as "no findings".
rc=0
matches=$(git grep --column -noE "${pattern}" -- \
    .github '**/action.yml' '**/action.yaml' 'action.yml' 'action.yaml') || rc=$?
if ((rc > 1)); then
    echo "check-shell-defaults.sh: git grep failed with exit status ${rc}" >&2
    exit "${rc}"
fi
[[ -n ${matches} ]] || exit 0

while IFS=: read -r file line column match; do
    # The match is the dollar, the brace, the name or number, then the dash,
    # colon-dash, equals or colon-equals.
    name=${match:2}
    name=${name%%[:=-]*}
    text=$(sed -n "${line}p" "${file}")
    if [[ ${name} =~ ^[0-9]+$ ]]; then
        subject="positional parameter ${name}"
        required="\${${name}:?<argument name> is required}"
    else
        subject=${name}
        required="\${${name}:?${name} is required}"
    fi
    printf '%s:%s:%s: error: hidden default for %s; make it required with %s [defaults]\n%s\n\n' \
        "${file}" "${line}" "${column}" "${subject}" "${required}" "${text}"
done <<<"${matches}"

exit 1
