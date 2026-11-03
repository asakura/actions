#!/usr/bin/env bash
# Carry out the plan suggestions-plan.sh wrote: retire the suggestion threads
# that no longer apply, then post the new suggestions in one review.
#
# Usage: suggestions-apply.sh
# Env:
#   GITHUB_REPOSITORY  owner/name.
#   PR_NUMBER          pull request number.
#   HEAD_SHA           head commit the plan was made for.
#   GH_TOKEN           token with pull-requests: write.
#   PLAN_DIR           directory with review.json and retire.tsv; either may be
#                      missing.
# Nothing is deleted: a retired thread first gets the plan's reply saying why
# (unless it already has one), then its suggestion is minimized as resolved.
# The thread itself is not resolved; that needs contents: write. A plan for a
# commit that is no longer the head changes nothing.
set -euo pipefail

: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${PR_NUMBER:?PR_NUMBER is required}"
: "${HEAD_SHA:?HEAD_SHA is required}"
: "${PLAN_DIR:?PLAN_DIR is required}"

current_sha=$(gh api "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}" | jq -r '.head.sha')
if [[ ${current_sha} != "${HEAD_SHA}" ]]; then
    echo "the plan is for ${HEAD_SHA}, but the pull request head is ${current_sha}; changing nothing"
    exit 0
fi

if [[ -f ${PLAN_DIR}/retire.tsv ]]; then
    while IFS=$'\t' read -r thread_id comment_id node_id replied reply; do
        if [[ ${replied} == false ]]; then
            gh api --method POST --silent \
                "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/comments/${comment_id}/replies" \
                -f body="${reply}"
            echo "replied on thread ${thread_id}"
        fi
        # shellcheck disable=SC2016 # $id is a GraphQL variable.
        gh api graphql --silent \
            -f query='mutation($id: ID!) { minimizeComment(input: {subjectId: $id, classifier: RESOLVED}) { minimizedComment { isMinimized } } }' \
            -F id="${node_id}"
        echo "minimized the suggestion on thread ${thread_id}"
    done <"${PLAN_DIR}/retire.tsv"
fi

if [[ -f ${PLAN_DIR}/review.json ]]; then
    gh api --method POST --silent "repos/${GITHUB_REPOSITORY}/pulls/${PR_NUMBER}/reviews" \
        --input "${PLAN_DIR}/review.json"
    count=$(jq '.comments | length' "${PLAN_DIR}/review.json")
    echo "posted a review with ${count} suggestions"
fi
