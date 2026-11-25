# asakura/actions

Reusable GitHub Actions workflows and composite actions shared by `asakura/*` repositories.

Consumers pin a full commit SHA of a tagged release (`uses: asakura/actions/.github/workflows/<name>.yml@<sha> # vX.Y.Z`).
Tags are immutable; there is no moving `v1` tag.

## Pinning actions

Every `uses: owner/repo@<sha>` in this repository's workflows and actions is pinned to a full commit SHA, and its line ends with the tag that points at that commit: `# vX.Y.Z`, with all three numbers.
The lint workflow suggests the tag when the comment is missing or wrong, and fails when the same action and version are pinned to different commits.

Some upstream actions publish no `vX.Y.Z` tag, only a moving tag such as `v29` or a branch such as `stable`.
For those, put a marker line directly above the `uses:` line and end the `uses:` line with the upstream tag or branch the commit was taken from:

```yaml
      # pin-comment: no vX.Y.Z tag upstream
      - uses: DeterminateSystems/update-flake-lock@<40-hex sha> # v29
```

The marker line holds only indentation and exactly `# pin-comment: no vX.Y.Z tag upstream`.
Its indentation is the column of the first non-space character of the `uses:` line: aligned with the `-` of `- uses:`, or with `uses` when it is a key under `- name:`.
The marker is not on the `uses:` line, because zizmor reads everything after the first `#` there as the version and reports a comment that holds no version.
The `uses:` line ends with `# <ref>`, one word without spaces, for example `v29`, `stable` or `1.26`, and nothing after it.
The lint workflow accepts this only while no `vX.Y.Z` tag of that repository points at the pinned commit; once one does, it asks for `# vX.Y.Z` and no marker instead.
A marker after the ref on the `uses:` line itself fails the lint, with a suggestion that moves it to its own line above.
A marker line that is not directly above a pin, has other text, is indented differently from the `uses:` line below it, or sits above a line that does not end with `# <ref>` fails the lint too.
A version must keep the same commit: the lint workflow fails a pull request that pins an action and `vX.Y.Z` to another commit than the merge base, or to two commits.
A pin with the marker is exempt from that check, because upstream moves `v29` or `stable` on purpose, so a bump of such a pin to a newer commit passes.
A marker added to a `# vX.Y.Z` pin does not exempt it.
For a branch ref such as `stable`, this lint therefore has no SHA check at all: nothing verifies where the new commit comes from, so review every bump of such a pin yourself.
Renovate reads the first comment of the `uses:` line as the tag.

Units are added incrementally; see each unit's section below once it lands.

## setup-nix

Composite action `.github/actions/setup-nix`: installs community (upstream) Nix.
It downloads the Determinate `nix-installer` binary from its GitHub release, verifies a pinned sha256 and runs it with `--prefer-upstream-nix`.
Determinate Nix, FlakeHub login and installer telemetry are all off, and the runner user is not made a trusted Nix user.
It is tested on GitHub-hosted `ubuntu-26.04` x64 runners; any runner that is not Linux x64 fails with an error.

| Input | Required | Description |
| -------------- | -------- | ------------------------------------------------------------------------------------------------------------------ |
| `github-token` | yes | Written to nix.conf `access-tokens` to avoid GitHub API rate limits. Pass `${{ github.token }}`; the step fails if empty. |

Permissions: none beyond what the caller's job already has.

```yaml
steps:
  - uses: asakura/actions/.github/actions/setup-nix@<sha> # vX.Y.Z
    with:
      github-token: ${{ github.token }}
```

## secret-scan

Reusable workflow `.github/workflows/secret-scan.yml`.
On pull requests, `gitleaks-pr` runs gitleaks over the commits the pull request adds and prints each finding with the secret redacted.
On push, schedule and manual runs, `full-history` scans every commit of every branch and tag with gitleaks and, if `trufflehog` is true, with trufflehog, which reports only credentials it verified as live.
A scheduled run skips the scan when the default branch has had no commit for `idle-days` days.
`full-history` and `notify` run only in repositories owned by `asakura`.
All jobs run on `ubuntu-26.04`.
gitleaks is the Ubuntu archive's package; trufflehog is the release binary whose version and sha256 are pinned in the workflow.
gitleaks reads the scanned repository's `.gitleaks.toml` when it has one, so allowlisting a false positive there takes effect in both scans.

`notify` keeps at most one open issue per repository.
It finds the issue by a hidden marker in its body (`<!-- asakura-actions-secret-scan -->`), authored by `github-actions[bot]`, so renaming the issue or changing `issue-title` does not orphan it.
It runs only for the default branch, and only when there is something to write:

- When the full-history scan fails, it comments on the open issue, or creates one with `issue-title` if there is none, and closes any further open marker issues as duplicates. The text lists each finding by file, line, commit and rule, never the secret, at most 50 per scanner with the rest in the run log; or it says which scanner failed before finishing.
- When the scan passes while an issue is open, it comments on every open marker issue that the findings are gone (removed from history, allowlisted, or no longer verified by trufflehog) and closes it as completed. A real exposed secret must already have been rotated. A pass with no open issue posts nothing.
- A scheduled run skipped as idle scans nothing and never closes an issue.
- A run whose commit is no longer the head of its ref changes nothing.
- A run of any other ref, such as a manual run on a feature branch, scans but never touches issues.
- A run that cannot read the repository or its open issues from the API fails without touching issues.

Every input is required; there are no defaults.

| Input | Type | Required | Description |
| ----- | ---- | -------- | ----------- |
| `trufflehog` | boolean | yes | Whether the full-history scan also runs trufflehog (verified credentials only). |
| `idle-days` | number | yes | Skip a scheduled full-history scan when the default branch has no commit in this many days; `0` turns the check off. |
| `issue-title` | string | yes | Title of a new failure issue. |
| `timeout-minutes` | number | yes | Timeout of each job. |

Secrets: none; the workflow uses the caller's `github.token`.
Outputs: none.

Permissions the caller must grant: `contents: read` (checkout, the idle check and the head-of-ref check) and `issues: write` (`notify`; `full-history` reads issues with the same grant).
The check name to require in branch protection is `secret-scan / gitleaks-pr`.

```yaml
name: secret-scan
on:
  pull_request:
    types: [opened, synchronize, reopened]
  push:
    branches: [main]
  schedule:
    - cron: "0 6 * * 1" # weekly, Monday 06:00 UTC
  workflow_dispatch:
permissions: {}
defaults:
  run:
    shell: bash
concurrency:
  group: ${{ github.workflow }}-${{ github.head_ref || github.ref }}
  cancel-in-progress: true
jobs:
  secret-scan:
    uses: asakura/actions/.github/workflows/secret-scan.yml@<sha> # vX.Y.Z
    permissions:
      contents: read # the workflow checks out the history and lists recent commits
      issues: write # the workflow opens, comments on and closes the scan issue
    with:
      trufflehog: true
      idle-days: 7
      issue-title: Secret scan failed on the default branch history
      timeout-minutes: 30
```
