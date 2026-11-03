#!/usr/bin/env bash
# shellcheck source-path=SCRIPTDIR
# Test suggestions-apply.sh: the gh calls it makes for a plan, and in what
# order.
set -euo pipefail

tests=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=lib/check.sh
source "${tests}/lib/check.sh"
# shellcheck source=lib/gh-stub.sh
source "${tests}/lib/gh-stub.sh"

# Run suggestions-apply.sh with the pull request head at $1 and print its gh
# calls, without the text of the GraphQL query.
# shellcheck disable=SC2329 # called through check.
apply() {
    : >"${tmp}/gh.log"
    STUB_HEAD=$1 PLAN_DIR="${tmp}/plan" "${tests}/../suggestions-apply.sh" >/dev/null
    sed 's/ -f query=.* -F / -F /' "${tmp}/gh.log"
}

# T2 needs a reply; T3 has one already.
mkdir -p "${tmp}/plan"
printf '%s\t%s\t%s\t%s\t%s\n' \
    T2 100 NT2 false 'Resolved: why.' \
    T3 101 NT3 true 'Resolved: why.' >"${tmp}/plan/retire.tsv"
echo '{"comments": [{}]}' >"${tmp}/plan/review.json"

check "a plan for an older head changes nothing" \
    "api repos/o/r/pulls/7" \
    apply ffff
check "reply, then minimize; no second reply; the review last" \
    "api repos/o/r/pulls/7
api --method POST --silent repos/o/r/pulls/7/comments/100/replies -f body=Resolved: why.
api graphql --silent -F id=NT2
api graphql --silent -F id=NT3
api --method POST --silent repos/o/r/pulls/7/reviews --input ${tmp}/plan/review.json" \
    apply "${HEAD_SHA}"

exit "${failed}"
