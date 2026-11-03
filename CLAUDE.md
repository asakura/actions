# CLAUDE.md

Guidance for Claude Code (and humans) working in `asakura/actions`: shared
reusable workflows and composite actions for `asakura/*` repositories. Follow
the rules; if a case seems to need an exception, ask instead of deciding alone.

## Workflow for changes

- One small, focused change per pull request. The owner reviews and merges;
  never merge yourself.
- Conventional Commits, lowercase subject, at most 72 characters (`feat`,
  `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `style`;
  scopes such as `lint`, `secret-scan`, `setup-nix`).
- Push over SSH (`git@github.com:asakura/actions.git`); the `gh` token has no
  `workflow` scope.
- Merge method is rebase only, and rebase rewrites SHAs. Never pin or tag a
  PR-branch SHA; pin only tagged commits on `main`.
- Changes that consumers need land here first; then open one PR per consumer
  repo that bumps the pin.

## Be explicit; never rely on defaults

Spell out every setting whose default affects behavior, even when the explicit
value equals today's default and even when that means repetition:

- triggers: `on.pull_request.types: [opened, synchronize, reopened]`,
  `push.branches`, and so on;
- `defaults.run.shell: bash`;
- `runs-on` with a fixed image series (`ubuntu-24.04`, not `ubuntu-latest`);
- `timeout-minutes` on every job;
- `concurrency.cancel-in-progress`, checkout's `fetch-depth`, artifact
  `retention-days` and `if-no-files-found`, apt's `--no-install-recommends`.

**Why:** defaults belong to someone else (GitHub, runner images, action
authors) and change without a PR in this repo. An implicit value is a design
decision nobody made or reviewed: when it shifts, every consumer silently
behaves in a way the system was not designed for, and the diff that caused it
is not ours to find. An explicit value is visible in review, greppable, and
changes only through a reviewed commit. The cost is a few repeated lines.

## Checks run at their strictest level

Every linter runs at its strictest level; `.github/workflows/_lint.yml` holds
the exact flags. Fix findings. Only a genuine false positive or an
inapplicable optional check may be disabled, individually and inline with a
reason. Never lower a level or disable a rule globally.

**Why:** a false positive costs a minute and a comment; a missed problem (an
injection, an unquoted variable, a scan that silently never runs) can stay
broken for months. A lowered level hides an unknown and growing set of
findings; an inline disable hides one known case and is visible in review.

Steps may be skipped when no relevant file changed, but findings are never
filtered by changed line, and a required check is never path-filtered at
workflow level.

**Why:** a change on one line can break another (a removed variable, a renamed
reusable-workflow input), and a required check that does not report blocks the
pull request forever.

## Scripts

- Shell logic for this repository's own workflows lives in
  `.github/scripts/*.sh`, not inline in YAML: bash, `set -euo pipefail`, and a
  header comment saying what the script takes and does.
- Exception: reusable workflows and composite actions inline their logic in
  `run:` blocks, because `./` inside them resolves to the caller's checkout,
  not this repository.

**Why:** shellcheck and shfmt only see files; actionlint and zizmor don't
analyze what a `run:` block does, so logic inline in YAML (a `curl | bash`, an
unquoted variable) passes every check unseen. Files can be run and tested
locally and diff cleanly.

## Installing tools

1. Package in the Ubuntu archive: `sudo apt-get update` then
   `sudo apt-get install -y --no-install-recommends <pkg>`, with no version or
   hash pin. Prefer the archive's version to newer upstream releases, unless a
   newer one fixes a serious (security or correctness) problem or delivers a
   feature we critically need.
2. Not in the archive: the official prebuilt release binary, verified against a
   sha256 pinned in the workflow, via `.github/scripts/install-binary.sh`.
   Cross-check the hash against the release's checksum file, digest or
   attestation when adding or bumping it.
3. Never pipe a remote script into a shell (`bash <(curl …)`, `curl | sh`),
   even if its URL is pinned to a commit.

**Why:** apt verifies a GPG-signed chain (`InRelease` → `Packages` → `.deb`),
and Ubuntu never reuses a version number, so the archive already guarantees
integrity, and security fixes reach us through updates instead of being frozen
out by a pin. The archive's version is the most exercised one; fresh releases
carry the most regressions and are where compromised releases show up. Outside
the archive, the pinned hash is the only integrity check: a commit-pinned
installer still downloads mutable release assets unverified.

### Containers

- Prefer installing a package or binary (above) to running a container.
  **Why:** an image ships a whole userland nobody here reviews (its own libc,
  shell, package manager and their unpatched libraries), it gets no security
  updates from the runner's archive, and no linter looks inside it.
- No Docker: no job-level `container:` or `services:`, no Docker container
  actions (`runs.using: docker`), no `docker` commands. Use `podman run` in a
  step. **Why:** the Docker daemon runs as root and access to its socket is
  root on the host, and containers run as root by default. Podman has no
  daemon and runs rootless, so a container escape lands in an unprivileged
  user.
- The smallest possible image: OS-less (`scratch`, distroless) rather than
  Alpine-based, pinned by digest (`image@sha256:…`), never by tag. Any other
  image (Alpine, Debian, Ubuntu, …) needs the owner's decision first; ask.
  **Why:** every extra package is attack surface, and an OS-less image has no
  shell or package manager to exploit or to carry vulnerabilities. Tags can be
  re-pointed, and zizmor checks image pins only in `container:` and
  `services:`, not inside `run:`.

## Workflow security

- zizmor (`--persona=auditor`) and the repository's `sha_pinning_required`
  enforce SHA-pinned `uses:`, `persist-credentials: false` and no `${{ … }}`
  inside `run:`. Fix their findings; don't disable them. Add a `# vX.Y.Z`
  comment to every pin.
- Least privilege: workflow-level `permissions: {}`; each job grants only what
  it uses, each grant with a comment saying why it is needed. Jobs that need
  write access are separate from jobs that run checks.
- Third-party actions only when unavoidable; prefer `gh`, `git` and small
  scripts.

**Why:** tags and branches move, and a compromised upstream must not reach us
without a reviewed pin bump. Every third-party action is code we don't review
running with the job's token, so each one widens what a single upstream
compromise can reach.

## Reusable workflow and composite action conventions

- Inputs are kebab-case. Each workflow documents its inputs, secrets, outputs
  and the exact `permissions` its caller must grant in `README.md`, with a
  copy-paste caller stub. Secrets are passed explicitly, never
  `secrets: inherit`.
- No workflow-level `concurrency` in callees (`github.workflow` resolves to the
  caller's name); callers own concurrency.
- Job ids and `name`s are public API, because they form check names
  (`secret-scan / gitleaks-pr`). Changing one is a breaking change.
- Every new reusable workflow gets a call in
  `.github/workflows/_test-workflows.yml`, with exactly the permissions its
  README documents.

## Versioning

`vX.Y.Z` tags; no moving `v1` tag. Consumers pin the full SHA. Never move,
delete or recreate a tag, and never edit a published release: a fix ships as a
new patch version. **Why:** consumers pin the commit, so a moved tag would no
longer match what they run; a tag ruleset and immutable releases reject such
changes anyway. A major bump is required
for a removed or renamed input or output, a changed job id or `name`, a new
permission the caller must grant, or a behavior-changing default.
