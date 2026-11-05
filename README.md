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
The same action and `<ref>` must keep the same commit, just like a version.
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
