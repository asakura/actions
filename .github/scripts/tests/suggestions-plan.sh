#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Test suggestions-plan.sh: which hunks it posts, which threads it retires,
# and the comment it writes.
set -euo pipefail

tests=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/check.sh
source "${tests}/lib/check.sh"
# shellcheck source=lib/gh-stub.sh
source "${tests}/lib/gh-stub.sh"

# Run suggestions-plan.sh on ${tmp}/lint; it writes ${tmp}/plan and
# ${tmp}/output.
plan() {
    rm -rf "${tmp}/plan"
    : >"${tmp}/output"
    LINT_DIR="${tmp}/lint" PLAN_DIR="${tmp}/plan" GITHUB_OUTPUT="${tmp}/output" \
        "${tests}/../suggestions-plan.sh" >/dev/null
}

# Write ${tmp}/threads.json from the threads given as a JSON array. Every
# thread states id, path, start_line, line, body, resolved, outdated,
# minimized, author and replied; a thread that lacks one fails the test.
threads() {
    jq '
        ["id", "path", "start_line", "line", "body", "resolved", "outdated",
         "minimized", "author", "replied"] as $required
        | {data: {repository: {pullRequest: {reviewThreads: {nodes: map(
            . as $thread
            | ($required - keys) as $missing
            | if ($missing | length) > 0
              then error("thread \($thread.id // "?") lacks: \($missing | join(", "))")
              else . end
            | {
                id,
                isResolved: .resolved,
                isOutdated: .outdated,
                path,
                startLine: .start_line,
                line,
                comments: {nodes: (
                    [{id: "N\(.id)", databaseId: 100, body,
                      isMinimized: .minimized,
                      author: {login: .author}}]
                    + if .replied then [{author: {login: "github-actions"}}] else [] end)}
            })}}}}}' >"${tmp}/threads.json"
}

# Print line $2 of the body of planned comment $1.
# shellcheck disable=SC2329 # called through check.
body_line() {
    jq -r ".comments[$1].body" "${tmp}/plan/review.json" | sed -n "$2p"
}

# Print "present" or "absent" for file $1.
# shellcheck disable=SC2329 # called through check.
exists() {
    if [[ -f $1 ]]; then echo present; else echo absent; fi
}

mkdir -p "${tmp}/lint"
cat >"${tmp}/lint/shfmt.txt" <<'DIFF'
--- a.sh.orig
+++ a.sh
@@ -1,3 +1,3 @@
-if true;then
-echo  hi
+if true; then
+    echo hi
 fi
DIFF
cat >"${tmp}/lint/mdformat.txt" <<'DIFF'
--- a/doc/x.md
+++ b/doc/x.md
@@ -2,2 +2,3 @@
 one
+
 ```two```
@@ -9 +10 @@
-* item
+- item
DIFF

# The pull request changes a.sh lines 1-3 and doc/x.md lines 1-5, so the
# mdformat hunk at line 9 lies outside it.
cat >"${tmp}/files.json" <<'JSON'
[{"filename": "a.sh", "patch": "@@ -0,0 +1,3 @@\n+if true;then\n+echo  hi\n+fi"},
 {"filename": "doc/x.md", "patch": "@@ -1,4 +1,5 @@\n x"},
 {"filename": "image.png"}]
JSON

md='<!-- lint-suggestion tool=mdformat -->'
sh='<!-- lint-suggestion tool=shfmt -->'
# What the plan posts for the doc/x.md hunk at lines 2-3.
md_body="${md}
mdformat would format these lines like this:

\`\`\`\`suggestion
one

\`\`\`two\`\`\`
\`\`\`\`"
# What it would post for the one-line doc/x.md hunk at line 9.
md_line_body="${md}
mdformat would format this line like this:

\`\`\`suggestion
- item
\`\`\`"
jq -n --arg md "${md}" --arg sh "${sh}" --arg md_body "${md_body}" --arg md_line_body "${md_line_body}" '[
    # Exactly the suggestion the plan would post: kept, not posted again.
    {id: "T1", path: "doc/x.md", start_line: 2, line: 3, body: $md_body, resolved: false, outdated: false, minimized: false, author: "github-actions", replied: false},
    # The same for a one-line suggestion, whose startLine GitHub reports as
    # the line itself: kept.
    {id: "T10", path: "doc/x.md", start_line: 9, line: 9, body: $md_line_body, resolved: false, outdated: false, minimized: false, author: "github-actions", replied: false},
    # Outdated: retired; T3 has a reply already.
    {id: "T2", path: "a.sh", start_line: null, line: null, body: $sh, resolved: false, outdated: true, minimized: false, author: "github-actions", replied: false},
    {id: "T3", path: "a.sh", start_line: null, line: null, body: $sh, resolved: false, outdated: true, minimized: false, author: "github-actions", replied: true},
    # Not ours, not a suggestion, minimized, resolved: left alone.
    {id: "T4", path: "a.sh", start_line: null, line: null, body: $sh, resolved: false, outdated: true, minimized: false, author: "someone", replied: false},
    {id: "T5", path: "a.sh", start_line: null, line: null, body: "a comment", resolved: false, outdated: true, minimized: false, author: "github-actions", replied: false},
    {id: "T6", path: "a.sh", start_line: null, line: null, body: $sh, resolved: false, outdated: true, minimized: true, author: "github-actions", replied: false},
    {id: "T7", path: "a.sh", start_line: null, line: null, body: $sh, resolved: true, outdated: true, minimized: false, author: "github-actions", replied: false},
    # Current, but shfmt suggests nothing on line 9 now: retired.
    {id: "T8", path: "a.sh", start_line: null, line: 9, body: $sh, resolved: false, outdated: false, minimized: false, author: "github-actions", replied: false},
    # Current, on the lines of the shfmt hunk, but with other text: retired,
    # and the hunk is posted again.
    {id: "T9", path: "a.sh", start_line: 1, line: 3, body: "\($sh)\nan older suggestion", resolved: false, outdated: false, minimized: false, author: "github-actions", replied: false}
]' | threads

plan
check "work to do" "work=true" cat "${tmp}/output"
check "only the shfmt hunk is posted" '{"path":"a.sh","line":3,"start_line":1}' \
    jq -c '.comments[] | {path, line, start_line}' "${tmp}/plan/review.json"
check "the review is on the head commit" "${HEAD_SHA}" \
    jq -r '.commit_id' "${tmp}/plan/review.json"
check "the suggestion body" "${sh}
shfmt would format these lines like this:

\`\`\`suggestion
if true; then
    echo hi
fi
\`\`\`" jq -r '.comments[0].body' "${tmp}/plan/review.json"
check "the threads that no longer apply are retired" "T2	100	NT2	false	Resolved: these lines changed by 1234567, so this suggestion no longer applies.
T3	100	NT3	true	Resolved: these lines changed by 1234567, so this suggestion no longer applies.
T8	100	NT8	false	Resolved: shfmt no longer suggests this change at 1234567.
T9	100	NT9	false	Resolved: shfmt no longer suggests this change at 1234567." \
    cat "${tmp}/plan/retire.tsv"

# shfmt printed an error instead of a diff: a missing hunk proves nothing.
echo 'a.sh:1:1: reached EOF without closing quote' >"${tmp}/lint/shfmt.txt"
plan
check "a formatter that errored retires none of its threads" "T2
T3" cut -f1 "${tmp}/plan/retire.tsv"

# Only mdformat ran, the pull request covers both its hunks, no threads.
rm "${tmp}/lint/shfmt.txt"
echo '[{"filename": "doc/x.md", "patch": "@@ -1,9 +1,9 @@"}]' >"${tmp}/files.json"
echo '[]' | threads
plan
check "the fence is longer than the backticks inside" '````suggestion' body_line 0 4
check "a one-line hunk says this line" "mdformat would format this line like this:" body_line 1 2
check "no thread to retire, no retire.tsv" absent exists "${tmp}/plan/retire.tsv"

# No diffs, no threads.
rm "${tmp}/lint/mdformat.txt"
plan
check "nothing to do" "work=false" cat "${tmp}/output"
check "nothing to do, no plan files" absent exists "${tmp}/plan/review.json"

# Only the pin comment check ran: its fix is posted like a formatter's, as a
# suggestion on the line, and kept while the check still suggests it.
cat >"${tmp}/lint/pin-comments.diff" <<'DIFF'
--- .github/workflows/x.yml
+++ .github/workflows/x.yml
@@ -3 +3 @@
-      - uses: a/b@0123456789012345678901234567890123456789 # v1
+      - uses: a/b@0123456789012345678901234567890123456789 # v1.2.3
DIFF
printf '%s\n' '[{"filename": ".github/workflows/x.yml", "patch": "@@ -0,0 +1,4 @@\n+x"}]' >"${tmp}/files.json"
echo '[]' | threads
plan
check "the pin comment fix is posted on its line" '{"path":".github/workflows/x.yml","line":3,"start_line":null}' \
    jq -c '.comments[] | {path, line, start_line}' "${tmp}/plan/review.json"
check "the pin comment suggestion body" '<!-- lint-suggestion tool=pins -->
pins would format this line like this:

```suggestion
      - uses: a/b@0123456789012345678901234567890123456789 # v1.2.3
```' jq -r '.comments[0].body' "${tmp}/plan/review.json"
jq -n '[{id: "T1", path: ".github/workflows/x.yml", start_line: null, line: 3, body: "<!-- lint-suggestion tool=pins -->\nan older suggestion", resolved: false, outdated: false, minimized: false, author: "github-actions", replied: false}]' | threads
plan
check "an older pin comment suggestion is retired" "T1	100	NT1	false	Resolved: pins no longer suggests this change at 1234567." \
    cat "${tmp}/plan/retire.tsv"
: >"${tmp}/lint/pin-comments.diff"
plan
check "a clean pin comment check retires its thread" "T1" cut -f1 "${tmp}/plan/retire.tsv"

exit "${failed}"
