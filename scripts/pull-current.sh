#!/usr/bin/env bash
# Bring back the packages of the previous upstream versions from the published repository,
# so each release keeps KEEP_VERSIONS versions per architecture (downgrades stay possible).
# Every file is checked against the SHA256 recorded in the published index.json.
# Writes build/manifest-previous.jsonl. Run after check-upstream.sh.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

prev="$BUILD/manifest-previous.jsonl"
: > "$prev"
idx="$BUILD/published-index.json"
if ! curl -fsSL -o "$idx" "$PUBLIC_BASE_URL/index.json" 2>/dev/null; then
  log "nothing published yet"
  exit 0
fi

for pair in $UPSTREAM_ARCHES; do
  arch="${pair%%:*}"
  new=$(upstream_get "$arch" VERSION)
  # Older versions of this architecture, newest first, excluding the one being built now.
  keep=$(jq -r --arg a "$arch" --arg new "$new" \
      '[.packages[] | select(.deb_arch == $a and .upstream_version != $new) | .upstream_version] | unique | .[]' "$idx" \
    | sort -rV | head -n "$((KEEP_VERSIONS - 1))")
  for v in $keep; do
    jq -c --arg a "$arch" --arg v "$v" '.packages[] | select(.deb_arch == $a and .upstream_version == $v)' "$idx" |
    while read -r entry; do
      file=$(jq -r .file <<<"$entry")
      sha=$(jq -r .sha256 <<<"$entry")
      [[ "$file" =~ ^(rpm|arch|alpine|deb|source)/[A-Za-z0-9._/+-]+$ && "$file" != *..* ]] || die "suspicious path in index.json: $file"
      mkdir -p "$REPO/$(dirname "$file")"
      fetch "$PUBLIC_BASE_URL/$file" "$REPO/$file"
      [[ "$(sha256_of "$REPO/$file")" == "$sha" ]] || die "$file does not match the published index"

      # index.json est servi par notre propre serveur : il ne peut pas être la seule racine de
      # confiance. Deuxième contrôle, indépendant, quand il est possible :
      case "$file" in
        deb/pool/main/*.deb)
          # Proxmox garde les anciennes versions dans son index signé : on revérifie là-bas.
          up=$(awk -v f="$(basename "$file")" '$1=="Filename:" && index($2, f) {fn=$2} $1=="SHA256:" && fn {print $2; fn=""}' \
                 "$BUILD/upstream-meta/Packages-"* 2>/dev/null | head -n1)
          if [[ -n "$up" ]]; then
            [[ "$up" == "$sha" ]] || die "$file : SHA256 différent de l'index signé de Proxmox"
            log "  (revérifié contre l'index signé de Proxmox)"
          fi ;;
        arch/*/*.pkg.tar.zst)
          # La signature détachée voyage avec le paquet : sans elle, index-arch refusera.
          fetch "$PUBLIC_BASE_URL/$file.sig" "$REPO/$file.sig" ;;
      esac
      jq -c 'del(.sha256, .size)' <<<"$entry" >> "$prev"
    done
    log "$arch: kept $v"
  done
done
