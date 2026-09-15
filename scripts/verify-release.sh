#!/usr/bin/env bash
# Offline check of the assembled repo/ tree, before any test and before publishing.
# It answers one question: is what we are about to serve complete, signed, and exactly what
# index.json describes? Everything is checked against our own published public keys.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

fail=0
bad() { printf 'FAIL %s\n' "$*" >&2; fail=1; }

[[ -d "$REPO" ]] || die "no repo/ to verify"
gpg_setup_public() {                     # public keyring only: no secret needed here
  GNUPGHOME="$(mktemp -d)"; export GNUPGHOME
  chmod 700 "$GNUPGHOME"
  trap 'rm -rf "$GNUPGHOME"' EXIT
  gpg --batch --quiet --import "$REPO/keys/$REPO_ID.asc" || die "cannot import our own public key"
}

# 1. No symlinks: the tree is served by Apache with FollowSymLinks.
while read -r link; do bad "symlink in the published tree: ${link#"$REPO/"}"; done < <(find "$REPO" -type l)

# 2. Keys.
for f in "keys/$REPO_ID.asc" "keys/$APK_KEY_NAME" keys/FINGERPRINTS.txt; do
  [[ -s "$REPO/$f" ]] || bad "missing $f"
done
[[ -s "$REPO/index.json" ]] || die "missing index.json (run make-index-json.sh)"
gpg_setup_public

# 3. Every package listed in index.json exists with the right SHA256…
while read -r entry; do
  file=$(jq -r .file <<<"$entry"); sha=$(jq -r .sha256 <<<"$entry")
  if [[ ! -f "$REPO/$file" ]]; then bad "index.json lists a missing file: $file"; continue; fi
  [[ "$(sha256_of "$REPO/$file")" == "$sha" ]] || bad "$file does not match its SHA256 in index.json"
done < <(jq -c '.packages[]' "$REPO/index.json")

# …and every package file on disk is listed (nothing sneaked in).
while read -r path; do
  rel="${path#"$REPO/"}"
  jq -e --arg f "$rel" 'any(.packages[]; .file == $f)' "$REPO/index.json" >/dev/null \
    || bad "file present but absent from index.json: $rel"
done < <(find "$REPO" \( -name '*.rpm' -o -name '*.apk' -o -name '*.pkg.tar.zst' -o -name '*.deb' -o -name '*.zip' \) -type f)

# 4. Repository metadata, per format, with its signature.
for dir in "$REPO"/rpm/*/; do
  [[ -d "$dir" ]] || continue
  [[ -s "$dir/repodata/repomd.xml" ]] || bad "${dir#"$REPO/"}repodata/repomd.xml missing"
  gpg --batch --verify "$dir/repodata/repomd.xml.asc" "$dir/repodata/repomd.xml" 2>/dev/null \
    || bad "${dir#"$REPO/"}repodata/repomd.xml.asc does not verify"
done
[[ -s "$REPO/rpm/$REPO_ID.repo" ]] || bad "rpm/$REPO_ID.repo missing"

for dir in "$REPO"/arch/*/; do
  [[ -d "$dir" ]] || continue
  for pkg in "$dir"*.pkg.tar.zst; do
    [[ -s "$pkg.sig" ]] || bad "${pkg#"$REPO/"} has no detached signature"
    gpg --batch --verify "$pkg.sig" "$pkg" 2>/dev/null || bad "${pkg#"$REPO/"}.sig does not verify"
  done
  [[ -s "$dir$REPO_ID.db" ]] || bad "${dir#"$REPO/"}$REPO_ID.db missing"
  gpg --batch --verify "$dir$REPO_ID.db.sig" "$dir$REPO_ID.db" 2>/dev/null \
    || bad "${dir#"$REPO/"}$REPO_ID.db.sig does not verify"
done

for dir in "$REPO"/alpine/*/; do
  [[ -d "$dir" ]] || continue
  [[ -s "$dir/APKINDEX.tar.gz" ]] || bad "${dir#"$REPO/"}APKINDEX.tar.gz missing"
  tar -tzf "$dir/APKINDEX.tar.gz" 2>/dev/null | grep -q "^\.SIGN\.RSA\.${APK_KEY_NAME}$" \
    || bad "${dir#"$REPO/"}APKINDEX.tar.gz is not signed with $APK_KEY_NAME"
done

if [[ -d "$REPO/deb/pool" ]]; then
  [[ -s "$REPO/deb/dists/stable/InRelease" ]] || bad "deb/dists/stable/InRelease missing"
  gpg --batch --verify "$REPO/deb/dists/stable/InRelease" 2>/dev/null \
    || bad "deb/dists/stable/InRelease does not verify"
fi

# 5. SHA256SUMS: signed by the pinned key, covering exactly the files of the tree.
if [[ -s "$REPO/SHA256SUMS" && -s "$REPO/SHA256SUMS.asc" ]]; then
  gpg --batch --status-fd 1 --verify "$REPO/SHA256SUMS.asc" "$REPO/SHA256SUMS" 2>/dev/null \
    | awk -v fpr="$SIGNING_KEY_FPR" '$2 == "VALIDSIG" && ($3 == fpr || $NF == fpr) {ok=1} END {exit !ok}' \
    || bad "SHA256SUMS.asc does not verify with $SIGNING_KEY_FPR"
  (cd "$REPO" && sha256sum --quiet --strict -c SHA256SUMS >/dev/null 2>&1) || bad "SHA256SUMS does not match the tree"
  extra=$(comm -13 <(cut -c67- "$REPO/SHA256SUMS" | LC_ALL=C sort) \
                   <(cd "$REPO" && find . -type f ! -name SHA256SUMS ! -name SHA256SUMS.asc -printf '%P\n' | LC_ALL=C sort))
  [[ -z "$extra" ]] || bad "files not listed in SHA256SUMS: $extra"
else
  bad "SHA256SUMS or SHA256SUMS.asc missing (run sign-manifest.sh)"
fi

# 6. Sources next to the binaries they were built from (AGPL).
while read -r v; do
  [[ -s "$REPO/source/proxmox-backup-$v.zip" ]] || bad "no source archive for upstream $v"
done < <(jq -r '[.packages[].upstream_version] | unique | .[]' "$REPO/index.json")

(( fail == 0 )) || die "release did not pass verification"
log "release verified: $(jq '.packages | length' "$REPO/index.json") files, $(jq -c .latest "$REPO/index.json")"
