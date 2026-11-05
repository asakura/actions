# asakura/actions

Reusable GitHub Actions workflows and composite actions shared by `asakura/*` repositories.

Consumers pin a full commit SHA of a tagged release (`uses: asakura/actions/.github/workflows/<name>.yml@<sha> # vX.Y.Z`).
Tags are immutable; there is no moving `v1` tag.

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
On pull requests it runs gitleaks over the commits the PR adds (`gitleaks-pr`).
On push, schedule and manual runs it scans the full history with gitleaks and, optionally, trufflehog (`full-history`), skipping scheduled runs when the default branch has been idle.
The default branch is looked up at runtime.
`full-history` and `notify` run only in repositories owned by `asakura` (`full-history` is skipped elsewhere, and `notify` needs it).
All jobs run on `ubuntu-26.04`; Nix comes from the `setup-nix` action pinned at v1.0.0.

`notify` keeps at most one open issue per repository.
It finds the issue by a hidden marker in its body (`<!-- asakura-actions-secret-scan -->`), authored by `github-actions[bot]`, so renaming the issue or changing `issue-title` does not orphan it.
It runs only for the default branch, and only when there is something to write:

- When the full-history scan fails, it comments on the open issue, or creates one with `issue-title` if there is none. Any further open marker issues are closed as duplicates.
- When a full scan passes and an open marker issue exists, it comments on every open marker issue, explaining that the finding is gone (removed from history, allowlisted, or no longer verified by trufflehog), and closes it as completed. A real exposed secret must already have been rotated. A pass with no open issue posts nothing.
- Scheduled runs skipped as idle never close an issue, because nothing was scanned. A run whose commit is no longer the head of its ref changes nothing.
- Runs of any other ref, such as a manual run on a feature branch, still scan but never touch issues.

Every input is required; there are no defaults.

| Input | Type | Required | Description |
| ----- | ---- | -------- | ----------- |
| `tool-source` | string | yes | `pinned`: tools from nixpkgs at `nixpkgs-rev`. `flake`: the caller's flake via `--inputs-from .`. Any other value fails the scan. |
| `nixpkgs-rev` | string | yes | Nixpkgs commit used when `tool-source` is `pinned`; unused when it is `flake`. |
| `trufflehog` | boolean | yes | Whether to also run trufflehog (verified only) in the full-history scan. |
| `idle-days` | number | yes | Skip the scheduled full-history scan if the default branch has no commit in this many days; `0` turns the check off. |
| `issue-title` | string | yes | Title of a new failure issue. |
| `timeout-minutes` | number | yes | Timeout of each job. |

Secrets: none; the workflow uses the caller's `github.token`.
Outputs: none.

Permissions the caller must grant: `contents: read` (checkout and head-of-ref check) and `issues: write` (`notify`; `full-history` reads issues with the same grant).
The check name to require in branch protection is `secret-scan / gitleaks-pr`.

```yaml
name: secret-scan
on:
  pull_request:
    types: [opened, synchronize, reopened]
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
      contents: read # the workflow checks out the repository history
      issues: write # the workflow opens, comments on and closes the scan issue
    with:
      tool-source: pinned
      nixpkgs-rev: 0bb2eedc20e4739f29e8045034f2828ad7054f8f
      trufflehog: true
      idle-days: 7
      issue-title: Secret scan failed on the default branch history
      timeout-minutes: 30
```
