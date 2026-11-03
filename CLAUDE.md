# CLAUDE.md

Guidance for Claude Code (and humans) working in `asakura/actions`: shared
reusable workflows and composite actions for `asakura/*` repositories. Every
rule below has a **Why**. Follow the rule; if a case seems to need an exception,
ask instead of deciding alone.

## Workflow for changes

- One small, focused change per pull request. The owner reviews and merges;
  never merge yourself.
- Conventional Commits, lowercase subject, at most 72 characters (`feat`,
  `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore`, `style`;
  scopes such as `lint`, `secret-scan`, `setup-nix`).
- Push over SSH (`git@github.com:asakura/actions.git`). The `gh` token lacks
  the `workflow` scope on purpose; don't widen it or use the contents API to
  write workflow files.
- Merge method is rebase only, and rebase rewrites SHAs. Never pin or tag a
  PR-branch SHA; pin only tagged commits on `main`.
- Changes that consumers need land here first; then open one PR per consumer
  repo that bumps the pin.

## Be explicit; never rely on defaults

Spell out every setting whose default affects behavior, even when the explicit
value equals today's default and even when that means repetition:

- triggers: `on.pull_request.types: [opened, synchronize, reopened]`,
  `push.branches`, and so on;
- `permissions:` at workflow level (`{}`) and per job, each with a comment
  saying why it is needed;
- `defaults.run.shell: bash` (GitHub's implicit shell is `bash -e {0}`; an
  explicit `bash` adds `--noprofile --norc -o pipefail`);
- `runs-on` with a fixed image series (`ubuntu-24.04`, not `ubuntu-latest`);
- `timeout-minutes` on every job (the implicit default is 360);
- `concurrency.cancel-in-progress`, checkout's `persist-credentials` and
  `fetch-depth`, artifact `retention-days` and `if-no-files-found`, apt's
  `--no-install-recommends`.

**Why:** defaults belong to someone else and change without a PR in this repo
(GitHub has changed default token permissions, runner images and action
defaults before). An implicit value is a design decision nobody made or
reviewed: when it shifts, every consumer silently behaves in a way the system
was not designed for, and the diff that caused it is not ours to find. An
explicit value is visible in review, greppable, and changes only through a
reviewed commit. The cost is a few repeated lines.

## Checks run at their strictest level

| Tool | Flags |
|---|---|
| actionlint | default rules, `SHELLCHECK_OPTS='--enable=all --severity=style'` for `run:` blocks |
| zizmor | `--persona=auditor` (strictest; replaces `--pedantic`) |
| shellcheck | `--enable=all --severity=style` |
| shfmt | `--simplify --diff --indent 4 --case-indent` |

Fix findings. Only a genuine false positive or an inapplicable optional check
may be disabled, individually and inline with a reason
(`# shellcheck disable=SC1234 # reason`, `# zizmor: ignore[rule] -- reason`).
Never lower a level or disable a rule globally.

**Why:** a false positive costs a minute and a comment; a missed problem (an
injection, an unquoted variable, a scan that silently never runs) can stay
broken for months. A lowered level hides an unknown and growing set of
findings; an inline disable hides one known case and is visible in review.
Starting clean at the strictest level keeps it cheap to stay clean.

The `lint` job filters which tools run by changed files, but never filters
findings by changed line: a change on one line can break another (a removed
variable, a renamed reusable-workflow input). A required check is never
path-filtered at workflow level, because a check that does not report blocks
the pull request forever.

## Scripts

- Shell logic for this repository's own workflows lives in
  `.github/scripts/*.sh`, not inline in YAML: bash, `set -euo pipefail`, and a
  header comment saying what the script takes and does. The `lint` job checks
  them with shellcheck and shfmt.
- Exception: reusable workflows and composite actions inline their logic in
  `run:` blocks, because `./` inside them resolves to the caller's checkout,
  not this repository.
- Bash, not nushell.

**Why:** shellcheck and shfmt only see files; actionlint and zizmor don't
analyze what a `run:` block does, which is how a `curl | bash` slipped through
once. Files can be run and tested locally and diff cleanly. Bash because
shellcheck is mature at `--enable=all` while nushell's linters and formatters
are young; nushell is not in the Ubuntu archive or on runner images (every
consumer job would download it, and actionlint cannot check `shell: nu`
blocks); its pre-1.0 minor releases break scripts; and the tool bootstrap has
to be bash anyway.

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
   even if its URL is pinned to a commit. Never use actions that pull a Docker
   image by tag.

**Why:** apt verifies a GPG-signed chain (`InRelease` → `Packages` → `.deb`),
and Ubuntu never reuses a version number, so the archive already guarantees
integrity, and security fixes reach us through updates instead of being frozen
out by a pin. The archive's version is the most exercised one; fresh releases
carry the most regressions and are where compromised releases show up. Outside
the archive, the pinned hash is the only integrity check: a commit-pinned
installer still downloads mutable release assets unverified, and Docker tags
can be re-pointed.

## Workflow security

- Every `uses:` is pinned to a full 40-character commit SHA with a
  `# vX.Y.Z` comment; the repository enforces `sha_pinning_required`.
- `actions/checkout` always with `persist-credentials: false`.
- Never interpolate `${{ … }}` inside `run:`; pass values through `env:`.
- Least privilege: workflow-level `permissions: {}`; each job grants only what
  it uses. Jobs that need write access are separate from jobs that run checks.
- Third-party actions only when unavoidable; prefer `gh`, `git` and small
  scripts (`tj-actions/changed-files` was compromised in March 2025).

**Why:** tags and branches move, and a compromised upstream must not reach us
without a reviewed pin bump. Persisted credentials and template injection are
the two most common ways a workflow leaks its token.

## Reusable workflow and composite action conventions

- Inputs are kebab-case. Each workflow documents its inputs, secrets, outputs
  and the exact `permissions` its caller must grant in `README.md`, with a
  copy-paste caller stub. Secrets are passed explicitly, never
  `secrets: inherit`.
- No workflow-level `concurrency` in callees (`github.workflow` resolves to the
  caller's name); callers own concurrency.
- Job ids and `name`s are public API, because they form check names
  (`secret-scan / gitleaks-pr`). Changing one is a breaking change.
- The only internal cross-reference is
  `uses: asakura/actions/setup-nix@<sha> # vX.Y.Z`, pinned to a tagged `main`
  commit.
- `.github/workflows/_test-workflows.yml` calls each reusable workflow with
  exactly the permissions its README documents.

## Versioning

Immutable `vX.Y.Z` tags (protected by a tag ruleset, with immutable releases
on); no moving `v1` tag. Consumers pin the full SHA. A major bump is required
for a removed or renamed input or output, a changed job id or `name`, a new
permission the caller must grant, or a behavior-changing default.
