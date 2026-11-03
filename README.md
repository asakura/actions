# asakura/actions

Reusable GitHub Actions workflows and composite actions shared by `asakura/*` repositories.

Consumers pin a full commit SHA of a tagged release (`uses: asakura/actions/.github/workflows/<name>.yml@<sha> # vX.Y.Z`).
Tags are immutable; there is no moving `v1` tag.

Units are added incrementally; see each unit's section below once it lands.
