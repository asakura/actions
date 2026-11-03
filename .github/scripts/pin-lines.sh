#!/usr/bin/env bash
# List the SHA-pinned "uses:" lines of one workflow or action file.
#
# Usage: pin-lines.sh < FILE
# Prints one JSON object per line of the form "uses: owner/repo[/path]@<40
# lowercase hex>" (a quoted value and a "- " list marker are fine); other refs,
# local "./" paths and "docker://" images are not pins and print nothing:
#   {"line": N, "action": "owner/repo[/path]", "sha": "...",
#    "prefix": the line up to and including the SHA (and a closing quote),
#    "text": the whole line,
#    "comment": what follows the prefix, without leading whitespace,
#    "version": "vX.Y.Z" when that comment is exactly "# vX.Y.Z", else null}
set -euo pipefail

jq -nRc '
    [inputs] | to_entries[]
    | .key as $index | .value as $text
    | ($text | capture("^(?<prefix>[ \\t]*(- +)?uses:[ \\t]+[\"\u0027]?(?<action>[A-Za-z0-9_-][A-Za-z0-9_.-]*/[A-Za-z0-9_.-]+(/[^\\s@#\"\u0027]+)?)@(?<sha>[0-9a-f]{40})[\"\u0027]?)(?<rest>\\s.*)?$"))
    | (.rest // "") as $rest
    | {line: ($index + 1), action, sha, prefix, text: $text,
       comment: ($rest | sub("^\\s+"; "")),
       version: first(($rest | capture("^ # (?<version>v[0-9]+\\.[0-9]+\\.[0-9]+)$").version), null)}'
