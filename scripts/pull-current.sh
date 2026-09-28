#!/usr/bin/env bash
# Decide which published files the new release carries over, so each release keeps KEEP_VERSIONS
# versions per architecture (downgrades stay possible):
#   - an architecture built in this release keeps its KEEP_VERSIONS-1 previous versions;
#   - an architecture with nothing new keeps its KEEP_VERSIONS newest ones, current included,
#     byte for byte (check-upstream.sh sets BUILD_<arch>=0 and nothing is rebuilt).
# Packages are NOT downloaded here: they would travel through every CI artifact and exceed the
# instance's size limit. This script only writes, with the SHA256 of the published index.json:
#   build/manifest-previous.jsonl  index entries of the carried files (for make-index-json.sh)
#   build/carried.sha256           "<sha256>  <path>" of every carried file, .sig included
#   build/carried-tested.sha256    the subset the install tests need: newest version of TESTED_ARCH
# restore-carried.sh fetches them in the jobs that need them and checks every byte against this list.
# Run after check-upstream.sh.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

prev="$BUILD/manifest-previous.jsonl"
carried="$BUILD/carried.sha256"
tested="$BUILD/carried-tested.sha256"
: > "$prev"; : > "$carried"; : > "$tested"
idx="$BUILD/published-index.json"
if ! curl -fsSL -o "$idx" "$PUBLIC_BASE_URL/index.json" 2>/dev/null; then
  log "nothing published yet"
  exit 0
fi

all=$(mktemp)
trap 'rm -f "$all"' EXIT
for pair in $UPSTREAM_ARCHES; do
  arch="${pair%%:*}"
  new=$(upstream_get "$arch" VERSION)
  if [[ "$(upstream_get "$arch" BUILD)" == 1 ]]; then
    # Older versions of this architecture, newest first, excluding the one being built now.
    keep=$(jq -r --arg a "$arch" --arg new "$new" \
        '[.packages[] | select(.deb_arch == $a and .upstream_version != $new) | .upstream_version] | unique | .[]' "$idx" \
      | sort -rV | head -n "$((KEEP_VERSIONS - 1))")
    current=""
  else
    keep=$(jq -r --arg a "$arch" \
        '[.packages[] | select(.deb_arch == $a) | .upstream_version] | unique | .[]' "$idx" \
      | sort -rV | head -n "$KEEP_VERSIONS")
    current="$new"
    grep -qx -- "$new" <<<"$keep" || die "$arch: $new is not published, yet check-upstream.sh did not build it"
  fi
  for v in $keep; do
    jq -c --arg a "$arch" --arg v "$v" '.packages[] | select(.deb_arch == $a and .upstream_version == $v)' "$idx" |
    while read -r entry; do
      file=$(jq -r .file <<<"$entry")
      sha=$(jq -r .sha256 <<<"$entry")
      [[ "$file" =~ ^(rpm|arch|alpine|deb|source)/[A-Za-z0-9._/+-]+$ && "$file" != *..* ]] || die "suspicious path in index.json: $file"
      [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || die "malformed SHA256 in index.json for $file"
      lines="$sha  $file"

      # index.json est servi par notre propre serveur : il ne peut pas être la seule racine de
      # confiance. Deuxième contrôle, indépendant, quand il est possible :
      case "$file" in
        deb/pool/main/*.deb)
          # Proxmox garde les anciennes versions dans son index signé : on revérifie là-bas.
          up=$(awk -v f="$(basename "$file")" '$1=="Filename:" && index($2, f) {fn=$2} $1=="SHA256:" && fn {print $2; fn=""}' \
                 "$BUILD/upstream-meta/Packages-"* 2>/dev/null | head -n1)
          if [[ -n "$up" ]]; then
            [[ "$up" == "$sha" ]] || die "$file : SHA256 différent de l'index signé de Proxmox"
            log "  $file revérifié contre l'index signé de Proxmox"
          fi ;;
        arch/*/*.pkg.tar.zst)
          # La signature détachée voyage avec le paquet : sans elle, index-arch refusera. Elle n'est
          # pas dans index.json, on l'épingle ici ; verify-release.sh la vérifie avec notre clé.
          sig=$(mktemp)
          fetch "$PUBLIC_BASE_URL/$file.sig" "$sig"
          lines+=$'\n'"$(sha256_of "$sig")  $file.sig"
          rm -f "$sig" ;;
      esac
      printf '%s\n' "$lines" >> "$all"
      if [[ "$v" == "$current" && "$arch" == "$TESTED_ARCH" ]]; then printf '%s\n' "$lines" >> "$tested"; fi
      jq -c 'del(.sha256, .size)' <<<"$entry" >> "$prev"
    done
    log "$arch: carrying $v over"
  done
done

# One source zip may serve both architectures: one line per path, and one SHA256 per path.
LC_ALL=C sort -u "$all" > "$carried"
dup=$(cut -c67- "$carried" | LC_ALL=C sort | uniq -d)
[[ -z "$dup" ]] || die "index.json gives two SHA256 for: $dup"
LC_ALL=C sort -u -o "$tested" "$tested"
log "carried over: $(wc -l < "$carried") files, $(wc -l < "$tested") needed by the install tests"
