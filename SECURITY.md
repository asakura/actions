# Security policy

## Reporting a vulnerability

Report a suspected vulnerability privately, through GitHub's private
vulnerability reporting. Open the repository's Security tab, click the
"Report a vulnerability" button, or go directly to
https://github.com/asakura/actions/security/advisories/new

Do not open a public issue, pull request or discussion for a suspected
vulnerability.

Include as much of the following as you can:

- The affected workflow or action, and its version: the release tag or the
  commit SHA you use.
- The impact: what an attacker could do, and what they need in order to do it.
- Steps to reproduce the problem, such as a minimal caller workflow.

## What to expect

- The single maintainer handles reports on a best-effort basis.
- The maintainer aims to acknowledge a report within 7 days.
- A fix ships as a new patch version, with a new `vX.Y.Z` tag.
- Tags are never moved and published releases are never edited. Consumers
  must bump their SHA pin to the fixed release.
- A GitHub security advisory is published once a fix is released.

## Supported versions

Only the latest `vX.Y.Z` release receives fixes. Consumers pin a full commit
SHA of a tagged release, so they get a fix only by updating that pin.

## Scope

In scope:

- The reusable workflows under `.github/workflows/`, except those whose file
  name starts with `_`. Those are this repository's own CI. Issues about them
  are welcome too.
- The composite actions under `.github/actions/`.

Out of scope:

- Vulnerabilities in third-party tools or actions that these use. Report those
  upstream.
- Consumer repositories' own configuration.
