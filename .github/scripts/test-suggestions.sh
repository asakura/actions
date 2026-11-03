#!/usr/bin/env bash
# Test diff-hunks.sh, suggestions-plan.sh and suggestions-apply.sh offline,
# with a stub gh that serves fixtures and logs every call.
#
# Usage: test-suggestions.sh
# Needs bash and jq. Prints one line per check and exits 1 if any failed.
set -euo pipefail

scripts=$(cd "$(dirname "$0")" && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT
failed=0

# Check $1: the output of the command $3... must equal $2.
check() {
    local name=$1 expected=$2 actual
    shift 2
    actual=$("$@")
    if [[ ${actual} == "${expected}" ]]; then
        echo "ok: ${name}"
    else
        echo "FAIL: ${name}"$'\n'"  expected: ${expected}"$'\n'"  actual:   ${actual}"
        failed=1
    fi
}

# Print the hunks of tool $1, path prefix $2, from diff file $3.
# shellcheck disable=SC2329 # called through check.
hunks() {
    "${scripts}/diff-hunks.sh" "$1" "$2" <"$3"
}

# Run suggestions-plan.sh on ${tmp}/lint, writing ${tmp}/plan and ${tmp}/output.
plan() {
    : >"${tmp}/output"
    LINT_DIR="${tmp}/lint" PLAN_DIR="${tmp}/plan" GITHUB_OUTPUT="${tmp}/output" \
        "${scripts}/suggestions-plan.sh" >/dev/null
}

# Print line $2 of the body of comment $1 in the planned review.
# shellcheck disable=SC2329 # called through check.
body_line() {
    jq -r ".comments[$1].body" "${tmp}/plan/review.json" | sed -n "$2p"
}

# Print "present" or "absent" for file $1.
# shellcheck disable=SC2329 # called through check.
exists() {
    if [[ -f $1 ]]; then echo present; else echo absent; fi
}

# Run suggestions-apply.sh on ${tmp}/apply with the pull request head at $1,
# then print the gh calls, each shortened to what the checks compare.
# shellcheck disable=SC2329 # called through check.
apply() {
    : >"${tmp}/gh.log"
    STUB_HEAD=$1 PLAN_DIR="${tmp}/apply" "${scripts}/suggestions-apply.sh" >/dev/null
    sed -E \
        -e 's|^api --method POST --silent repos/o/r/pulls/7/comments/([0-9]+)/replies -f body=(.*)|reply \1 \2|' \
        -e 's|^api graphql --silent -f query=mutation.* -F id=(.*)|minimize \1|' \
        -e 's|^api --method POST --silent repos/o/r/pulls/7/reviews .*|review|' \
        "${tmp}/gh.log"
}

# Print one review thread as GraphQL returns it. Arguments: id, outdated,
# path, line, author, body, minimized, resolved, and optionally the author of
# a reply.
thread() {
    # shellcheck disable=SC2016 # $id and the rest are jq variables.
    jq -nc --arg id "$1" --argjson outdated "$2" --arg path "$3" --argjson line "$4" \
        --arg author "$5" --arg body "$6" --argjson minimized "$7" --argjson resolved "$8" \
        --arg reply "${9:-}" '
        {id: $id, isResolved: $resolved, isOutdated: $outdated, path: $path, line: $line,
         comments: {nodes: ([{id: "N\($id)", databaseId: 100, body: $body,
                              isMinimized: $minimized, author: {login: $author}}]
                            + if $reply == "" then [] else [{author: {login: $reply}}] end)}}'
}

# A stub gh: answers from the fixture files and logs its arguments to gh.log.
mkdir -p "${tmp}/bin"
cat >"${tmp}/bin/gh" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"${STUB_DIR}/gh.log"
case "$*" in
    *'query($owner'*) cat "${STUB_DIR}/threads.json" ;;
    *'/files'*) cat "${STUB_DIR}/files.json" ;;
    'api repos/o/r/pulls/7') echo "{\"head\": {\"sha\": \"${STUB_HEAD}\"}}" ;;
    *) ;;
esac
EOF
chmod +x "${tmp}/bin/gh"
export PATH="${tmp}/bin:${PATH}" STUB_DIR="${tmp}"
export GITHUB_REPOSITORY=o/r PR_NUMBER=7 HEAD_SHA=1234567890abcdef

# --- diff-hunks.sh ---

cat >"${tmp}/shfmt.txt" <<'EOF'
diff a.sh.orig a.sh
--- a.sh.orig
+++ a.sh
@@ -1,3 +1,3 @@
-if true;then
-echo  hi
+if true; then
+    echo hi
 fi
EOF
check "shfmt hunk" \
    '{"tool":"shfmt","path":"a.sh","start":1,"end":3,"lines":["if true; then","    echo hi","fi"]}' \
    hunks shfmt "" "${tmp}/shfmt.txt"

# Two hunks in one file; the second ends without a newline at end of file.
cat >"${tmp}/mdformat.txt" <<'EOF'
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
EOF
# shellcheck disable=SC2016 # the backticks are Markdown, not a command.
check "mdformat hunks" \
    '{"tool":"mdformat","path":"doc/x.md","start":2,"end":3,"lines":["one","","```two```"]}
{"tool":"mdformat","path":"doc/x.md","start":9,"end":9,"lines":["- item"]}' \
    hunks mdformat b/ "${tmp}/mdformat.txt"

# --- suggestions-plan.sh ---

# The pull request diff covers a.sh lines 1-3 and doc/x.md lines 1-5, so the
# second mdformat hunk (line 9) lies outside it.
cat >"${tmp}/files.json" <<'EOF'
[{"filename": "a.sh", "patch": "@@ -0,0 +1,3 @@\n+if true;then\n+echo  hi\n+fi"},
 {"filename": "doc/x.md", "patch": "@@ -1,4 +1,5 @@\n x"},
 {"filename": "image.png"}]
EOF
# T1 is an open suggestion on doc/x.md line 3, so that hunk is not posted
# again. T2 is outdated and must be retired; T3 too, but it has a reply
# already. T8 is current, but shfmt has no hunk ending on its line any more.
# T4 to T7 are not ours, not a suggestion, minimized or resolved.
md='<!-- lint-suggestion tool=mdformat -->'
sh='<!-- lint-suggestion tool=shfmt -->'
{
    thread T1 false doc/x.md 3 github-actions "${md}" false false
    thread T2 true a.sh null github-actions "${sh}" false false
    thread T3 true a.sh null github-actions "${sh}" false false github-actions
    thread T4 true a.sh null someone "${sh}" false false
    thread T5 true a.sh null github-actions "a person's comment" false false
    thread T6 true a.sh null github-actions "${sh}" true false
    thread T7 true a.sh null github-actions "${sh}" false true
    thread T8 false a.sh 9 github-actions "${sh}" false false
} | jq -s '{data: {repository: {pullRequest: {reviewThreads: {nodes: .}}}}}' >"${tmp}/threads.json"

mkdir -p "${tmp}/lint"
cp "${tmp}/shfmt.txt" "${tmp}/mdformat.txt" "${tmp}/lint/"
plan
check "plan: work" "work=true" cat "${tmp}/output"
check "plan: only the shfmt hunk is posted" '{"path":"a.sh","line":3,"start_line":1}' \
    jq -c '.comments[] | {path, line, start_line}' "${tmp}/plan/review.json"
check "plan: the review is on the head commit" "${HEAD_SHA}" \
    jq -r '.commit_id' "${tmp}/plan/review.json"
check "plan: suggestion body" "${sh}
shfmt would format these lines like this:

\`\`\`suggestion
if true; then
    echo hi
fi
\`\`\`" jq -r '.comments[0].body' "${tmp}/plan/review.json"
check "plan: retire our threads that no longer apply" "T2	100	NT2	false	Resolved: these lines changed by 1234567, so this suggestion no longer applies.
T3	100	NT3	true	Resolved: these lines changed by 1234567, so this suggestion no longer applies.
T8	100	NT8	false	Resolved: shfmt no longer suggests a change to these lines at 1234567." \
    cat "${tmp}/plan/retire.tsv"

# shfmt failed with an error instead of a diff: its missing hunk proves
# nothing, so T8 stays.
echo 'a.sh:1:1: reached EOF without closing quote' >"${tmp}/lint/shfmt.txt"
plan
check "plan: a failed formatter retires nothing of its own" "T2
T3" cut -f1 "${tmp}/plan/retire.tsv"

# Only mdformat ran, the diff covers both of its hunks, and there are no
# threads.
echo '[{"filename": "doc/x.md", "patch": "@@ -1,9 +1,9 @@"}]' >"${tmp}/files.json"
echo '{"data": {"repository": {"pullRequest": {"reviewThreads": {"nodes": []}}}}}' >"${tmp}/threads.json"
rm "${tmp}/lint/shfmt.txt"
plan
check "plan: a fence longer than the backticks inside" '````suggestion' body_line 0 4
check "plan: a one-line hunk says this line" "mdformat would format this line like this:" body_line 1 2
check "plan: no thread to retire, no retire.tsv" absent exists "${tmp}/plan/retire.tsv"

# No diffs and no threads: nothing to do.
rm "${tmp}/lint/mdformat.txt"
plan
check "plan: nothing to do" "work=false" cat "${tmp}/output"
check "plan: nothing to do, no files" "" ls "${tmp}/plan"

# --- suggestions-apply.sh ---

mkdir -p "${tmp}/apply"
printf 'T2\t100\tNT2\tfalse\tResolved: why.\nT3\t101\tNT3\ttrue\tResolved: why.\n' >"${tmp}/apply/retire.tsv"
echo '{"comments": [{}]}' >"${tmp}/apply/review.json"
check "apply: a plan for an old head changes nothing" "api repos/o/r/pulls/7" apply ffff
check "apply: reply first, then minimize; no second reply; then the review" "api repos/o/r/pulls/7
reply 100 Resolved: why.
minimize NT2
minimize NT3
review" apply "${HEAD_SHA}"

exit "${failed}"
