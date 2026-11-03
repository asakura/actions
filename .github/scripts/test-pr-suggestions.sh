#!/usr/bin/env bash
# Test pr-suggestions.sh without network: its pure steps on diff fixtures taken
# from real shfmt and mdformat-diff.sh output, and its whole flow against a stub
# of gh.
#
# Usage: test-pr-suggestions.sh
# Needs bash and jq only. Prints one line per check and exits 1 on any failure.
# The script-tests job in _lint.yml runs it whenever a script changes.
set -euo pipefail
# The last stage of a pipeline runs in this shell, so expect can count failures.
shopt -s lastpipe

script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/pr-suggestions.sh"
work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT
failures=0

# Check that stdin equals $2 (expected); $1 names the check.
expect() {
    local actual
    actual=$(cat)
    if [[ ${actual} == "$2" ]]; then
        echo "ok   $1"
    else
        echo "FAIL $1"
        echo "  expected: $2"
        echo "  actual:   ${actual}"
        failures=$((failures + 1))
    fi
}

# --- fixtures ---------------------------------------------------------------

# shfmt --diff of two scripts (paths as given on the command line).
cat >"${work}/shfmt.txt" <<'EOF'
diff .github/scripts/a.sh.orig .github/scripts/a.sh
--- .github/scripts/a.sh.orig
+++ .github/scripts/a.sh
@@ -1,9 +1,8 @@
 #!/usr/bin/env bash
 set -eu
-if true;then
-echo   a
+if true; then
+    echo a
 fi
 
-
 x=1
-for i in 1;do echo $i;done
+for i in 1; do echo $i; done
diff .github/scripts/b.sh.orig .github/scripts/b.sh
--- .github/scripts/b.sh.orig	2026-01-01 00:00:00.000000000 +0000
+++ .github/scripts/b.sh	2026-01-01 00:00:00.000000000 +0000
@@ -1,3 +1,4 @@
 #!/usr/bin/env bash
+
 set -eu
 echo b
@@ -10,4 +11,3 @@
 e
 f
-
 g
EOF

# mdformat-diff.sh output: two hunks in one file; another file whose new text
# holds a fenced block (a pure insertion), and a removed line that looks like a
# file header.
cat >"${work}/mdformat.txt" <<'EOF'
--- a/README.md
+++ b/README.md
@@ -1,7 +1,7 @@
 # T
 
-* a
-* b
+- a
+- b
 
 ```sh
 x
@@ -9,6 +9,4 @@
 
 text
 
-
-
 more
--- a/docs/fence.md
+++ b/docs/fence.md
@@ -3,3 +3,6 @@
 intro
 
+````text
+```sh
+````
 outro
--- a/docs/dash.md
+++ b/docs/dash.md
@@ -1,3 +1,2 @@
 start
--- not a header
 end
EOF

readme=$'# T\n\n* a\n* b\n\n```sh\nx\n```\n\ntext\n\n\n\nmore\n'

# --- parse ------------------------------------------------------------------

hunks=$(bash "${script}" parse shfmt <"${work}/shfmt.txt")
jq -r '"\(.path):\(.start)-\(.end)"' <<<"${hunks}" | paste -sd' ' |
    expect "shfmt: hunks over two files" ".github/scripts/a.sh:3-9 .github/scripts/b.sh:1-1 .github/scripts/b.sh:12-12"
# shellcheck disable=SC2016 # the expected text is literal
jq -c 'select(.start == 3) | .new' <<<"${hunks}" |
    expect "shfmt: new lines of the first hunk" '["if true; then","    echo a","fi","","x=1","for i in 1; do echo $i; done"]'
# shellcheck disable=SC2016 # the expected text is literal
jq -c 'select(.start == 3) | .old' <<<"${hunks}" |
    expect "shfmt: context between changes stays inside the range" '["if true;then","echo   a","fi","","","x=1","for i in 1;do echo $i;done"]'
jq -r 'select(.start == 1) | .path' <<<"${hunks}" |
    expect "shfmt: a timestamp is not part of the path" ".github/scripts/b.sh"
jq -c 'select(.path | endswith("b.sh")) | select(.start == 1) | [.old, .new]' <<<"${hunks}" |
    expect "shfmt: pure insertion anchors to the line before" '[["#!/usr/bin/env bash"],["#!/usr/bin/env bash",""]]'
jq -c 'select(.start == 12) | [.old, .new]' <<<"${hunks}" |
    expect "shfmt: a pure deletion is a range of its removed line, with no new line" '[[""],[]]'

mdhunks=$(bash "${script}" parse mdformat <"${work}/mdformat.txt")
jq -r '"\(.path):\(.start)-\(.end)"' <<<"${mdhunks}" | paste -sd' ' |
    expect "mdformat: a/ and b/ are stripped from paths" "README.md:3-4 README.md:12-13 docs/fence.md:4-4 docs/dash.md:2-2"
jq -c 'select(.path == "docs/dash.md") | .old' <<<"${mdhunks}" |
    expect "mdformat: a removed line that looks like a header stays a line" '["-- not a header"]'
bash "${script}" parse mdformat </dev/null | wc -l | tr -d ' ' |
    expect "mdformat: nothing in, nothing out" 0

# --- marker -----------------------------------------------------------------

jq -r 'select(.start == 3 and .tool == "mdformat") | .marker' <<<"${mdhunks}" |
    sed -E 's/sha=[0-9a-f]{64}/sha=SHA/' |
    expect "marker: tool, path, lines and sha of the suggested text" '<!-- lint-suggestion tool=mdformat path=README.md lines=3-4 sha=SHA -->'
want_sha=$(printf -- '- a\n- b\n' | sha256sum | cut -d' ' -f1)
jq -r 'select(.start == 3 and .tool == "mdformat") | .marker' <<<"${mdhunks}" | grep -o 'sha=[0-9a-f]*' |
    expect "marker: sha is sha256 of the suggested text" "sha=${want_sha}"
again=$(bash "${script}" parse mdformat <"${work}/mdformat.txt")
printf '%s\n' "${again}" |
    expect "marker: stable for the same diff" "${mdhunks}"

# --- render -----------------------------------------------------------------

rendered=$(bash "${script}" render <<<"${mdhunks}")
jq -c 'select(.comment.path == "README.md" and .comment.line == 4) | .comment | [.start_line, .line, .side, .start_side]' <<<"${rendered}" |
    expect "render: multi-line range" '[3,4,"RIGHT","RIGHT"]'
jq -c 'select(.comment.path == "docs/dash.md") | .comment | has("start_line")' <<<"${rendered}" |
    expect "render: single line has no start_line" false
# shellcheck disable=SC2016 # the expected text is literal
jq -r 'select(.comment.path == "docs/fence.md") | .comment.body' <<<"${rendered}" | sed -n '4p;$p' | paste -sd' ' |
    expect "render: suggestion fence is longer than any backtick run inside" '`````suggestion `````'
# shellcheck disable=SC2016 # the expected text is literal
jq -r 'select(.comment.path == "README.md" and .comment.line == 4) | .comment.body' <<<"${rendered}" | sed -n '4p' |
    expect "render: plain content uses three backticks" '```suggestion'
jq -r 'select(.comment.path == "README.md" and .comment.line == 13) | .comment.body' <<<"${rendered}" | tail -n 4 |
    expect "render: deletion gives an empty suggestion" $'mdformat would remove these lines:\n\n```suggestion\n```'

# --- ranges and fit ---------------------------------------------------------

cat >"${work}/files.json" <<'EOF'
[{"filename": "README.md", "status": "modified", "patch": "@@ -1,3 +1,5 @@\n a\n+b\n c\n@@ -20 +22 @@\n-x\n+y"},
 {"filename": "gone.md", "status": "removed", "patch": "@@ -1,2 +0,0 @@\n-a\n-b"},
 {"filename": "big.bin", "status": "modified"}]
[{"filename": ".github/scripts/a.sh", "status": "added", "patch": "@@ -0,0 +1,9 @@\n+a"}]
EOF
bash "${script}" ranges <"${work}/files.json" >"${work}/ranges.tsv"
paste -sd' ' <"${work}/ranges.tsv" | tr '\t' ':' |
    expect "ranges: RIGHT-side ranges over two pages, without removed or patchless files" "README.md:1:5 README.md:22:22 .github/scripts/a.sh:1:9"

all=$(
    jq -nc '{path: "README.md", start: 2, end: 4}'
    jq -nc '{path: "README.md", start: 4, end: 6}'
    jq -nc '{path: "README.md", start: 22, end: 22}'
    jq -nc '{path: "README.md", start: 21, end: 22}'
    jq -nc '{path: ".github/scripts/a.sh", start: 9, end: 9}'
    jq -nc '{path: ".github/scripts/a.sh", start: 9, end: 10}'
    jq -nc '{path: "other.md", start: 1, end: 1}'
    jq -nc '{path: "README.md", start: 0, end: 0}'
)
bash "${script}" fit "${work}/ranges.tsv" <<<"${all}" | jq -r '"\(.path):\(.start)-\(.end)"' | paste -sd' ' |
    expect "fit: only ranges inside one hunk of the pull request diff" "README.md:2-4 README.md:22-22 .github/scripts/a.sh:9-9"

# --- matches ----------------------------------------------------------------

printf '%s' "${readme}" >"${work}/head-readme"
bash "${script}" matches "${work}/head-readme" <<<"${mdhunks}" | jq -r 'select(.path == "README.md") | .start' | paste -sd' ' |
    expect "matches: old lines equal the head file" "3 12"
printf '%s' "${readme/\* a/* changed}" >"${work}/head-readme-changed"
bash "${script}" matches "${work}/head-readme-changed" <<<"${mdhunks}" | jq -r 'select(.path == "README.md") | .start' | paste -sd' ' |
    expect "matches: a head file that differs drops the hunk" "12"

# --- flow against a stub of gh ----------------------------------------------

stub_bin="${work}/bin"
mkdir -p "${stub_bin}"
cat >"${stub_bin}/gh" <<'EOF'
#!/usr/bin/env bash
# Stub of gh api: state in $STUB_DIR (head_sha, files.json, threads.json,
# head/<path>); every write is appended to $STUB_DIR/calls.log.
set -euo pipefail
args=("$@")
jq_filter="" input="" body="" query="" id="" endpoint=""
for ((i = 0; i < ${#args[@]}; i++)); do
    case "${args[i]}" in
        --jq) jq_filter=${args[i + 1]} ;;
        --input) input=${args[i + 1]} ;;
        -f) case "${args[i + 1]}" in body=*) body=${args[i + 1]#body=} ;; query=*) query=${args[i + 1]#query=} ;; *) ;; esac ;;
        -F) case "${args[i + 1]}" in id=*) id=${args[i + 1]#id=} ;; *) ;; esac ;;
        repos/*) endpoint=${args[i]} ;;
        *) ;;
    esac
done
[[ ${args[0]} == api ]] || exit 1
case "${endpoint}" in
    */pulls/7) cat "${STUB_DIR}/head_sha" ;;
    */pulls/7/files) cat "${STUB_DIR}/files.json" ;;
    */contents/*)
        path=${endpoint#*/contents/}
        cat "${STUB_DIR}/head/${path%%\?*}"
        ;;
    */pulls/7/reviews)
        cp "${input}" "${STUB_DIR}/review.json"
        echo "review $(jq '.comments | length' "${input}")" >>"${STUB_DIR}/calls.log"
        ;;
    */comments/*/replies)
        n=${endpoint#*comments/}
        if [[ ${STUB_FAIL_REPLY:-} == "${n%%/*}" ]]; then
            echo "gh: Resource not accessible by integration (HTTP 403)" >&2
            exit 1
        fi
        echo "reply ${n%%/*}: ${body}" >>"${STUB_DIR}/calls.log"
        ;;
    "")
        if [[ ${query} == mutation* ]]; then
            if [[ ${STUB_FAIL_MINIMIZE:-} == "${id}" ]]; then
                echo "gh: Resource not accessible by integration" >&2
                exit 1
            fi
            [[ ${query} =~ classifier:\ ([A-Z]+) ]]
            echo "minimize ${id} ${BASH_REMATCH[1]}" >>"${STUB_DIR}/calls.log"
        else
            jq -r "${jq_filter}" "${STUB_DIR}/threads.json"
        fi
        ;;
    *) exit 1 ;;
esac
EOF
chmod +x "${stub_bin}/gh"

export PATH="${stub_bin}:${PATH}"
export STUB_DIR="${work}/stub"
export GITHUB_REPOSITORY=o/r PR_NUMBER=7 HEAD_SHA=abcdef1234567890 GH_TOKEN=x
export LINT_DIR="${work}/lint"
mkdir -p "${STUB_DIR}/head/docs" "${STUB_DIR}/head/.github/scripts" "${LINT_DIR}"
ten_lines=$'#!/usr/bin/env bash\nset -eu\nif true;then\necho   a\nfi\n\n\nx=1\nfor i in 1;do echo $i;done\n'
printf '%s' "${ten_lines}" >"${STUB_DIR}/head/.github/scripts/a.sh"
printf '%s' "${readme}" >"${STUB_DIR}/head/README.md"
cat >"${STUB_DIR}/files.json" <<'EOF'
[{"filename": "README.md", "status": "added", "patch": "@@ -0,0 +1,13 @@\n+x"},
 {"filename": ".github/scripts/a.sh", "status": "added", "patch": "@@ -0,0 +1,9 @@\n+x"}]
EOF

# Only the a.sh hunks of shfmt and README.md hunks of mdformat are in the fixture.
sed '/^diff .*b.sh/,$d' "${work}/shfmt.txt" >"${LINT_DIR}/shfmt.txt"
sed '/^--- a\/docs\/fence.md/,$d' "${work}/mdformat.txt" >"${LINT_DIR}/mdformat.txt"

# Reset the stub: $1 is the head sha.
reset_stub() {
    : >"${STUB_DIR}/calls.log"
    rm -f "${STUB_DIR}/review.json"
    echo "$1" >"${STUB_DIR}/head_sha"
    echo '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]}}}}}' >"${STUB_DIR}/threads.json"
}

# Set the review threads to the lines of stdin:
# id|isOutdated|isResolved|databaseId|marker[|isMinimized[|hasReply]].
# The first comment has node id "C<id>"; a reply is one of ours saying "Resolved".
set_threads() {
    jq -Rn '{data: {repository: {pullRequest: {reviewThreads: {nodes: [inputs | split("|") | {
        id: .[0], isOutdated: (.[1] == "true"), isResolved: (.[2] == "true"),
        comments: {nodes: ([{id: ("C" + .[0]), databaseId: (.[3] | tonumber), body: (.[4] + "\nbody"),
            isMinimized: (.[5] == "true"), author: {login: "github-actions"}}]
            + (if .[6] == "true" then [{id: "R", databaseId: 1, body: "Resolved: earlier",
                isMinimized: false, author: {login: "github-actions"}}] else [] end))}}]}}}}}' \
        >"${STUB_DIR}/threads.json"
}

run_sync() {
    LINT_RESULT=${LINT_RESULT:-failure} bash "${script}" sync 2>&1
}

reset_stub "${HEAD_SHA}"
out=$(run_sync)
expect "new findings: one review with the three suggestions" "review 3" <"${STUB_DIR}/calls.log"
jq -r '[.event, .commit_id] | join(" ")' "${STUB_DIR}/review.json" |
    expect "new findings: review is a COMMENT on the run's commit" "COMMENT abcdef1234567890"
jq -r '[.comments[].side] | unique | join(" ")' "${STUB_DIR}/review.json" |
    expect "new findings: every comment is on the RIGHT side" "RIGHT"
{ jq -r '.body' "${STUB_DIR}/review.json" | grep -c 'cannot be suggested' || true; } |
    expect "new findings: no unsuggested note when all hunks fit" 0
echo "--- review body"
jq -r '.body' "${STUB_DIR}/review.json"
echo "--- first comment"
jq -r '.comments[0] | "\(.path):\(.start_line // .line)-\(.line)\n\(.body)"' "${STUB_DIR}/review.json"
echo "---"

# Existing threads for the same findings, as the first run posted them.
markers=$(jq -r '.comments[].body | split("\n")[0]' "${STUB_DIR}/review.json")
threads_for() {
    local n=0 marker
    while IFS= read -r marker; do
        n=$((n + 1))
        echo "T${n}|${1:-false}|false|$((100 + n))|${marker}"
    done <<<"${markers}"
}
reset_stub "${HEAD_SHA}"
threads_for | set_threads
run_sync >/dev/null
expect "re-run with the same findings: nothing posted, nothing resolved" "" <"${STUB_DIR}/calls.log"

reset_stub "${HEAD_SHA}"
threads_for true | set_threads
run_sync >/dev/null
replies=$(grep -c '^reply' "${STUB_DIR}/calls.log")
resolves=$(grep -c '^minimize' "${STUB_DIR}/calls.log")
reviews=$(grep -c '^review 3' "${STUB_DIR}/calls.log")
printf '%s\n' "${replies} ${resolves} ${reviews}" |
    expect "outdated threads: replied to, minimized, and posted again" "3 3 1"
grep '^reply 101' "${STUB_DIR}/calls.log" |
    expect "outdated threads: the reason" "reply 101: Resolved: superseded; these lines changed at abcdef1."

reset_stub "${HEAD_SHA}"
first_marker=$(sed -n 1p <<<"${markers}")
{
    threads_for
    echo "Tdup|false|false|900|${first_marker}"
} | set_threads
run_sync >/dev/null
expect "duplicate thread: replied to and minimized as DUPLICATE, nothing posted" $'reply 900: Duplicate of an earlier suggestion.\nminimize CTdup DUPLICATE' <"${STUB_DIR}/calls.log"

reset_stub "${HEAD_SHA}"
{
    threads_for
    echo "Told|false|false|950|<!-- lint-suggestion tool=mdformat path=README.md lines=1-2 sha=00 -->"
    echo "Tsh|false|false|951|<!-- lint-suggestion tool=shfmt path=.github/scripts/a.sh lines=1-2 sha=00 -->"
    echo "Tres|false|true|952|<!-- lint-suggestion tool=shfmt path=x lines=1-2 sha=00 -->"
    echo "Tmin|false|false|953|<!-- lint-suggestion tool=shfmt path=y lines=1-2 sha=00 -->|true"
} | set_threads
run_sync >/dev/null
expect "different findings: stale threads get the reason and are minimized; resolved and minimized ones are untouched" $'reply 950: Resolved: mdformat no longer reports these lines at abcdef1.\nminimize CTold RESOLVED\nreply 951: Resolved: shfmt no longer reports these lines at abcdef1.\nminimize CTsh RESOLVED' <"${STUB_DIR}/calls.log"

reset_stub "${HEAD_SHA}"
echo "Told|false|false|950|<!-- lint-suggestion tool=mdformat path=README.md lines=1-2 sha=00 -->" | set_threads
rm -f "${LINT_DIR}/shfmt.txt" "${LINT_DIR}/mdformat.txt"
LINT_RESULT=success run_sync >/dev/null
expect "pass after failure: reply and minimize, no review" $'reply 950: Resolved: mdformat no longer reports these lines at abcdef1.\nminimize CTold RESOLVED' <"${STUB_DIR}/calls.log"
reset_stub "${HEAD_SHA}"
LINT_RESULT=success run_sync >/dev/null
expect "pass with no thread: nothing" "" <"${STUB_DIR}/calls.log"

reset_stub "${HEAD_SHA}"
echo "Trep|true|false|960|<!-- lint-suggestion tool=mdformat path=README.md lines=1-2 sha=00 -->|false|true" | set_threads
LINT_RESULT=success run_sync >/dev/null
expect "already replied: no second reply, only the minimize" "minimize CTrep RESOLVED" <"${STUB_DIR}/calls.log"

reset_stub "${HEAD_SHA}"
{
    echo "Tfail|false|false|970|<!-- lint-suggestion tool=mdformat path=README.md lines=1-2 sha=00 -->"
    echo "Tnext|false|false|971|<!-- lint-suggestion tool=mdformat path=README.md lines=3-4 sha=00 -->"
} | set_threads
set +e
out=$(STUB_FAIL_REPLY=970 LINT_RESULT=success run_sync)
status=$?
set -e
expect "failed reply: the next thread is still retired" $'reply 971: Resolved: mdformat no longer reports these lines at abcdef1.\nminimize CTnext RESOLVED' <"${STUB_DIR}/calls.log"
printf '%s\n' "${status}" | expect "failed reply: exit status is 1" 1
printf '%s\n' "${out}" | grep 'error:' |
    expect "failed reply: says what failed and why" "error: could not reply on thread Tfail: gh: Resource not accessible by integration (HTTP 403)"

reset_stub "${HEAD_SHA}"
{
    echo "Tfail|false|false|970|<!-- lint-suggestion tool=mdformat path=README.md lines=1-2 sha=00 -->"
    echo "Tnext|false|false|971|<!-- lint-suggestion tool=mdformat path=README.md lines=3-4 sha=00 -->"
} | set_threads
set +e
out=$(STUB_FAIL_MINIMIZE=CTfail LINT_RESULT=success run_sync)
status=$?
set -e
expect "failed minimize: the next thread is still retired" $'reply 970: Resolved: mdformat no longer reports these lines at abcdef1.\nreply 971: Resolved: mdformat no longer reports these lines at abcdef1.\nminimize CTnext RESOLVED' <"${STUB_DIR}/calls.log"
printf '%s\n' "${status}" | expect "failed minimize: exit status is 1" 1
printf '%s\n' "${out}" | grep 'error:' |
    expect "failed minimize: says what failed and why" "error: could not minimize the suggestion on thread Tfail: gh: Resource not accessible by integration"

echo "mdformat: error: cannot read README.md" >"${LINT_DIR}/mdformat.txt"
reset_stub "${HEAD_SHA}"
echo "Told|false|false|950|<!-- lint-suggestion tool=mdformat path=README.md lines=1-2 sha=00 -->" | set_threads
run_sync >/dev/null
expect "crashed tool: its threads are left alone" "" <"${STUB_DIR}/calls.log"

sed '/^diff .*b.sh/,$d' "${work}/shfmt.txt" >"${LINT_DIR}/shfmt.txt"
sed '/^--- a\/docs\/fence.md/,$d' "${work}/mdformat.txt" >"${LINT_DIR}/mdformat.txt"
reset_stub "feedface"
echo "Told|false|false|950|<!-- lint-suggestion tool=mdformat path=README.md lines=1-2 sha=00 -->" | set_threads
out=$(run_sync)
expect "head moved: no write at all" "" <"${STUB_DIR}/calls.log"
printf '%s\n' "${out}" |
    expect "head moved: says why" "lint ran on abcdef1234567890, but the pull request head is feedface; leaving the suggestions alone"

reset_stub "${HEAD_SHA}"
MAX_SUGGESTIONS=2 run_sync >/dev/null
expect "cap: only the first two are posted" "review 2" <"${STUB_DIR}/calls.log"
jq -r '.body' "${STUB_DIR}/review.json" | grep -c 'Only the first 2 suggestions are posted; 1 more' |
    expect "cap: the review says how many stay in the lint comment" 1

reset_stub "${HEAD_SHA}"
printf '%s' "${readme/\* a/* changed}" >"${STUB_DIR}/head/README.md"
run_sync >/dev/null
jq -r '"\(.comments | length) " + (.body | tostring | gsub("\n"; " "))' "${STUB_DIR}/review.json" | grep -c '^2 .*1 more formatter hunks cannot be suggested' |
    expect "head file differs: those hunks are not suggested, and the review says so" 1
printf '%s' "${readme}" >"${STUB_DIR}/head/README.md"

reset_stub "${HEAD_SHA}"
printf '%s\n' '[{"filename": "README.md", "status": "added", "patch": "@@ -0,0 +1,2 @@\n+x"}]' >"${STUB_DIR}/files.json"
run_sync >/dev/null
expect "outside the pull request diff: nothing to post, no empty review" "" <"${STUB_DIR}/calls.log"

# --- find -------------------------------------------------------------------

export GITHUB_OUTPUT="${work}/output"
: >"${GITHUB_OUTPUT}"
reset_stub "${HEAD_SHA}"
bash "${script}" find >/dev/null
expect "find: findings in the output files mean work" "work=true" <"${GITHUB_OUTPUT}"
: >"${LINT_DIR}/shfmt.txt"
: >"${LINT_DIR}/mdformat.txt"
: >"${GITHUB_OUTPUT}"
bash "${script}" find >/dev/null
expect "find: no findings and no thread mean no work" "work=false" <"${GITHUB_OUTPUT}"
echo "Told|false|false|950|<!-- lint-suggestion tool=mdformat path=README.md lines=1-2 sha=00 -->" | set_threads
: >"${GITHUB_OUTPUT}"
bash "${script}" find >/dev/null
expect "find: an active suggestion thread means work" "work=true" <"${GITHUB_OUTPUT}"
echo "Tmin|false|false|950|<!-- lint-suggestion tool=mdformat path=README.md lines=1-2 sha=00 -->|true" | set_threads
: >"${GITHUB_OUTPUT}"
bash "${script}" find >/dev/null
expect "find: a minimized suggestion is not work" "work=false" <"${GITHUB_OUTPUT}"
echo "Thum|false|true|950|<!-- lint-suggestion tool=mdformat path=README.md lines=1-2 sha=00 -->" | set_threads
: >"${GITHUB_OUTPUT}"
bash "${script}" find >/dev/null
expect "find: a thread a person resolved is not work" "work=false" <"${GITHUB_OUTPUT}"

if ((failures > 0)); then
    echo "${failures} check(s) failed"
    exit 1
fi
echo "all checks passed"
