#!/usr/bin/env bash
# List the SHA-pinned "uses:" lines of one workflow or action file, and the
# pin-comment marker lines that do not belong to one.
#
# Usage: pin-lines.sh < FILE
# Prints one JSON object per line of the form "uses: owner/repo[/path]@<40
# lowercase hex>" (a quoted value and a "- " list marker are fine); other refs,
# local "./" paths and "docker://" images are not pins and print nothing:
#   {"kind": "pin", "line": N, "action": "owner/repo[/path]", "sha": "...",
#    "prefix": the line up to and including the SHA (and a closing quote),
#    "indent": the whitespace the line starts with,
#    "text": the whole line,
#    "comment": what follows the prefix, without leading whitespace,
#    "version": "vX.Y.Z" when that comment is exactly "# vX.Y.Z", else null,
#    "marker": true when the line directly above is exactly the indent of this
#      line followed by "# pin-comment: no vX.Y.Z tag upstream",
#    "exception": true when "marker" is true and the comment is exactly
#      "# <ref>" (one <ref> token without spaces or "#", the upstream tag or
#      branch the commit was taken from) and <ref> is no vX.Y.Z, else false,
#    "ref": what the pin follows upstream: the version of a "# vX.Y.Z" pin, the
#      <ref> of an exception, else null,
#    "inline": true when the line itself holds "# pin-comment:" (the old form,
#      which is an error),
#    "inline_ref": the <ref> of "# <ref> # pin-comment: no vX.Y.Z tag upstream"
#      at the end of the line, else null}
# "version" is only ever a vX.Y.Z tag, so it is null for an exception; callers
# that compare pins across commits use "ref", which both kinds have. A marker
# never makes a "# vX.Y.Z" pin an exception, so it cannot excuse a changed
# commit of one. Whether an exception is allowed (no vX.Y.Z tag points at the
# commit) is not decided here; check-pin-comments.sh asks upstream.
# A line that starts with "# pin-comment:" and is not the marker of the pin
# right below it prints
#   {"kind": "stray", "line": N, "text": "...", "indent": the whitespace it
#    starts with, "reason": "text" (it is not exactly the marker text),
#    "target" (the next line is no pin) or "indent" (its indentation differs
#    from the pin below), "expected": the indentation width of the pin below,
#    null when the next line is no pin}
set -euo pipefail

jq -nRc '
    def marker: "# pin-comment: no vX.Y.Z tag upstream";
    def pin: capture("^(?<prefix>(?<indent>[ \\t]*)(- +)?uses:[ \\t]+[\"\u0027]?(?<action>[A-Za-z0-9_-][A-Za-z0-9_.-]*/[A-Za-z0-9_.-]+(/[^\\s@#\"\u0027]+)?)@(?<sha>[0-9a-f]{40})[\"\u0027]?)(?<rest>\\s.*)?$");
    [inputs] as $lines
    | range(0; $lines | length) as $i
    | $lines[$i] as $text
    | (
        ($text | pin)
        # rest, the optional group after the SHA, is null when nothing follows it.
        | (.rest // "") as $rest
        | ($i > 0 and $lines[$i - 1] == .indent + marker) as $marked
        | first(($rest | capture("^ # (?<version>v[0-9]+\\.[0-9]+\\.[0-9]+)$").version), null) as $version
        | first(($rest | capture("^ # (?<ref>[^\\s#]+)$").ref), null) as $token
        | ($marked and $token != null and ($token | test("^v[0-9]+\\.[0-9]+\\.[0-9]+$") | not)) as $exception
        | {kind: "pin", line: ($i + 1), action, sha, prefix, indent, text: $text,
           comment: ($rest | sub("^\\s+"; "")),
           version: $version,
           marker: $marked,
           exception: $exception,
           ref: (if $version != null then $version elif $exception then $token else null end),
           inline: ($rest | test("#\\s*pin-comment:")),
           inline_ref: first(($rest | capture("^ # (?<ref>[^\\s#]+) # pin-comment: no vX\\.Y\\.Z tag upstream$").ref), null)}
      ),
      (
        select($text | test("^[ \\t]*# pin-comment:"))
        | ($text | capture("^(?<indent>[ \\t]*)").indent) as $indent
        # Past the last line there is no next line; that is no pin either.
        | first(($lines[$i + 1] // "" | pin), null) as $below
        | select($below == null or $text != $below.indent + marker)
        | {kind: "stray", line: ($i + 1), text: $text, indent: $indent,
           reason: (if $text != $indent + marker then "text" elif $below == null then "target" else "indent" end),
           expected: (if $below != null then ($below.indent | length) else null end)}
      )'
