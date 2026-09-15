#!/usr/bin/env bash
# repo/SHA256SUMS: the checksum of every file of the release, with a detached OpenPGP signature.
# It is the single root of trust for the web host (server/pull-packages.sh): the tree travels
# through GitHub, the host believes only this signature, checked against a key it keeps itself.
# Run after make-index-json.sh, before verify-release.sh.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

[[ -s "$REPO/index.json" ]] || die "missing index.json (run make-index-json.sh)"
gpg_setup
[[ "$GPG_KEY_FPR" == "$SIGNING_KEY_FPR" ]] || die "signing key $GPG_KEY_FPR is not SIGNING_KEY_FPR ($SIGNING_KEY_FPR)"

rm -f "$REPO/SHA256SUMS" "$REPO/SHA256SUMS.asc"
(
  cd "$REPO"
  find . -type f -printf '%P\n' | LC_ALL=C sort | while IFS= read -r f; do
    [[ "$f" =~ ^[A-Za-z0-9._+/-]+$ && "$f" != *..* && "$f" != .* && "$f" != */.* ]] \
      || die "file name not allowed in a release: $f"
    sha256sum -- "$f"
  done
) > "$BUILD/SHA256SUMS"
mv "$BUILD/SHA256SUMS" "$REPO/SHA256SUMS"
"${GPG_SIGN[@]}" --armor --detach-sign --output "$REPO/SHA256SUMS.asc" "$REPO/SHA256SUMS"
log "SHA256SUMS: $(wc -l < "$REPO/SHA256SUMS") files, signed by $GPG_KEY_FPR"
