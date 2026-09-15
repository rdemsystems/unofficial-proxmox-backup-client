#!/usr/bin/env bash
# Publish the public halves of the signing keys under repo/keys/.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

[[ -n "${UPC_APK_KEY_FILE:-}" && -s "$UPC_APK_KEY_FILE" ]] || die "UPC_APK_KEY_FILE is not set"
gpg_setup
mkdir -p "$REPO/keys"

gpg --batch --armor --export "$GPG_KEY_FPR" > "$REPO/keys/$REPO_ID.asc"
openssl rsa -in "$UPC_APK_KEY_FILE" -passin "pass:${NFPM_APK_PASSPHRASE:-}" -pubout \
  -out "$REPO/keys/$APK_KEY_NAME" 2>/dev/null || die "cannot derive the APK public key"
{
  echo "OpenPGP (RPM, pacman, deb): $GPG_KEY_FPR"
  echo "APK (RSA, /etc/apk/keys/$APK_KEY_NAME): sha256 $(sha256_of "$REPO/keys/$APK_KEY_NAME")"
} > "$REPO/keys/FINGERPRINTS.txt"
log "public keys exported (OpenPGP $GPG_KEY_FPR)"
