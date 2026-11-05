#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Test check-pin-changes.sh: a pin with the same action and version but another
# commit than at the merge base is an error in a changed, new or renamed file,
# wherever the old pin was; so are two commits for one version in one pull
# request.
set -euo pipefail

tests=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/check.sh
source "${tests}/lib/check.sh"
# shellcheck source=lib/gh-stub.sh
source "${tests}/lib/gh-stub.sh"

# Run check-pin-changes.sh in the checkout ${tmp}/repo.
# shellcheck disable=SC2329 # called through check.
changes() {
    (cd "${tmp}/repo" && BASE_SHA=base "${tests}/../check-pin-changes.sh")
}

# A 40-digit commit made of one digit: sha 1 prints 1111111111111111111111111111111111111111.
sha() {
    printf '%0.s'"$1" {1..40}
}
one=$(sha 1)
two=$(sha 2)
three=$(sha 3)
four=$(sha 4)

echo '{"merge_base_commit": {"sha": "mergebase"}}' >"${tmp}/compare.json"

# The merge base: checkout v7.0.1 at commit 1 in a.yml (line 4) and in the
# composite action (line 2); other v2.0.0 at commit 3 in a.yml. b.yml has a
# comment that is no version, and README.md is no workflow.
mkdir -p "${tmp}/base/.github/workflows" "${tmp}/base/.github/actions/x"
cat >"${tmp}/base/.github/workflows/a.yml" <<YAML
steps:
  - run: true
  - name: checkout
    uses: actions/checkout@${one} # v7.0.1
  - uses: other/act@${three} # v2.0.0
YAML
cat >"${tmp}/base/.github/actions/x/action.yml" <<YAML
steps:
  - uses: actions/checkout@${one} # v7.0.1
YAML
cat >"${tmp}/base/.github/workflows/b.yml" <<YAML
steps:
  - uses: actions/checkout@${two} # v7
YAML
cat >"${tmp}/trees.json" <<'JSON'
{"truncated": false, "tree": [
  {"path": ".github", "type": "tree"},
  {"path": ".github/actions/x/action.yml", "type": "blob"},
  {"path": ".github/workflows/a.yml", "type": "blob"},
  {"path": ".github/workflows/b.yml", "type": "blob"},
  {"path": ".github/workflows/notes.txt", "type": "blob"},
  {"path": "README.md", "type": "blob"}]}
JSON

# The head: a.yml is untouched in content; new.yml is added and re-points
# checkout v7.0.1 to commit 2; renamed.yml was a.yml and keeps its pins; the
# two added files c.yml and d.yml pin other/new v1.0.0 to commits 3 and 4;
# gone.yml is removed.
mkdir -p "${tmp}/repo/.github/workflows"
cp "${tmp}/base/.github/workflows/a.yml" "${tmp}/repo/.github/workflows/renamed.yml"
cat >"${tmp}/repo/.github/workflows/new.yml" <<YAML
steps:
  - uses: "actions/checkout@${two}" # v7.0.1
  - uses: other/act@${three} # v2.0.0
  - uses: actions/checkout@${two} # v7
YAML
printf 'steps:\n  - uses: other/new@%s # v1.0.0\n' "${three}" >"${tmp}/repo/.github/workflows/c.yml"
printf 'steps:\n  - uses: other/new@%s # v1.0.0\n' "${four}" >"${tmp}/repo/.github/workflows/d.yml"

cat >"${tmp}/files.json" <<'JSON'
[{"filename": ".github/workflows/renamed.yml", "previous_filename": ".github/workflows/a.yml", "status": "renamed"},
 {"filename": ".github/workflows/new.yml", "status": "added"},
 {"filename": ".github/workflows/gone.yml", "status": "removed"},
 {"filename": "README.md", "status": "modified"}]
JSON
check "a renamed file with the same pins, a new file with a pin of another commit" \
    ".github/workflows/new.yml:2:69: error: actions/checkout@2222222 is pinned as v7.0.1, but at the merge base v7.0.1 was 1111111 (.github/actions/x/action.yml:2, .github/workflows/a.yml:4): the same version must be the same commit, so a tag was re-pointed or history was rewritten [pin-changed]
  - uses: \"actions/checkout@${two}\" # v7.0.1
[exit status 1]" \
    changes

cat >"${tmp}/files.json" <<'JSON'
[{"filename": ".github/workflows/c.yml", "status": "added"},
 {"filename": ".github/workflows/d.yml", "status": "added"}]
JSON
check "two commits for one version in the pull request's own files" \
    ".github/workflows/c.yml:2:60: error: other/new@3333333 is pinned as v1.0.0, but this pull request also pins v1.0.0 to 4444444 (.github/workflows/d.yml:2): the same version must be the same commit [pin-changed]
  - uses: other/new@${three} # v1.0.0

.github/workflows/d.yml:2:60: error: other/new@4444444 is pinned as v1.0.0, but this pull request also pins v1.0.0 to 3333333 (.github/workflows/c.yml:2): the same version must be the same commit [pin-changed]
  - uses: other/new@${four} # v1.0.0
[exit status 1]" \
    changes

cat >"${tmp}/files.json" <<'JSON'
[{"filename": ".github/workflows/renamed.yml", "previous_filename": ".github/workflows/a.yml", "status": "renamed"},
 {"filename": ".github/workflows/c.yml", "status": "added"}]
JSON
check "pins that agree with the merge base and with each other" "" changes

echo '{"truncated": true, "tree": []}' >"${tmp}/trees.json"
check "a truncated tree is an error" \
    "check-pin-changes.sh: the file tree at mergebase is too large for the API, so not every workflow and action file can be listed
[exit status 1]" \
    changes

exit "${failed}"
