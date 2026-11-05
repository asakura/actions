# Sourced after check.sh by the tests of scripts that call git ls-remote. Puts
# a stub git first on PATH. "git ls-remote --tags https://github.com/OWNER/REPO"
# prints the file ${tmp}/ls-remote/OWNER/REPO, which a test writes in the
# format of the real command; any other call fails.
# shellcheck shell=bash
# shellcheck disable=SC2154 # tmp is set by check.sh.

mkdir -p "${tmp}/bin" "${tmp}/ls-remote"
cat >"${tmp}/bin/git" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"${STUB_DIR}/git.log"
case "$*" in
    'ls-remote --tags https://github.com/'*)
        cat "${STUB_DIR}/ls-remote/${3#https://github.com/}"
        ;;
    *)
        echo "git stub: unexpected call: $*" >&2
        exit 2
        ;;
esac
STUB
chmod +x "${tmp}/bin/git"

export PATH="${tmp}/bin:${PATH}" STUB_DIR="${tmp}"
