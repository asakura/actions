#!/usr/bin/env bash
# Planted hidden defaults to verify the shell defaults finding text. Do not merge.
set -euo pipefail

echo "${FOO:-bar}"
: "${BAZ:=qux}"
echo "${BAZ}"
