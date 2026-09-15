#!/usr/bin/env bash
# Cron job on the web host: pull the "packages" branch from GitHub, verify it, switch atomically.
#
# Trust: SHA256SUMS.asc is checked with a keyring kept ON THIS HOST (never the key shipped in the
# branch) and must come from the pinned fingerprint. Every file must be listed in SHA256SUMS and
# match it; nothing else is accepted (no symlink, no dot file). A release older than the one
# being served is refused, so a replayed old branch cannot roll the repository back.
#
# Layout under $UPC_BASE:
#   trusted.gpg        our public key as a gpgv keyring, installed by hand (see README)
#   git/               bare clone, packages branch only, depth 1
#   releases/<id>/     verified trees; the newest $UPC_KEEP_RELEASES are kept
#   current            symlink to the release being served, switched with rename(2)
# The web site links rpm, arch, alpine, deb, keys, source, index.json and SHA256SUMS(.asc) to current/.
#
# Silent when there is nothing new, so cron only mails on a switch or an error.
#   */10 * * * * /var/www/unofficial-repository-proxmox-backup-client/pull-packages.sh
set -euo pipefail
umask 022

BASE="${UPC_BASE:-/var/www/unofficial-repository-proxmox-backup-client}"
REMOTE="${UPC_PACKAGES_REMOTE:-https://github.com/rdemsystems/unofficial-proxmox-backup-client.git}"
BRANCH="${UPC_PACKAGES_BRANCH:-packages}"
FPR="${UPC_SIGNING_FPR:-827DEFD8FDAD5EE640805C30904EB81A1243150F}"
KEEP="${UPC_KEEP_RELEASES:-3}"

log() { printf '%s\n' "$*"; }
die() { printf 'pull-packages: %s\n' "$*" >&2; exit 1; }

[[ -d "$BASE" ]] || die "$BASE does not exist"
exec 9>"$BASE/.lock"
flock -n 9 || exit 0
[[ -s "$BASE/trusted.gpg" ]] || die "$BASE/trusted.gpg is missing"
mkdir -p "$BASE/releases"

git="$BASE/git"
[[ -d "$git" ]] || git init -q --bare "$git"
git -C "$git" fetch -q --depth 1 "$REMOTE" "+refs/heads/$BRANCH:refs/heads/$BRANCH" || die "fetch failed"
commit=$(git -C "$git" rev-parse --verify "refs/heads/$BRANCH^{commit}")
id="${commit:0:16}"
[[ "$(readlink "$BASE/current" 2>/dev/null)" == "releases/$id" ]] && exit 0

tmp="$BASE/releases/.incoming"
rm -rf "$tmp"
mkdir "$tmp"
trap 'rm -rf "$tmp"' EXIT
git -C "$git" -c tar.umask=022 archive --format=tar "$commit" | tar -x --no-same-owner -C "$tmp"
rm -f "$tmp/README.md"                      # branch landing text, not part of the release

# 1. Only plain files and directories, no hidden names.
odd=$(find "$tmp" -mindepth 1 \( ! -type f ! -type d -o -name '.*' \) -printf '%P\n' | head -n 5)
[[ -z "$odd" ]] || die "$id: entries not allowed: $odd"

# 2. Signature of SHA256SUMS, by the pinned key, checked with the local keyring.
[[ -s "$tmp/SHA256SUMS" && -s "$tmp/SHA256SUMS.asc" ]] || die "$id: SHA256SUMS or its signature is missing"
status=$(gpgv --keyring "$BASE/trusted.gpg" --status-fd 1 "$tmp/SHA256SUMS.asc" "$tmp/SHA256SUMS" 2>/dev/null) \
  || die "$id: SHA256SUMS.asc does not verify"
awk -v fpr="$FPR" '$2 == "VALIDSIG" && ($3 == fpr || $NF == fpr) {ok=1} END {exit !ok}' <<<"$status" \
  || die "$id: SHA256SUMS is not signed by $FPR"

# 3. Every file listed, every checksum right, nothing unlisted.
grep -Evq '^[0-9a-f]{64}  [A-Za-z0-9._+/-]+$' "$tmp/SHA256SUMS" && die "$id: malformed line in SHA256SUMS"
grep -Eq '(^|/)\.' <(cut -c67- "$tmp/SHA256SUMS") && die "$id: hidden or relative path in SHA256SUMS"
(cd "$tmp" && sha256sum --quiet --strict -c SHA256SUMS >/dev/null 2>&1) || die "$id: checksum mismatch or missing file"
unlisted=$(comm -13 <(cut -c67- "$tmp/SHA256SUMS" | LC_ALL=C sort) \
                    <(cd "$tmp" && find . -type f ! -name SHA256SUMS ! -name SHA256SUMS.asc -printf '%P\n' | LC_ALL=C sort))
[[ -z "$unlisted" ]] || die "$id: files not listed in SHA256SUMS: $(head -n 5 <<<"$unlisted")"

# 4. No rollback.
new_gen=$(jq -er .generated "$tmp/index.json") || die "$id: index.json unreadable"
if [[ -s "$BASE/current/index.json" ]]; then
  cur_gen=$(jq -r .generated "$BASE/current/index.json")
  [[ ! "$new_gen" < "$cur_gen" ]] || die "$id: generated $new_gen is older than the served release ($cur_gen)"
fi

# 5. Switch.
rm -rf "$BASE/releases/$id"
mv -T "$tmp" "$BASE/releases/$id"
trap - EXIT
touch "$BASE/releases/$id"
ln -sfn "releases/$id" "$BASE/current.new"
mv -T "$BASE/current.new" "$BASE/current"
log "switched to $id (generated $new_gen, latest $(jq -c .latest "$BASE/current/index.json"))"

# 6. Prune old releases (never the current one) and objects of replaced commits.
find "$BASE/releases" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%T@ %f\n' | sort -rn \
  | tail -n +"$((KEEP + 1))" | while read -r _ old; do
  [[ "$old" == "$id" ]] || rm -rf "${BASE:?}/releases/$old"
done
git -C "$git" gc -q --prune=now 2>/dev/null || true
