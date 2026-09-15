# shellcheck shell=bash
# Common helpers, sourced by every script.
# shellcheck disable=SC2034  # variables defined here are used by the calling scripts
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.env
. "$ROOT/config.env"

BUILD="$ROOT/build"   # scratch area (upstream metadata, extracted trees, manifests)
REPO="$ROOT/repo"     # the tree that ends up under $PUBLIC_BASE_URL

log() { printf '>> %s\n' "$*" >&2; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

# Debian arch -> the name used by rpm, pacman and apk.
linux_arch() {
  case "$1" in
    amd64) echo x86_64 ;;
    arm64) echo aarch64 ;;
    *) die "unsupported architecture: $1" ;;
  esac
}

# "4.2.5-1" -> UP_VER=4.2.5 UP_REV=1
split_version() {
  UP_VER="${1%-*}"
  UP_REV="${1##*-}"
  [[ "$UP_VER" != "$1" && "$UP_REV" =~ ^[0-9]+$ ]] || die "unexpected upstream version: $1"
}

sha256_of() { sha256sum "$1" | cut -d' ' -f1; }

# Download to a file, failing loudly (no partial files left behind).
fetch() {
  local url="$1" out="$2"
  curl -fsSL --retry 3 --retry-delay 5 -o "$out.part" "$url" || { rm -f "$out.part"; die "download failed: $url"; }
  mv "$out.part" "$out"
}

# Signing keys live in ../secrets/ of the private GitLab project (outside public/) (decision of 2026-09-15); an
# explicit environment variable still wins, for local runs with other keys.
: "${UPC_GPG_KEY_FILE:=$ROOT/../secrets/signing-key.asc}"
: "${UPC_APK_KEY_FILE:=$ROOT/../secrets/apk-signing.rsa}"
export UPC_GPG_KEY_FILE UPC_APK_KEY_FILE

# Import the signing key (UPC_GPG_KEY_FILE, passphrase in UPC_GPG_PASSPHRASE if any) into a
# throwaway GNUPGHOME. Sets GPG_KEY_FPR and the GPG_SIGN array for non-interactive signing.
gpg_setup() {
  [[ -n "${UPC_GPG_KEY_FILE:-}" && -s "$UPC_GPG_KEY_FILE" ]] || die "UPC_GPG_KEY_FILE is not set"
  GNUPGHOME="$(mktemp -d)"; export GNUPGHOME
  chmod 700 "$GNUPGHOME"
  # Le trousseau temporaire contient la clé privée : il part avec le script, meme en cas d'echec.
  trap 'rm -rf "$GNUPGHOME"' EXIT
  local err
  err=$(gpg --batch --quiet --import "$UPC_GPG_KEY_FILE" 2>&1) || die "cannot import UPC_GPG_KEY_FILE: $err"
  GPG_KEY_FPR=$(gpg --batch --with-colons --list-secret-keys | awk -F: '/^fpr:/{print $10; exit}')
  [[ -n "$GPG_KEY_FPR" ]] || die "no secret key in UPC_GPG_KEY_FILE"
  GPG_SIGN=(gpg --batch --yes --local-user "$GPG_KEY_FPR" --pinentry-mode loopback --passphrase "${UPC_GPG_PASSPHRASE:-}")
}

# Per-architecture upstream facts written by check-upstream.sh, e.g. upstream_get amd64 VERSION
upstream_get() {
  local arch="$1" key="$2" var
  # shellcheck source=/dev/null
  . "$BUILD/upstream.env"
  var="${key}_${arch}"
  printf '%s' "${!var:-}"
}
