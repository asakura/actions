#!/usr/bin/env bash
# Build a markdown report of all lint checks from their saved outputs.
#
# Usage: lint-report.sh
# Env:
#   LINT_DIR           directory with <tool>.txt outputs (default
#                      $RUNNER_TEMP/lint); report.md is written there.
#   OUTCOME_ACTIONLINT, OUTCOME_ZIZMOR, OUTCOME_SHELLCHECK, OUTCOME_SHFMT
#                      steps.<id>.outcome of each check.
#   OUTCOME_CHANGES    steps.changes.outcome (optional).
#   MAX_OUTPUT_CHARS   cap on the output shown per failed tool (default 12000),
#                      which keeps the report below the 65536-character limit of
#                      a GitHub comment.
# Writes report.md in LINT_DIR; its only reader is the pull request comment.
# Exits 0 even when checks failed: the failing check steps already fail the job.
set -euo pipefail

lint_dir=${LINT_DIR:-${RUNNER_TEMP:?RUNNER_TEMP or LINT_DIR is required}/lint}
max_chars=${MAX_OUTPUT_CHARS:-12000}
mkdir -p "${lint_dir}"

# Print the number of findings in the output of tool $1.
count_findings() {
    local file="${lint_dir}/$1.txt"
    local pattern
    case "$1" in
        actionlint | shellcheck) pattern='^[^:]+:[0-9]+:[0-9]+: ' ;;
        zizmor) pattern='^(error|warning|help|info|note)\[' ;;
        shfmt) pattern='^@@ ' ;;
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

tools=(actionlint zizmor shellcheck shfmt)
outcomes=(
    "${OUTCOME_ACTIONLINT:-skipped}"
    "${OUTCOME_ZIZMOR:-skipped}"
    "${OUTCOME_SHELLCHECK:-skipped}"
    "${OUTCOME_SHFMT:-skipped}"
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
if [[ ${OUTCOME_CHANGES:-success} != success ]]; then
    report+=$'\n'"The changed-files step ${OUTCOME_CHANGES}; see the job log."$'\n'
fi
report+="${details}"

printf '%s' "${report}" >"${lint_dir}/report.md"
