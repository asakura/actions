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
- Every amend updates everything that describes the change: the commit
  message, the PR body and the code comments it touches.
- A fix applies a rule, not an instance. Before opening it, `git grep` the
  whole repository for the pattern and fix every match of that one rule in
  that PR, or list each one left with the reason. Problems with other rules
  found on the way go to their own PRs. Instances named in a request are where
  to start, not the scope.
- Editing a file means checking the whole file against this CLAUDE.md, not only
  your hunk; code near your change is not a template. Fix what you find in a
  separate PR, or list it in the PR body.
- A violation of a rule here is a bug, not an optional cleanup.

**Why:** the fix that made `LINT_DIR` and `MAX_OUTPUT_CHARS` required in
`lint-report.sh` left 10 matches of the same violation in that file, two of
them copied in from the surrounding lines after the rule existed.

## Pull request scope

- A pull request is one change: its title names it without "and", and
  every commit serves it. Check this before every push to an open pull
  request, not only when opening it.
- A commit that makes the pull request's change correct (a bug in the code
  it adds, a review comment about that code) goes into it as a new commit.
  Anything else, including a bug found in code the pull request doesn't
  change or an extension a review suggested, is a new pull request,
  stacked on the open one when it depends on it. The owner asking to add
  something to an open pull request covers that one change.
- A change that replaces what an unmerged commit introduced (a format, an
  input, a message) means the design was not settled. Stop and ask the
  owner how to go on before writing it.
- Before building a new format that checked files will contain, run every
  check that reads those files on an example, the way CI runs it.
- A proposal names what it relies on (a tool's behavior, a setting) and
  where that was checked.
- A stack is one branch per part, each based on the previous one, each body
  starting "Part N of M" with links to its neighbours. After a part merges,
  the next one needs a rebase onto `main` and a force-push, which the owner
  chooses each time.

**Why:** the owner reviews every line, and review gets harder with every
unrelated change mixed in. A mixed pull request can't be approved in part:
one objection blocks everything else in it. Reviewing a design that a
later commit replaces is wasted work. Pull requests grow through follow-up
pushes, so a check done only when opening one misses that. A check run
differently from CI (offline instead of online, other flags) can pass what
CI fails. The owner decides on the reasons a proposal gives, so an
unchecked premise leads to a wrong decision.

## Before removing a safeguard

You may be wrong: about what a rule means, about what a request refers to, or
about the code it applies to. Feeling sure is not a sign you are right, so
check this every time, not only when you feel unsure.

A safeguard is anything on `main` or in the repository's settings that
protects or records: a test, check or verification step, a rule in this file,
a ruleset or setting, a comment or issue. Ordinary code changes and your own
unmerged work are not covered.

Remove or weaken a safeguard only when the owner's request names exactly what
goes ("delete `tests/`"); otherwise ask first. None of these names it:

- your reading of a rule;
- the owner approving a proposal of yours: that is not a request for
  everything your reading of it implies, so name what will be removed and get
  a yes to that;
- a request whose readings differ in what gets removed ("fix that").

Even when it is named, if you find that the change's premise doesn't hold,
stop and ask. Don't ship the change with the problem listed as a follow-up.

The PR body says what the safeguard protected and what protects that
afterwards, so the owner can check both.

A subagent can't ask the owner: when it would have to ask, it stops and
reports back instead.

Rules have exceptions, and the owner decides them. A new rule says where code
should go; existing code that doesn't meet it yet is not a reason to remove
anything.

**Why:** rules here are short, and the owner's intent behind them includes
exceptions nobody wrote down. A removal is only right if your reading of the
rule, the request and the code are all right at once, and a wrong one takes
away protection where the code is hardest to get right. A question costs one
message; a confident wrong change costs a review, a revert and trust.

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

A script must be simple enough that it needs no tests: reading it once shows
that it works, and running it shows whether it does. When it isn't, simplify
it or cut the feature that makes it hard to follow. In practice:

- one concern per script;
- no hand-written parser when a standard tool (`jq`, `gh --jq`, `git`) can
  produce the data;
- no global variables used as a function's return value;
- no long positional argument lists: a script takes its inputs as named
  environment variables, and structured data as JSON read with `jq`;
- every input the caller passes is required (`: "${NAME:?…}"`), with no
  hidden default. Variables GitHub sets (`RUNNER_TEMP`, `GITHUB_OUTPUT`,
  `GITHUB_REPOSITORY`, …) are not inputs. This covers every way to write a
  default: `${NAME:-x}`, `${NAME-x}`, `${NAME:=x}`, `${NAME=x}`, an input
  documented as "optional", and, in test fixtures, a jq `// value` that fills
  in a field the fixture didn't state. jq's `//` stays only where absence is
  part of the data (a format or API that omits a field, an empty array, or an
  error message reporting the missing field), with a comment saying so.
  `git grep -nE '\$\{[A-Za-z_]+:?[-=]' .github` returns nothing, and the
  `shell defaults` lint step enforces it.

**Why:** the owner reviews every line that runs with this repository's token.
A script that takes an hour to follow gets approved unread, and code nobody
read is where bugs and injections hide. Tests don't fix that: they are more
code to review, and they only prove the script against what we assumed.

## Adding a check

A new check on this repository is a step of the `lint` job in `_lint.yml`, not
a job of its own: gated by an output of `changed-files.sh`, its human-readable
output saved for `lint-report.sh`, and a row in the lint report.

**Why:** a step shares the lint job's checkout and change detection, its
failure reaches the lint report people read, and `lint` is already the
required check. A separate job costs a runner and a checkout, needs its own
gate, and fails somewhere the report never mentions.

## Verifying GitHub behavior

Behavior that depends on GitHub (API fields, how review threads, comments and
checks behave) is verified on a draft "do not merge" pull request, case by
case, then closed with a comment saying what it showed.

**Why:** GitHub's behavior is undocumented in places: a review thread whose
lines only move stays current, and a one-line thread reports its `startLine`
as its line, not null. Both broke code that looked right on review.

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
