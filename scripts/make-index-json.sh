#!/usr/bin/env bash
# repo/index.json: what the repository serves, read by the web page and by the next release.
# Checksums are recomputed from the files actually present in repo/.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

[[ -s "$BUILD/manifest-new.jsonl" ]] || die "no build/manifest-new.jsonl (run package.sh)"
all="$BUILD/manifest-all.jsonl"
cat "$BUILD/manifest-new.jsonl" > "$all"
[[ -f "$BUILD/manifest-previous.jsonl" ]] && cat "$BUILD/manifest-previous.jsonl" >> "$all"

entries="$BUILD/index-entries.jsonl"
: > "$entries"
while read -r entry; do
  file=$(jq -r .file <<<"$entry")
  [[ -f "$REPO/$file" ]] || die "index entry without file: $file"
  jq -c --arg sha "$(sha256_of "$REPO/$file")" --argjson size "$(stat -c %s "$REPO/$file")" \
    '. + {sha256: $sha, size: $size}' <<<"$entry" >> "$entries"
done < "$all"

fpr=$(sed -n 's/^OpenPGP[^:]*: //p' "$REPO/keys/FINGERPRINTS.txt" 2>/dev/null || true)
# Newest upstream version per Debian architecture (sort -V understands "4.2.5-1").
latest='{}'
for a in $(jq -r .deb_arch "$entries" | sort -u); do
  v=$(jq -r --arg a "$a" 'select(.deb_arch == $a) | .upstream_version' "$entries" | sort -V | tail -n1)
  latest=$(jq -c --arg a "$a" --arg v "$v" '. + {($a): $v}' <<<"$latest")
done
jq -s \
  --arg repo "$REPO_ID" --arg base "$PUBLIC_BASE_URL" --arg gen "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg up_base "$UPSTREAM_BASE" --arg up_suite "$UPSTREAM_SUITE" --arg up_pkg "$UPSTREAM_PACKAGE" \
  --arg fpr "$fpr" --arg apk_key "$APK_KEY_NAME" --argjson latest "$latest" '
  {
    repository: $repo,
    base_url: $base,
    generated: $gen,
    unofficial: "Not affiliated with Proxmox Server Solutions GmbH. Proxmox is a registered trademark of Proxmox Server Solutions GmbH.",
    upstream: {base: $up_base, suite: $up_suite, package: $up_pkg},
    keys: {openpgp_fingerprint: $fpr, openpgp: "keys/\($repo).asc", apk: "keys/\($apk_key)"},
    latest: $latest,
    packages: sort_by(.deb_arch, .format, .file)
  }' "$entries" > "$REPO/index.json"
log "index.json: $(jq '.packages | length' "$REPO/index.json") files, latest $(jq -c .latest "$REPO/index.json")"
