#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Test pin-lines.sh: which lines are pins, and the version, exception and ref
# of their comments.
set -euo pipefail

tests=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/check.sh
source "${tests}/lib/check.sh"

# shellcheck disable=SC2329 # called through check.
pins() {
    "${tests}/../pin-lines.sh" <"${tmp}/file.yml" | jq -c '[.line, .version, .exception, .ref]'
}

sha=$(printf '1%.0s' {1..40})
cat >"${tmp}/file.yml" <<YAML
steps:
  - uses: a/b@${sha} # v1.2.3
  - uses: a/b@${sha} # v1
  - uses: a/b@${sha}
  - uses: a/b@${sha} # v23 # pin-comment: no vX.Y.Z tag upstream
  - uses: a/b/c@${sha} # release/1.26 # pin-comment: no vX.Y.Z tag upstream
  - uses: a/b@${sha} # two words # pin-comment: no vX.Y.Z tag upstream
  - uses: a/b@${sha} # v23 # pin-comment: no tag
  - uses: a/b@${sha} # v23 # pin-comment: no vX.Y.Z tag upstream, really
  - uses: ./local
  - uses: a/b@v1
YAML
check "versions, exceptions and refs by line; other lines are no pins" \
    '[2,"v1.2.3",false,"v1.2.3"]
[3,null,false,null]
[4,null,false,null]
[5,null,true,"v23"]
[6,null,true,"release/1.26"]
[7,null,false,null]
[8,null,false,null]
[9,null,false,null]' \
    pins

exit "${failed}"
