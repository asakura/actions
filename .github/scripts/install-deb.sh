#!/usr/bin/env bash
# Install one binary from an Ubuntu .deb without root, after verifying its hash.
#
# Usage: install-deb.sh PACKAGE VERSION SHA256 [BIN_DIR]
#   PACKAGE  Ubuntu package name; its /usr/bin/PACKAGE is installed.
#   VERSION  exact package version, as in `apt-get download PACKAGE=VERSION`.
#   SHA256   expected sha256 of the downloaded .deb; a mismatch aborts.
#   BIN_DIR  destination directory (default: $RUNNER_TEMP/bin).
set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
    echo "usage: $0 PACKAGE VERSION SHA256 [BIN_DIR]" >&2
    exit 2
fi

package=$1
version=$2
sha256=$3
bin_dir=${4:-${RUNNER_TEMP:?RUNNER_TEMP or BIN_DIR is required}/bin}

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

(cd "$work" && apt-get download "${package}=${version}")
deb=("$work"/*.deb)
echo "${sha256}  ${deb[0]}" | sha256sum --check --strict

dpkg -x "${deb[0]}" "$work/root"
mkdir -p "$bin_dir"
install -m 0755 "$work/root/usr/bin/${package}" "$bin_dir/${package}"
