#!/usr/bin/env bash
# Fail when a pull request changes the commit of a pin but not its version or
# ref.
#
# Usage: check-pin-changes.sh | annotate-gcc.sh
# Run from the repository root, checked out at the pull request head.
# Env:
#   GITHUB_REPOSITORY  owner/name.
#   PR_NUMBER          pull request number.
#   BASE_SHA           base branch commit of the pull request event.
#   HEAD_SHA           head commit of the pull request.
#   GH_TOKEN           token with contents: read and pull-requests: read.
# A pin is "uses: ...@<sha> # vX.Y.Z", or an exception with the comment
# "# <ref> # pin-comment: no vX.Y.Z tag upstream"; its "ref" is the version or
# the <ref> (see pin-lines.sh).
# Reads the pins of every workflow and action file at the commit where the
# pull request branched off, not only of the files it changes, and checks
# every pin of every workflow and action file the pull request changes, adds
# or renames against them: a pin of the same action with the same ref but
# another commit is an error, wherever the old pin was. A release always has a
# new version, so this is a re-pointed tag or rewritten history; an exception
# pin follows its <ref> the same way. A pull request that pins one action and
# ref to two commits in its own files is an error too. The merge base is where
# the pull request branched off (BASE_SHA may be newer); its file list comes
# from the git trees API and its files from the contents API, which need no
# more than contents: read. Prints gcc-style findings; exits 1 when there are
# any.
set -euo pipefail

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${BASE_SHA:?BASE_SHA is required}"
: "${HEAD_SHA:?HEAD_SHA is required}"

scripts=$(dirname "$0")
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
# The files that can hold pins, as a path regular expression.
path_re='^\.github/(workflows/[^/]+|actions/[^/]+/action)\.ya?ml$'

merge_base=$(gh api "repos/${GITHUB_REPOSITORY}/compare/${BASE_SHA}...${HEAD_SHA}" |
    jq -r '.merge_base_commit.sha')

# Every pin at the merge base, one JSON object per line with its file.
tree=$(gh api "repos/${GITHUB_REPOSITORY}/git/trees/${merge_base}?recursive=1")
truncated=$(jq -r '.truncated' <<<"${tree}")
if [[ ${truncated} != false ]]; then
    echo "check-pin-changes.sh: the file tree at ${merge_base} is too large for the API, so not every workflow and action file can be listed" >&2
    exit 1
fi
base_files=$(jq -r --arg re "${path_re}" '.tree[] | select(.type == "blob" and (.path | test($re))) | .path' <<<"${tree}")
: >"${work}/base.jsonl"
if [[ -n ${base_files} ]]; then
    while IFS= read -r path; do
        gh api -H 'Accept: application/vnd.github.raw+json' \
            "repos/${GITHUB_REPOSITORY}/contents/${path}?ref=${merge_base}" |
            "${scripts}/pin-lines.sh" |
            jq -c --arg path "${path}" 'select(.ref != null) | {path: $path, line, action, ref, exception, sha}' \
                >>"${work}/base.jsonl"
    done <<<"${base_files}"
fi

# Every pin in the files the pull request changes or adds (a renamed file is
# listed under its new name), read from the checkout.
pr_files=$(gh api --paginate "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/files" |
    jq -r --arg re "${path_re}" '.[] | select(.status != "removed" and (.filename | test($re))) | .filename')
: >"${work}/head.jsonl"
if [[ -n ${pr_files} ]]; then
    while IFS= read -r path; do
        # shellcheck disable=SC2094 # jq only gets the name, as a string; nothing is written.
        "${scripts}/pin-lines.sh" <"${path}" |
            jq -c --arg path "${path}" 'select(.ref != null) | . + {path: $path}' \
                >>"${work}/head.jsonl"
    done <<<"${pr_files}"
fi

# Print "abc1234 (file:line, file:line) and ..." for the pins in $1, grouped
# by commit.
# shellcheck disable=SC2016 # $pins is a jq variable.
describe='def describe($pins): $pins | group_by(.sha)
    | map("\(.[0].sha[0:7]) (\(map("\(.path):\(.line)") | join(", ")))") | join(" and ");'

findings=$(jq -rs --slurpfile base "${work}/base.jsonl" "${describe}"'
    def named($pin): if $pin.exception then "ref \($pin.ref)" else $pin.ref end;
    . as $head
    | def same($pin): select(.action == $pin.action and .ref == $pin.ref);
    # Pins whose version or ref was another commit at the merge base.
    [$head[] as $pin
        | [$base[] | same($pin)] as $old
        | select(($old | length) > 0 and ($old | any(.sha == $pin.sha) | not))
        | $pin + {message: "\($pin.action)@\($pin.sha[0:7]) is pinned as \(named($pin)), but at the merge base \(named($pin)) was \(describe($old)): the same version or ref must be the same commit, so a tag was re-pointed or history was rewritten"}] as $moved
    # Pins that disagree with another pin of this pull request; a pin already
    # reported above is the cause, so it is neither reported nor compared again.
    | [$head[] | select(. as $pin | $moved | any(.path == $pin.path and .line == $pin.line) | not)] as $rest
    | [$rest[] as $pin
        | [$rest[] | same($pin) | select(.sha != $pin.sha)] as $other
        | select(($other | length) > 0)
        | $pin + {message: "\($pin.action)@\($pin.sha[0:7]) is pinned as \(named($pin)), but this pull request also pins \(named($pin)) to \(describe($other)): the same version or ref must be the same commit"}] as $clash
    | ($moved + $clash) | sort_by([.path, .line])[]
    | "\(.path):\(.line):\(.prefix | length): error: \(.message) [pin-changed]\n\(.text)\n"' \
    "${work}/head.jsonl")

if [[ -n ${findings} ]]; then
    printf '%s\n' "${findings}"
    exit 1
fi
