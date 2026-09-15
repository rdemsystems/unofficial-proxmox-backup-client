#!/usr/bin/env bash
# Local end-to-end check of scripts/publish.sh + server/pull-packages.sh, without GitHub or a
# web host: a bare repository stands for GitHub, a throwaway key signs a small fake tree.
#   tests/packages-roundtrip.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export GNUPGHOME="$work/gnupg"
mkdir -m 700 "$GNUPGHOME"
fail() { echo "FAIL: $*" >&2; exit 1; }

gpg --batch --quiet --passphrase '' --quick-gen-key "Roundtrip test <test@example.invalid>" ed25519 sign 1d
fpr=$(gpg --batch --with-colons --list-keys | awk -F: '/^fpr:/{print $10; exit}')
gpg --batch --export "$fpr" > "$work/trusted.gpg"
git init -q --bare "$work/github.git"
mkdir -p "$work/srv"
cp "$work/trusted.gpg" "$work/srv/trusted.gpg"

# A release tree: the few files publish.sh insists on, a package, a signed SHA256SUMS.
make_tree() {                     # $1 = generated date, $2 = package content
  local t="$work/repo"
  rm -rf "$t"; mkdir -p "$t/keys" "$t/deb/pool"
  . "$ROOT/config.env"
  echo key > "$t/keys/$REPO_ID.asc"; echo key > "$t/keys/$APK_KEY_NAME"; echo fp > "$t/keys/FINGERPRINTS.txt"
  echo "$2" > "$t/deb/pool/pkg.deb"
  jq -n --arg g "$1" '{generated: $g, latest: {amd64: "0"}}' > "$t/index.json"
  (cd "$t" && find . -type f -printf '%P\n' | LC_ALL=C sort | xargs -d '\n' sha256sum) > "$work/SHA256SUMS"
  mv "$work/SHA256SUMS" "$t/SHA256SUMS"
  gpg --batch --yes --local-user "$fpr" --armor --detach-sign --output "$t/SHA256SUMS.asc" "$t/SHA256SUMS"
}
publish() {
  UPC_REPO_DIR="$work/repo" UPC_PACKAGES_REMOTE="$work/github.git" SIGNING_KEY_FPR="$fpr" \
    "$ROOT/scripts/publish.sh" 2>/dev/null
}
pull() {
  UPC_BASE="$work/srv" UPC_PACKAGES_REMOTE="$work/github.git" UPC_SIGNING_FPR="$fpr" \
    "$ROOT/server/pull-packages.sh"
}
served() { cat "$work/srv/current/deb/pool/pkg.deb"; }
# Commit a tampered tree straight into "GitHub", as an attacker with write access would.
tamper() {                        # $1 = shell snippet run inside a checkout of the branch
  rm -rf "$work/evil"
  cp -a "$work/good" "$work/evil"          # each attack starts from the last good release
  (cd "$work/evil" && eval "$1" && git add -A && git -c user.name=x -c user.email=x@x commit -q -m evil \
    && git push -q -f origin HEAD:packages)
}

make_tree 2026-01-01T00:00:00Z one; publish; pull >/dev/null
[[ "$(served)" == one ]] || fail "first release not served"
[[ -z "$(pull)" ]] || fail "second pull without change is not silent"

make_tree 2026-01-02T00:00:00Z two; publish; pull >/dev/null
[[ "$(served)" == two ]] || fail "second release not served"
git clone -q --branch packages "$work/github.git" "$work/good"

tamper 'echo evil > deb/pool/pkg.deb'
pull 2>>"$work/refusals" && fail "modified package accepted"
[[ "$(served)" == two ]] || fail "current moved after a refused release"

tamper 'echo x > deb/pool/extra.deb'
pull 2>>"$work/refusals" && fail "unlisted file accepted"

tamper 'ln -s /etc/passwd deb/pool/link'
pull 2>>"$work/refusals" && fail "symlink accepted"

tamper 'echo x > deb/.htaccess'
pull 2>>"$work/refusals" && fail "hidden file accepted"

make_tree 2026-01-01T12:00:00Z old; publish; pull 2>>"$work/refusals" && fail "rollback to an older release accepted"
[[ "$(served)" == two ]] || fail "current moved after a rollback attempt"

make_tree 2026-01-03T00:00:00Z three; publish
UPC_BASE="$work/srv" UPC_PACKAGES_REMOTE="$work/github.git" UPC_SIGNING_FPR=0000000000000000000000000000000000000000 \
  "$ROOT/server/pull-packages.sh" 2>>"$work/refusals" && fail "signature by an unpinned key accepted"
pull >/dev/null
[[ "$(served)" == three ]] || fail "third release not served"
[[ "$(find "$work/srv/releases" -mindepth 1 -maxdepth 1 -type d | wc -l)" -le 3 ]] || fail "old releases not pruned"
sed 's/^/  refused: /' "$work/refusals"
echo "packages roundtrip OK"
