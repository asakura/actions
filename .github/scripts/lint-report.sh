#!/usr/bin/env bash
# Build a markdown report of all lint checks from their saved outputs.
#
# Usage: lint-report.sh
# Env:
#   LINT_DIR           directory with <tool>.txt outputs; report.md is
#                      written there.
#   OUTCOME_ACTIONLINT, OUTCOME_ZIZMOR, OUTCOME_PIN_COMMENTS,
#   OUTCOME_PIN_CHANGES, OUTCOME_SHELLCHECK, OUTCOME_SHFMT, OUTCOME_TESTS,
#   OUTCOME_MDFORMAT
#                      steps.<id>.outcome of each check.
#   OUTCOME_CHANGES    steps.changes.outcome.
#   OUTCOME_SUGGESTIONS steps.suggestions.outcome.
#   MAX_OUTPUT_CHARS   cap on the output shown per failed tool, which keeps
#                      the report below the 65536-character limit of a
#                      GitHub comment.
# Writes report.md in LINT_DIR; its only reader is the pull request comment.
# Exits 0 even when checks failed: the failing check steps already fail the job.
set -euo pipefail

lint_dir=${LINT_DIR:?LINT_DIR is required}
max_chars=${MAX_OUTPUT_CHARS:?MAX_OUTPUT_CHARS is required}
outcome_changes=${OUTCOME_CHANGES:?OUTCOME_CHANGES is required}
outcome_suggestions=${OUTCOME_SUGGESTIONS:?OUTCOME_SUGGESTIONS is required}
mkdir -p "${lint_dir}"

# Print the number of findings in the output of tool $1.
count_findings() {
    local file="${lint_dir}/$1.txt"
    local pattern
    case "$1" in
        actionlint | pin-comments | pin-changes | shellcheck) pattern='^[^:]+:[0-9]+:[0-9]+: ' ;;
        zizmor) pattern='^(error|warning|help|info|note)\[' ;;
        shfmt | mdformat) pattern='^@@ ' ;;
        tests) pattern='^FAIL: ' ;;
        *)
            echo "count_findings: unknown tool $1" >&2
            return 1
            ;;
    esac
    if [[ -f ${file} ]]; then
        grep -cE "${pattern}" "${file}" || true
    else
        echo 0
    fi
}

tools=(actionlint zizmor pin-comments pin-changes shellcheck shfmt tests mdformat)
outcomes=(
    "${OUTCOME_ACTIONLINT:?OUTCOME_ACTIONLINT is required}"
    "${OUTCOME_ZIZMOR:?OUTCOME_ZIZMOR is required}"
    "${OUTCOME_PIN_COMMENTS:?OUTCOME_PIN_COMMENTS is required}"
    "${OUTCOME_PIN_CHANGES:?OUTCOME_PIN_CHANGES is required}"
    "${OUTCOME_SHELLCHECK:?OUTCOME_SHELLCHECK is required}"
    "${OUTCOME_SHFMT:?OUTCOME_SHFMT is required}"
    "${OUTCOME_TESTS:?OUTCOME_TESTS is required}"
    "${OUTCOME_MDFORMAT:?OUTCOME_MDFORMAT is required}"
)

table=$'| tool | result | findings |\n| --- | --- | --- |'
details=""

for i in "${!tools[@]}"; do
    tool=${tools[i]}
    case "${outcomes[i]}" in
        success)
            table+=$'\n'"| ${tool} | passed | 0 |"
            ;;
        failure)
            findings=$(count_findings "${tool}")
            # A failure without parseable findings means the tool itself errored.
            if [[ ${findings} == 0 ]]; then
                findings="tool error"
            fi
            table+=$'\n'"| ${tool} | failed | ${findings} |"
            body=""
            if [[ -f "${lint_dir}/${tool}.txt" ]]; then
                # Cut by bytes (never fewer characters than bytes allow), then
                # drop a partial trailing UTF-8 sequence.
                body=$(head -c "${max_chars}" "${lint_dir}/${tool}.txt" | iconv -c -f UTF-8 -t UTF-8 || true)
                size=$(wc -c <"${lint_dir}/${tool}.txt")
                if ((size > max_chars)); then
                    body+=$'\n[... output truncated ...]'
                fi
            fi
            details+=$'\n'"<details><summary>${tool}</summary>"$'\n\n'
            details+='``````text'$'\n'"${body}"$'\n'"\`\`\`\`\`\`"$'\n\n'"</details>"$'\n'
            ;;
        skipped)
            table+=$'\n'"| ${tool} | skipped — no relevant changes | - |"
            ;;
        *)
            table+=$'\n'"| ${tool} | ${outcomes[i]} | - |"
            ;;
    esac
done

report="## lint report"$'\n\n'"${table}"$'\n'
if [[ ${outcome_changes} != success ]]; then
    report+=$'\n'"The changed-files step ${outcome_changes}; see the job log."$'\n'
fi
if [[ ${outcome_suggestions} == failure ]]; then
    report+=$'\n'"Planning the formatter suggestions failed; see the job log."$'\n'
fi
report+="${details}"

printf '%s' "${report}" >"${lint_dir}/report.md"
