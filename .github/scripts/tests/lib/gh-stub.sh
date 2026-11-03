# Sourced after check.sh by the tests of scripts that call gh. Puts a stub gh
# first on PATH and sets the pull request the scripts work on: o/r#7, head
# 1234567890abcdef.
#
# The stub logs each call's arguments as one line to ${tmp}/gh.log and answers:
#   the review threads query   with ${tmp}/threads.json;
#   pulls/7/files              with ${tmp}/files.json;
#   pulls/7                    with a head SHA of ${STUB_HEAD};
#   anything else              with nothing.
# shellcheck shell=bash
# shellcheck disable=SC2154 # tmp is set by check.sh.

mkdir -p "${tmp}/bin"
cat >"${tmp}/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >>"${STUB_DIR}/gh.log"
case "$*" in
    *'query($owner'*) cat "${STUB_DIR}/threads.json" ;;
    *'/pulls/7/files'*) cat "${STUB_DIR}/files.json" ;;
    'api repos/o/r/pulls/7') echo "{\"head\": {\"sha\": \"${STUB_HEAD}\"}}" ;;
    *) ;;
esac
STUB
chmod +x "${tmp}/bin/gh"

export PATH="${tmp}/bin:${PATH}" STUB_DIR="${tmp}"
export GITHUB_REPOSITORY=o/r PR_NUMBER=7 HEAD_SHA=1234567890abcdef GH_TOKEN=stub
