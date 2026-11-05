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
#    "version": "vX.Y.Z" when that comment is exactly "# vX.Y.Z", else null,
#    "exception": true when that comment is exactly
#      "# <ref> # pin-comment: no vX.Y.Z tag upstream" (one <ref> token without
#      spaces or "#": the upstream tag or branch the commit was taken from),
#      else false,
#    "ref": what the pin follows upstream: the version of a "# vX.Y.Z" pin, the
#      <ref> of an exception, else null}
# "version" is only ever a vX.Y.Z tag, so it is null for an exception; callers
# that compare pins across commits use "ref", which both kinds have. Whether
# an exception is allowed (no vX.Y.Z tag points at the commit) is not decided
# here; check-pin-comments.sh asks upstream.
set -euo pipefail

jq -nRc '
    [inputs] | to_entries[]
    | .key as $index | .value as $text
    | ($text | capture("^(?<prefix>[ \\t]*(- +)?uses:[ \\t]+[\"\u0027]?(?<action>[A-Za-z0-9_-][A-Za-z0-9_.-]*/[A-Za-z0-9_.-]+(/[^\\s@#\"\u0027]+)?)@(?<sha>[0-9a-f]{40})[\"\u0027]?)(?<rest>\\s.*)?$"))
    # rest, the optional group after the SHA, is null when nothing follows it.
    | (.rest // "") as $rest
    | first(($rest | capture("^ # (?<version>v[0-9]+\\.[0-9]+\\.[0-9]+)$").version), null) as $version
    | first(($rest | capture("^ # (?<ref>[^\\s#]+) # pin-comment: no vX\\.Y\\.Z tag upstream$").ref), null) as $exempt
    | {line: ($index + 1), action, sha, prefix, text: $text,
       comment: ($rest | sub("^\\s+"; "")),
       version: $version,
       exception: ($exempt != null),
       ref: (if $version != null then $version else $exempt end)}'
