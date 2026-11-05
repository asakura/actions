#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Test pin-lines.sh: which lines are pins, the version, exception and ref of
# their comments and the marker line above them, and which marker lines belong
# to no pin.
set -euo pipefail

tests=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/check.sh
source "${tests}/lib/check.sh"

# shellcheck disable=SC2329 # called through check.
pins() {
    "${tests}/../pin-lines.sh" <"${tmp}/file.yml" |
        jq -c 'select(.kind == "pin") | [.line, .version, .marker, .exception, .ref, .inline, .inline_ref]'
}

# shellcheck disable=SC2329 # called through check.
strays() {
    "${tests}/../pin-lines.sh" <"${tmp}/file.yml" |
        jq -c 'select(.kind == "stray") | [.line, .reason, .expected]'
}

sha=$(printf '1%.0s' {1..40})
mark='# pin-comment: no vX.Y.Z tag upstream'
cat >"${tmp}/file.yml" <<YAML
steps:
  - uses: a/b@${sha} # v1.2.3
  - uses: a/b@${sha} # v1
  - uses: a/b@${sha}
  ${mark}
  - uses: a/b@${sha} # v23
  - name: x
    ${mark}
    uses: a/b/c@${sha} # release/1.26
  ${mark}
  - uses: a/b@${sha} # two words
  ${mark}
  - uses: a/b@${sha} # v1.2.3
  ${mark}
  - uses: a/b@${sha}
  - uses: a/b@${sha} # v23 ${mark}
  - uses: a/b@${sha} # v1.2.3 ${mark}
  - uses: a/b@${sha} # v23 # pin-comment: no tag
  - uses: ./local
  - uses: a/b@v1
YAML
check "versions, markers, exceptions, refs and the inline form by line; other lines are no pins" \
    '[2,"v1.2.3",false,false,"v1.2.3",false,null]
[3,null,false,false,null,false,null]
[4,null,false,false,null,false,null]
[6,null,true,true,"v23",false,null]
[9,null,true,true,"release/1.26",false,null]
[11,null,true,false,null,false,null]
[13,"v1.2.3",true,false,"v1.2.3",false,null]
[15,null,true,false,null,false,null]
[16,null,false,false,null,true,"v23"]
[17,null,false,false,null,true,"v1.2.3"]
[18,null,false,false,null,true,null]' \
    pins
check "no marker line is stray when it is above a pin, even a pin it cannot serve" "" strays

# A marker line needs the exact text, the pin directly below and the
# indentation of the pin's line.
cat >"${tmp}/file.yml" <<YAML
steps:
  ${mark}
  - run: true
  ${mark}

    ${mark}
  - uses: a/b@${sha} # v23
 ${mark}
  - uses: a/b@${sha} # v23
  # pin-comment: no tag
  - uses: a/b@${sha} # v23
  - name: x
  ${mark}
    uses: a/b@${sha} # v23
  ${mark}
YAML
check "stray marker lines by line, with the reason and the indentation of the pin below" \
    '[2,"target",null]
[4,"target",null]
[6,"indent",2]
[8,"indent",2]
[10,"text",2]
[13,"indent",4]
[15,"target",null]' \
    strays

exit "${failed}"
