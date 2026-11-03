#!/usr/bin/env bash
# Check that every reference to this repository from its own workflows and
# composite actions is a pinned, tagged commit on main.
#
# Usage: check-self-pins.sh [directory]
#        check-self-pins.sh | annotate-gcc.sh
# directory is the tree to scan (default "."). It looks at
# .github/workflows/*.y{a,}ml and .github/actions/*/action.y{a,}ml; README.md
# examples and local "./" uses are not self-pins and are ignored.
# Env:
#   GITHUB_REPOSITORY  owner/name of the repository whose self-pins are
#                      checked: the "uses:" pattern is built from it.
#   GH_TOKEN           token with contents: read, for the "gh api" calls.
# Every "uses: <GITHUB_REPOSITORY>[/<path>]@<ref>" must have:
#   1. a 40-character lowercase hex SHA as <ref>;
#   2. a trailing "# vX.Y.Z" comment;
#   3. a tag vX.Y.Z that exists and resolves (annotated tags included) to
#      exactly that SHA;
#   4. a SHA that is main's head or one of its ancestors.
# Prints one "path:line:col: error: message" per finding (the format
# annotate-gcc.sh parses), then a summary; exits 1 on any finding, and 2 when
# the API cannot answer. Remote facts come from the API, so no git history is
# needed.
set -euo pipefail

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${GH_TOKEN:?GH_TOKEN is required}"

cd "${1:-.}"

branch=main
errors=0
checked=0

declare -A tag_commit=()
declare -A reachable=()

# "owner/name" with the regex metacharacters ("." only, in valid names) escaped.
repo_pattern=${GITHUB_REPOSITORY//./\\.}
uses_pattern="^([[:space:]-]*)uses:[[:space:]]*[\"']?${repo_pattern}(/[^@[:space:]\"']*)?@([^[:space:]\"']+)[\"']?[[:space:]]*(#[[:space:]]*(.*))?\$"
sha_pattern='^[0-9a-f]{40}$'
comment_pattern='^(v[0-9]+\.[0-9]+\.[0-9]+)([[:space:]]|$)'

# Print "path:line:col: error: message" and count it.
report() {
    printf '%s:%s:%s: error: %s\n' "$1" "$2" "$3" "$4"
    errors=$((errors + 1))
}

# gh_api <endpoint> <jq>: print the result; "NOT_FOUND" on a 404. Any other
# failure stops the check, because it says nothing about the pin.
gh_api() {
    local out
    if ! out=$(gh api "$1" --jq "$2" 2>&1); then
        if [[ ${out} == *"HTTP 404"* ]]; then
            printf 'NOT_FOUND\n'
            return 0
        fi
        printf 'error: gh api %s failed: %s\n' "$1" "${out}" >&2
        exit 2
    fi
    printf '%s\n' "${out}"
}

# resolve_tag <tag>: set tag_commit[<tag>] to the commit the tag points at
# ("" when the tag does not exist), following annotated tags.
resolve_tag() {
    local tag=$1 object type sha
    [[ -v tag_commit[${tag}] ]] && return 0
    tag_commit[${tag}]=""
    object=$(gh_api "repos/${GITHUB_REPOSITORY}/git/ref/tags/${tag}" '.object.type + " " + .object.sha')
    [[ ${object} == NOT_FOUND ]] && return 0
    for _ in 1 2 3 4 5; do
        type=${object%% *}
        sha=${object##* }
        if [[ ${type} != tag ]]; then
            tag_commit[${tag}]=${sha}
            return 0
        fi
        object=$(gh_api "repos/${GITHUB_REPOSITORY}/git/tags/${sha}" '.object.type + " " + .object.sha')
        [[ ${object} == NOT_FOUND ]] && return 0
    done
    return 0
}

# resolve_reachable <sha>: set reachable[<sha>] to true when <sha> is the head
# of main or one of its ancestors. Comparing main...<sha> makes <sha> the
# head, so "behind" and "identical" mean it is contained in main.
resolve_reachable() {
    local sha=$1 status
    [[ -v reachable[${sha}] ]] && return 0
    status=$(gh_api "repos/${GITHUB_REPOSITORY}/compare/${branch}...${sha}" .status)
    case "${status}" in
        behind | identical) reachable[${sha}]=true ;;
        *) reachable[${sha}]=false ;;
    esac
}

# check_file <path>
check_file() {
    local file=$1 line number=0 indent col path ref comment tag
    local -a lines
    mapfile -t lines <"${file}"
    for line in "${lines[@]}"; do
        number=$((number + 1))
        [[ ${line} =~ ${uses_pattern} ]] || continue
        indent=${BASH_REMATCH[1]}
        path=${BASH_REMATCH[2]}
        ref=${BASH_REMATCH[3]}
        comment=${BASH_REMATCH[5]}
        col=$((${#indent} + 1))
        checked=$((checked + 1))

        if [[ ! ${ref} =~ ${sha_pattern} ]]; then
            report "${file}" "${number}" "${col}" "${GITHUB_REPOSITORY}${path} must be pinned to a full 40-character lowercase SHA, not '${ref}'"
            continue
        fi
        if [[ ! ${comment} =~ ${comment_pattern} ]]; then
            report "${file}" "${number}" "${col}" "${GITHUB_REPOSITORY}${path}@${ref} needs a trailing '# vX.Y.Z' comment naming its release tag"
            continue
        fi
        tag=${BASH_REMATCH[1]}

        resolve_tag "${tag}"
        if [[ -z ${tag_commit[${tag}]} ]]; then
            report "${file}" "${number}" "${col}" "tag ${tag} does not exist in ${GITHUB_REPOSITORY}"
        elif [[ ${tag_commit[${tag}]} != "${ref}" ]]; then
            report "${file}" "${number}" "${col}" "tag ${tag} points at ${tag_commit[${tag}]}, not at ${ref}"
        fi

        resolve_reachable "${ref}"
        if [[ ${reachable[${ref}]} != true ]]; then
            report "${file}" "${number}" "${col}" "${ref} is not on ${branch}; pin only tagged commits on ${branch}"
        fi
    done
}

shopt -s nullglob
files=(.github/workflows/*.y{a,}ml .github/actions/*/action.y{a,}ml)

for file in "${files[@]}"; do
    check_file "${file#./}"
done

if ((checked == 0)); then
    printf 'No %s self-pins found.\n' "${GITHUB_REPOSITORY}"
elif ((errors == 0)); then
    printf 'All %d %s self-pins are tagged commits on %s.\n' "${checked}" "${GITHUB_REPOSITORY}" "${branch}"
else
    printf '%d error(s) in %d %s self-pin(s).\n' "${errors}" "${checked}" "${GITHUB_REPOSITORY}"
    exit 1
fi
