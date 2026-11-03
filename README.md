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

| Input | Default | Description |
| -------------- | ----------------------- | ------------------------------------------------------------------------ |
| `github-token` | `${{ github.token }}` | Written to nix.conf `access-tokens` to avoid GitHub API rate limits. |

Permissions: none beyond what the caller's job already has.

```yaml
steps:
  - uses: asakura/actions/.github/actions/setup-nix@<sha> # vX.Y.Z
```
