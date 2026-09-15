#!/usr/bin/env bash
# Build and sign APKINDEX.tar.gz for each architecture.
# Runs on Alpine <= 3.22: apk-tools 2 writes the v2 index, which apk-tools 3 (Alpine >= 3.23)
# still reads, so one index serves every supported Alpine release.
# Needs: apk-tools 2, abuild (abuild-sign), UPC_APK_KEY_FILE, repo/keys/ from export-keys.sh.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

[[ -n "${UPC_APK_KEY_FILE:-}" && -s "$UPC_APK_KEY_FILE" ]] || die "UPC_APK_KEY_FILE is not set"
pub="$REPO/keys/$APK_KEY_NAME"
[[ -s "$pub" ]] || die "missing $pub (run export-keys.sh)"
apk --version | grep -q '^apk-tools 2\.' || die "needs apk-tools 2 (Alpine <= 3.22) to write a v2 index"

# apk index verifies each package signature against /etc/apk/keys.
install -m 0644 "$pub" "/etc/apk/keys/$APK_KEY_NAME"

for dir in "$REPO"/alpine/*/; do
  (
    cd "$dir" || exit 1
    rm -f APKINDEX.tar.gz
    apk index --quiet -o APKINDEX.tar.gz -d "$REPO_ID $(date -u +%Y-%m-%d)" ./*.apk
    abuild-sign -q -k "$UPC_APK_KEY_FILE" -p "$APK_KEY_NAME" APKINDEX.tar.gz
  )
  log "signed ${dir#"$REPO/"}APKINDEX.tar.gz"
done
