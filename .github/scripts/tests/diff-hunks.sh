#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Test diff-hunks.sh on an shfmt diff, an mdformat diff and a diff whose hunk
# header carries a note.
set -euo pipefail

tests=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/check.sh
source "${tests}/lib/check.sh"

# shellcheck disable=SC2329 # called through check.
hunks() {
    "${tests}/../diff-hunks.sh" "$@"
}

# shfmt labels the files without a prefix.
cat >"${tmp}/shfmt.txt" <<'DIFF'
diff a.sh.orig a.sh
--- a.sh.orig
+++ a.sh
@@ -1,3 +1,3 @@
-if true;then
-echo  hi
+if true; then
+    echo hi
 fi
DIFF
check "one hunk; context lines are part of it" \
    '{"tool":"shfmt","path":"a.sh","start":1,"end":3,"lines":["if true; then","    echo hi","fi"],"note":""}' \
    hunks shfmt "" <"${tmp}/shfmt.txt"

# mdformat-diff.sh labels them a/ and b/. Two hunks; the second has a
# one-line header and ends without a newline at end of file.
cat >"${tmp}/mdformat.txt" <<'DIFF'
--- a/doc/x.md
+++ b/doc/x.md
@@ -2,2 +2,3 @@
 one
+
 ```two```
@@ -9 +10 @@
-* item
\ No newline at end of file
+- item
DIFF
# shellcheck disable=SC2016 # the backticks are Markdown, not a command.
check "two hunks; the b/ prefix is stripped" \
    '{"tool":"mdformat","path":"doc/x.md","start":2,"end":3,"lines":["one","","```two```"],"note":""}
{"tool":"mdformat","path":"doc/x.md","start":9,"end":9,"lines":["- item"],"note":""}' \
    hunks mdformat b/ <"${tmp}/mdformat.txt"

# check-pin-comments.sh puts the reason for a change after the hunk header.
cat >"${tmp}/pins.diff" <<'DIFF'
--- .github/workflows/x.yml
+++ .github/workflows/x.yml
@@ -3 +3 @@ a/b@0123456 has no version comment; v1.2.3 points at this commit
-      - uses: a/b@0123456789012345678901234567890123456789
+      - uses: a/b@0123456789012345678901234567890123456789 # v1.2.3
DIFF
check "the text after the header is the note" \
    '{"tool":"pins","path":".github/workflows/x.yml","start":3,"end":3,"lines":["      - uses: a/b@0123456789012345678901234567890123456789 # v1.2.3"],"note":"a/b@0123456 has no version comment; v1.2.3 points at this commit"}' \
    hunks pins "" <"${tmp}/pins.diff"

exit "${failed}"
