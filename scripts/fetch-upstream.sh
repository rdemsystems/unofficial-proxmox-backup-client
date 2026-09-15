#!/usr/bin/env bash
# Download each upstream .deb named by check-upstream.sh, verify it against the signed
# Packages index (SHA256 + size), keep it verbatim for the deb mirror, and extract it.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

[[ -s "$BUILD/upstream.env" ]] || die "run check-upstream.sh first"
mkdir -p "$BUILD/debs" "$REPO/deb/pool/main"

for pair in $UPSTREAM_ARCHES; do
  arch="${pair%%:*}"
  filename=$(upstream_get "$arch" FILENAME)
  sha=$(upstream_get "$arch" SHA256)
  size=$(upstream_get "$arch" SIZE)
  deb="$BUILD/debs/$(basename "$filename")"

  fetch "$UPSTREAM_BASE/$filename" "$deb"
  [[ "$(sha256_of "$deb")" == "$sha" ]] || die "$(basename "$deb"): SHA256 differs from the signed index"
  [[ "$(stat -c %s "$deb")" == "$size" ]] || die "$(basename "$deb"): size differs from the signed index"
  log "$(basename "$deb") verified ($sha)"

  # The deb mirror (Debian/Ubuntu) serves the upstream file byte for byte.
  cp "$deb" "$REPO/deb/pool/main/"

  root="$BUILD/root-$arch"
  rm -rf "$root" && mkdir -p "$root"
  dpkg-deb -x "$deb" "$root"
  for bin in proxmox-backup-client pxar; do
    [[ -x "$root/usr/bin/$bin" ]] || die "$bin missing from $(basename "$deb")"
  done
done
