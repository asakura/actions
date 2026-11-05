#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Test check-pin-comments.sh: the findings, and the diff of suggested fixes it
# writes, for pins without a version comment or with a wrong one.
set -euo pipefail

tests=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/check.sh
source "${tests}/lib/check.sh"
# shellcheck source=lib/git-stub.sh
source "${tests}/lib/git-stub.sh"

# Run check-pin-comments.sh in the checkout ${tmp}/repo.
# shellcheck disable=SC2329 # called through check.
pins() {
    (cd "${tmp}/repo" && PINS_DIFF="${tmp}/pins.diff" "${tests}/../check-pin-comments.sh")
}

# A 40-digit commit made of one digit: sha 1 prints 1111111111111111111111111111111111111111.
sha() {
    printf '%0.s'"$1" {1..40}
}
one=$(sha 1)
two=$(sha 2)
three=$(sha 3)

# a/b: v1.2.3 and its moving alias v1 point at commit 1. v1.2.4 is an
# annotated tag: its own line shows the tag object (3), the peeled line the
# commit it points at (2). c/d has no vX.Y.Z tag, only "stable" at commit 3.
mkdir -p "${tmp}/ls-remote/a" "${tmp}/ls-remote/c"
printf '%s\trefs/tags/v1\n%s\trefs/tags/v1.2.3\n%s\trefs/tags/v1.2.4\n%s\trefs/tags/v1.2.4^{}\n' \
    "${one}" "${one}" "${three}" "${two}" >"${tmp}/ls-remote/a/b"
printf '%s\trefs/tags/stable\n' "${three}" >"${tmp}/ls-remote/c/d"

mkdir -p "${tmp}/repo/.github/workflows"
cat >"${tmp}/repo/.github/workflows/x.yml" <<YAML
steps:
  - uses: a/b@${one}
  - uses: a/b@${one} # v1
  - uses: a/b@${two} # v1.2.4
  - uses: c/d@${three} # stable
  - run: true
YAML

check "a pin without a version comment, with a wrong one, with no tag upstream" \
    ".github/workflows/x.yml:2:55: error: a/b@1111111 has no version comment; v1.2.3 points at this commit, so the fix is to add \"# v1.2.3\". [pin-comment]
  - uses: a/b@${one}

.github/workflows/x.yml:3:55: error: a/b@1111111 has the comment \"# v1\", but it must be the exact tag; v1.2.3 points at this commit, so the fix is to change it to \"# v1.2.3\". [pin-comment]
  - uses: a/b@${one} # v1

.github/workflows/x.yml:5:55: error: c/d@3333333 has the comment \"# stable\", but it must be the exact tag, and no vX.Y.Z tag of c/d points at this commit; every pin needs exactly \"# vX.Y.Z\". [pin-comment]
  - uses: c/d@${three} # stable
[exit status 1]" \
    pins

# The fixes: the new comment on the line, the reason after the hunk header; no
# fix for the line without a tag.
check "the suggested fixes, with the reason for each" \
    "--- .github/workflows/x.yml
+++ .github/workflows/x.yml
@@ -2 +2 @@ a/b@1111111 has no version comment; v1.2.3 points at this commit, so the fix is to add \"# v1.2.3\".
-  - uses: a/b@${one}
+  - uses: a/b@${one} # v1.2.3
--- .github/workflows/x.yml
+++ .github/workflows/x.yml
@@ -3 +3 @@ a/b@1111111 has the comment \"# v1\", but it must be the exact tag; v1.2.3 points at this commit, so the fix is to change it to \"# v1.2.3\".
-  - uses: a/b@${one} # v1
+  - uses: a/b@${one} # v1.2.3" \
    cat "${tmp}/pins.diff"

exit "${failed}"
