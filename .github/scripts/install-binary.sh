#!/usr/bin/env bash
# Install one executable from a release tarball after verifying its hash.
#
# Usage: install-binary.sh URL SHA256 MEMBER NAME [BIN_DIR]
#   URL      https URL of a .tar.gz archive.
#   SHA256   expected sha256 of the archive; a mismatch aborts.
#   MEMBER   path of the executable inside the archive.
#   NAME     file name to install it as.
#   BIN_DIR  destination directory (default: $RUNNER_TEMP/bin).
set -euo pipefail

if [[ $# -lt 4 || $# -gt 5 ]]; then
    echo "usage: $0 URL SHA256 MEMBER NAME [BIN_DIR]" >&2
    exit 2
fi

url=$1
sha256=$2
member=$3
name=$4
bin_dir=${5:-${RUNNER_TEMP:?RUNNER_TEMP or BIN_DIR is required}/bin}

work=$(mktemp -d)
trap 'rm -rf "${work}"' EXIT

curl -fsSL --proto '=https' --tlsv1.2 -o "${work}/archive.tar.gz" "${url}"
echo "${sha256}  ${work}/archive.tar.gz" | sha256sum --check --strict

mkdir "${work}/extract"
tar -xzf "${work}/archive.tar.gz" -C "${work}/extract" "${member}"
mkdir -p "${bin_dir}"
install -m 0755 "${work}/extract/${member}" "${bin_dir}/${name}"
