#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Test check-pin-comments.sh: the findings, and the diff of suggested fixes it
# writes, for pins without a version comment or with a wrong one, and for the
# pin-comment marker lines that are inline, stray or useless.
set -euo pipefail

tests=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/check.sh
source "${tests}/lib/check.sh"
# shellcheck source=lib/git-stub.sh
source "${tests}/lib/git-stub.sh"

# Run check-pin-comments.sh in the checkout ${tmp}/repo with WRITE_PINS_DIFF=$1.
# shellcheck disable=SC2329 # called through check.
pins() {
    (cd "${tmp}/repo" && WRITE_PINS_DIFF=$1 PINS_DIFF="${tmp}/pins.diff" "${tests}/../check-pin-comments.sh")
}

# Print "present" or "absent" for file $1.
# shellcheck disable=SC2329 # called through check.
exists() {
    if [[ -f $1 ]]; then echo present; else echo absent; fi
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
# e/f has v1.0.0 at commit 2 and v2.0.0 at commit 3.
mkdir -p "${tmp}/ls-remote/a" "${tmp}/ls-remote/c" "${tmp}/ls-remote/e"
printf '%s\trefs/tags/v1\n%s\trefs/tags/v1.2.3\n%s\trefs/tags/v1.2.4\n%s\trefs/tags/v1.2.4^{}\n' \
    "${one}" "${one}" "${three}" "${two}" >"${tmp}/ls-remote/a/b"
printf '%s\trefs/tags/stable\n' "${three}" >"${tmp}/ls-remote/c/d"
printf '%s\trefs/tags/v1.0.0\n%s\trefs/tags/v2.0.0\n' "${two}" "${three}" >"${tmp}/ls-remote/e/f"

# The exceptions are accepted while no vX.Y.Z tag points at their commit: c/d at
# 3 with the marker above "- uses:" (line 7) and above "uses:" under "- name:"
# (line 10), e/f at 1 (line 12); e/f at 2 (line 14) is not. Lines 5 and 24 have
# no marker; line 15 has it inline; the markers above lines 17 and 19 do not
# apply to those comments; the markers at lines 21, 23 and 25 are stray.
mark='# pin-comment: no vX.Y.Z tag upstream'
mkdir -p "${tmp}/repo/.github/workflows"
cat >"${tmp}/repo/.github/workflows/x.yml" <<YAML
steps:
  - uses: a/b@${one}
  - uses: a/b@${one} # v1
  - uses: a/b@${two} # v1.2.4
  - uses: c/d@${three} # stable
  ${mark}
  - uses: c/d@${three} # stable
  - name: named
    ${mark}
    uses: c/d@${three} # stable
  ${mark}
  - uses: e/f@${one} # main
  ${mark}
  - uses: e/f@${two} # main
  - uses: c/d@${three} # stable ${mark}
  ${mark}
  - uses: a/b@${one} # v1.2.3
  ${mark}
  - uses: c/d@${three} # stable v2
  - run: true
  ${mark}
  - run: true
    ${mark}
  - uses: c/d@${three} # stable
  # pin-comment: no tag
  - run: true
YAML

check "a pin without a version comment, with a wrong one, with no tag upstream, with an unnecessary exception, with the old inline form, and markers that are useless, stray, misplaced or misindented" \
    ".github/workflows/x.yml:2:55: error: a/b@1111111 has no version comment; v1.2.3 points at this commit, so the fix is to add \"# v1.2.3\". [pin-comment]
  - uses: a/b@${one}

.github/workflows/x.yml:3:55: error: a/b@1111111 has the comment \"# v1\", but it must be the exact tag; v1.2.3 points at this commit, so the fix is to change it to \"# v1.2.3\". [pin-comment]
  - uses: a/b@${one} # v1

.github/workflows/x.yml:5:55: error: c/d@3333333 has the comment \"# stable\", but it must be the exact tag, and no vX.Y.Z tag of c/d points at this commit; every pin needs exactly \"# vX.Y.Z\", or, when upstream publishes no vX.Y.Z tag, the line \"# pin-comment: no vX.Y.Z tag upstream\" directly above the \"uses:\" line and \"# <ref>\" at the end of it. [pin-comment]
  - uses: c/d@${three} # stable

.github/workflows/x.yml:14:55: error: e/f@2222222 claims \"no vX.Y.Z tag upstream\", but the exception is unnecessary; v1.0.0 points at this commit, so the fix is to remove the marker line above and change the comment to \"# v1.0.0\". [pin-comment]
  - uses: e/f@${two} # main

.github/workflows/x.yml:15:55: error: c/d@3333333 has the pin-comment marker on the \"uses:\" line, but zizmor reads everything after the first \"#\" there as the version; move the marker to its own line directly above, indented like the \"uses:\" line, so that the \"uses:\" line ends with \"# <ref>\" only (here \"# pin-comment: no vX.Y.Z tag upstream\" above, and \"# stable\" at the end of the line). [pin-comment]
  - uses: c/d@${three} # stable # pin-comment: no vX.Y.Z tag upstream

.github/workflows/x.yml:17:55: error: a/b@1111111 has the pin-comment marker above, which only applies to a line that ends with \"# <ref>\" (one word, no vX.Y.Z), but its comment is \"# v1.2.3\"; remove the marker, or end the line with the upstream tag or branch as \"# <ref>\". [pin-comment]
  - uses: a/b@${one} # v1.2.3

.github/workflows/x.yml:19:55: error: c/d@3333333 has the pin-comment marker above, which only applies to a line that ends with \"# <ref>\" (one word, no vX.Y.Z), but its comment is \"# stable v2\"; remove the marker, or end the line with the upstream tag or branch as \"# <ref>\". [pin-comment]
  - uses: c/d@${three} # stable v2

.github/workflows/x.yml:21:3: error: the pin-comment marker is not directly above a SHA-pinned \"uses:\" line; put it on the line right before the \"uses:\" line it applies to, with no line between, or remove it. [pin-comment]
  # pin-comment: no vX.Y.Z tag upstream

.github/workflows/x.yml:23:5: error: the pin-comment marker is indented 4 spaces, but the \"uses:\" line below is indented 2 spaces; indent the marker with exactly 2 spaces, aligned with the first non-space character of the \"uses:\" line (the \"-\" of \"- uses:\", or \"uses\" under \"- name:\"). [pin-comment]
    # pin-comment: no vX.Y.Z tag upstream

.github/workflows/x.yml:24:55: error: c/d@3333333 has the comment \"# stable\", but it must be the exact tag, and no vX.Y.Z tag of c/d points at this commit; every pin needs exactly \"# vX.Y.Z\", or, when upstream publishes no vX.Y.Z tag, the line \"# pin-comment: no vX.Y.Z tag upstream\" directly above the \"uses:\" line and \"# <ref>\" at the end of it. [pin-comment]
  - uses: c/d@${three} # stable

.github/workflows/x.yml:25:3: error: this line starts with \"# pin-comment:\" but is not the marker; the marker line holds only the indentation of the \"uses:\" line below and exactly \"# pin-comment: no vX.Y.Z tag upstream\". [pin-comment]
  # pin-comment: no tag
[exit status 1]" \
    pins true

# The fixes: the new comment on the line, the reason after the hunk header; the
# unnecessary exception also loses its marker line, and the inline form gets a
# marker line. No fix for the lines without a tag, or with a marker that does
# not apply.
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
+  - uses: a/b@${one} # v1.2.3
--- .github/workflows/x.yml
+++ .github/workflows/x.yml
@@ -13,2 +13 @@ e/f@2222222 claims \"no vX.Y.Z tag upstream\", but the exception is unnecessary; v1.0.0 points at this commit, so the fix is to remove the marker line above and change the comment to \"# v1.0.0\".
-  # pin-comment: no vX.Y.Z tag upstream
-  - uses: e/f@${two} # main
+  - uses: e/f@${two} # v1.0.0
--- .github/workflows/x.yml
+++ .github/workflows/x.yml
@@ -15 +15,2 @@ c/d@3333333 has the pin-comment marker on the \"uses:\" line, but zizmor reads everything after the first \"#\" there as the version; move the marker to its own line directly above, indented like the \"uses:\" line, so that the \"uses:\" line ends with \"# <ref>\" only (here \"# pin-comment: no vX.Y.Z tag upstream\" above, and \"# stable\" at the end of the line).
-  - uses: c/d@${three} # stable # pin-comment: no vX.Y.Z tag upstream
+  # pin-comment: no vX.Y.Z tag upstream
+  - uses: c/d@${three} # stable" \
    cat "${tmp}/pins.diff"
# Where nothing reads the diff, it is not written; the findings are the same.
rm "${tmp}/pins.diff"
# shellcheck disable=SC2310 # the run fails on purpose; its findings are read next.
pins false >"${tmp}/findings" 2>&1 || true
check "WRITE_PINS_DIFF=false writes no diff" absent exists "${tmp}/pins.diff"
check "and prints the same findings" 11 grep -c ' error: ' "${tmp}/findings"
check "WRITE_PINS_DIFF must be true or false" \
    'check-pin-comments.sh: WRITE_PINS_DIFF must be true or false, not "yes"
[exit status 2]' \
    pins yes

# Print the error of a run without WRITE_PINS_DIFF, without the script's path.
# shellcheck disable=SC2329 # called through check.
missing() {
    env -u WRITE_PINS_DIFF PINS_DIFF="${tmp}/pins.diff" "${tests}/../check-pin-comments.sh" 2>&1 |
        sed 's/^.*: line [0-9]*: //' || true
}
check "WRITE_PINS_DIFF is required" "WRITE_PINS_DIFF: WRITE_PINS_DIFF is required" missing

exit "${failed}"
