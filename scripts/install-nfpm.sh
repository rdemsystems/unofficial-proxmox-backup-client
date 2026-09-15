#!/usr/bin/env bash
# Install a pinned nfpm release, checked against its published SHA256 (CI images only).
set -euo pipefail
NFPM_VERSION="2.47.0"
NFPM_SHA256="0660ca602b2d2d2ae4781a06c692b3eeb9d437ffea05b831d76e41f4a3188783"   # nfpm_2.47.0_Linux_x86_64.tar.gz
dest="${1:-/usr/local/bin}"
tmp=$(mktemp -d)
curl -fsSL -o "$tmp/nfpm.tgz" "https://github.com/goreleaser/nfpm/releases/download/v${NFPM_VERSION}/nfpm_${NFPM_VERSION}_Linux_x86_64.tar.gz"
echo "$NFPM_SHA256  $tmp/nfpm.tgz" | sha256sum -c --quiet
tar -xzf "$tmp/nfpm.tgz" -C "$tmp" nfpm
install -m 0755 "$tmp/nfpm" "$dest/nfpm"
rm -rf "$tmp"
nfpm --version | grep -m1 GitVersion
