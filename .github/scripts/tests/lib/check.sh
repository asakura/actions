# Sourced by every test. Defines tmp, a scratch directory removed on exit;
# failed, 0 until a check fails; and check. A test ends with: exit "${failed}".
# shellcheck shell=bash
# shellcheck disable=SC2034 # failed is read by the test that sources this file.

tmp=$(mktemp -d)
trap 'rm -rf "${tmp}"' EXIT
failed=0

# check NAME EXPECTED COMMAND...: run COMMAND and compare its output and
# errors with EXPECTED. Prints "ok: NAME", or "FAIL: NAME" with both outputs.
# A command that fails is a failed check, not the end of the test.
check() {
    local name=$1 expected=$2 actual
    shift 2
    actual=$("$@" 2>&1) || actual+=$'\n'"[exit status $?]"
    if [[ ${actual} == "${expected}" ]]; then
        echo "ok: ${name}"
    else
        printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "${name}" "${expected}" "${actual}"
        failed=1
    fi
}
