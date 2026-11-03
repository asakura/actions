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
- `runs-on` with a fixed image series (`ubuntu-26.04`, not `ubuntu-latest`);
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
- GitHub's Docker-based features (`services:`, job-level `container:`) are
  fine. When a `run:` block or script has to start a container itself, prefer
  `podman run` to `docker run`. **Why:** rootless Podman runs the container as
  the runner user, so files it writes into the workspace are not root-owned
  and later steps can read and clean them up; it needs no daemon; and the same
  command stays unprivileged if a job ever moves to a self-hosted runner,
  where Docker's root daemon would expose the host.
- The smallest possible image: OS-less (`scratch`, distroless) rather than
  Alpine-based, pinned by digest (`image@sha256:…`), never by tag. Any other
  image (Alpine, Debian, Ubuntu, …) needs the owner's decision first; ask.
  **Why:** every extra package is attack surface, and an OS-less image has no
  shell or package manager to exploit or to carry vulnerabilities. Tags can be
  re-pointed, and zizmor checks image pins only in `container:` and
  `services:`, not inside `run:`. On a GitHub-hosted runner the job already
  has `sudo` and the VM is discarded afterwards, so the risk is what the image
  can do with the job's token, secrets and checkout, not the container engine.

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

## Outputs and side effects

- A step or job that produces something (a file, an artifact, an output, a
  summary) runs under exactly the condition of whatever consumes it. When
  nothing consumes it in some case, it does not run in that case; when nothing
  consumes it at all, remove it. Check this whenever an `if:` or a consumer
  changes.
- Every step and job runs only when it has work, not only those that produce
  something. A job that exists for a side effect (a comment, an issue) runs
  only when there is something to write; when that depends on outside state, a
  cheap step upstream checks it and the job's `if:` reads that output. "It
  might be needed" is not a condition.
- Before calling a workflow change done, list the cases it can meet (nothing
  relevant changed, pass, failure, pass after an earlier failure, re-run of an
  old commit, fork) and which steps and jobs run in each. Anything that runs
  with nothing to do is a bug. Fixing one such step means rechecking every
  other step and job the same way.
- Every line written to `$GITHUB_OUTPUT` is also printed to the job log;
  write it once through `tee -a "${GITHUB_OUTPUT}"` so the two cannot differ.
  This log line is the one exception to the consumer rule above: keep it.
- Anything a run writes outside itself (a PR comment, an issue, a label) is
  written for concurrent and out-of-order runs: find it by a marker, update it
  instead of adding another, close duplicates, and change nothing when the
  run's commit is no longer the head.
- Report failures only. A pass posts nothing new; it resolves the earlier
  failure report. Nothing is ever deleted: first say why it is resolved, then
  close it.
  - an issue: comment why, then close it;
  - a PR comment: edit it to say why, then minimize it as resolved (as
    duplicate for duplicates).
- Anything people read (a PR comment, an issue, a job summary, a report) is
  written for people: tool output in its human-readable form (location,
  message, source snippet), never machine formats such as workflow commands
  (`::error file=…::`), raw JSON or SARIF. Machine output (annotations) is
  produced separately and never pasted into what people read. Before calling
  such a change done, render it from a real failing case and read it.

**Why:** an `if:` is written when its step is added, and nothing re-checks it
when the consumer changes later; no linter follows the link from producer to
consumer. A step that runs with nothing to do still costs runner time, adds a
check to every pull request, and hides which steps matter; the empty case
(nothing relevant changed) is the one a change is least often tested with.
GitHub shows step outputs nowhere (not in the log, the UI or the API)
except in debug logging after a re-run, so without the log line a step that sets
a wrong output cannot be diagnosed from the run it misbehaved in. Concurrency
cancels runs only after they start, and re-running an old run bypasses it, so
the last run to write wins, not the newest commit. A success message tells
nothing the check status doesn't, and every comment is a notification. A
failure report is a record: deleting it erases what failed and when (a leaked
secret must stay traceable), and the reason written before closing tells a
later reader why it no longer applies. A report is read by whoever has to fix
the failure, often from a notification; workflow commands are syntax for the
runner, and in a comment they bury the message in markup and drop the source
context. No linter reads a rendered comment, so only looking at one catches
this.

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
