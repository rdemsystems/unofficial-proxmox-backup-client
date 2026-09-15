#!/usr/bin/env bash
# Resolve the newest upstream static client for each configured architecture, through
# the signed chain only:
#   pinned keyring -> InRelease (gpgv) -> Packages (SHA256 listed in InRelease)
#                  -> .deb (SHA256 + size listed in Packages, checked later by fetch-upstream.sh)
# Writes build/upstream.env and build/decision ("release" or "noop").
# FORCE_RELEASE=1 builds even when the published index already has these versions.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

mkdir -p "$BUILD"
meta="$BUILD/upstream-meta"
rm -rf "$meta" && mkdir -p "$meta"

# The pinned keyring must be the file we reviewed, not whatever landed in the checkout.
[[ "$(sha256_of "$ROOT/$UPSTREAM_KEYRING")" == "$UPSTREAM_KEYRING_SHA256" ]] \
  || die "$UPSTREAM_KEYRING does not match the SHA256 pinned in config.env"

fetch "$UPSTREAM_BASE/dists/$UPSTREAM_SUITE/InRelease" "$meta/InRelease"
gpgv --status-fd 3 --keyring "$ROOT/$UPSTREAM_KEYRING" --output "$meta/Release" "$meta/InRelease" \
  3>"$meta/gpgv.status" 2>"$meta/gpgv.log" \
  || { cat "$meta/gpgv.log" >&2; die "InRelease signature does not verify against the pinned keyring"; }
# The keyring holds several Proxmox keys: require the one we expect, not just "any key in it".
grep -q "VALIDSIG $UPSTREAM_SIGNER_FPR" "$meta/gpgv.status" \
  || { cat "$meta/gpgv.status" >&2; die "InRelease was not signed by $UPSTREAM_SIGNER_FPR"; }
log "InRelease signed by $UPSTREAM_SIGNER_FPR"

# Replay / freeze: a signature stays valid forever, the index behind it must not.
release_date=$(sed -n 's/^Date: //p' "$meta/Release" | head -n1)
[[ -n "$release_date" ]] || die "no Date in the signed Release file"
age_days=$(( ( $(date -u +%s) - $(date -u -d "$release_date" +%s) ) / 86400 ))
(( age_days <= MAX_RELEASE_AGE_DAYS )) \
  || die "signed Release is $age_days days old (max $MAX_RELEASE_AGE_DAYS) — mirror frozen, or upstream stopped publishing"
(( age_days >= -1 )) || die "signed Release is dated in the future ($release_date)"
valid_until=$(sed -n 's/^Valid-Until: //p' "$meta/Release" | head -n1)
if [[ -n "$valid_until" ]]; then
  (( $(date -u -d "$valid_until" +%s) > $(date -u +%s) )) || die "signed Release expired on $valid_until"
fi

: > "$BUILD/upstream.env"
for pair in $UPSTREAM_ARCHES; do
  arch="${pair%%:*}" component="${pair##*:}"
  index="$component/binary-$arch/Packages"

  # SHA256 section of Release: " <sha256> <size> <path>"
  mapfile -t signed < <(awk -v p="$index" '/^SHA256:/{s=1; next} /^[^ ]/{s=0} s && $3==p {print $1, $2}' "$meta/Release")
  (( ${#signed[@]} == 1 )) || die "$index is listed ${#signed[@]} time(s) in the signed Release file"
  read -r expected expected_size <<<"${signed[0]}"
  [[ "$expected" =~ ^[0-9a-f]{64}$ && "$expected_size" =~ ^[0-9]+$ ]] || die "malformed SHA256 entry for $index"
  fetch "$UPSTREAM_BASE/dists/$UPSTREAM_SUITE/$index" "$meta/Packages-$arch"
  [[ "$(sha256_of "$meta/Packages-$arch")" == "$expected" ]] || die "$index does not match the signed Release file"
  [[ "$(stat -c %s "$meta/Packages-$arch")" == "$expected_size" ]] || die "$index size differs from the signed Release file"

  # Newest stanza of our package for this architecture: "version filename sha256 size"
  candidates=$(awk -v pkg="$UPSTREAM_PACKAGE" -v a="$arch" '
      function flush() { if (p==pkg && ar==a) print v, f, h, s; p=ar=v=f=h=s="" }
      /^$/ {flush(); next}
      /^Package: /      {p=$2}
      /^Architecture: / {ar=$2}
      /^Version: /      {v=$2}
      /^Filename: /     {f=$2}
      /^SHA256: /       {h=$2}
      /^Size: /         {s=$2}
      END {flush()}' "$meta/Packages-$arch")
  [[ -n "$candidates" ]] || die "no $UPSTREAM_PACKAGE for $arch in $component"
  # Debian version ordering is not "sort -V": epochs, tildes and revisions differ. Use dpkg.
  best=""
  while read -r line; do
    [[ -n "$line" ]] || continue
    if [[ -z "$best" ]] || dpkg --compare-versions "${line%% *}" gt "${best%% *}"; then best="$line"; fi
  done <<< "$candidates"
  read -r version filename sha size <<<"$best"
  split_version "$version"
  # These values end up in URLs, file names and (through upstream.env) in the shell.
  [[ "$filename" =~ ^dists/[A-Za-z0-9._/-]+\.deb$ && "$filename" != *..* ]] || die "unexpected Filename: $filename"
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || die "unexpected SHA256: $sha"
  [[ "$size" =~ ^[0-9]+$ ]] || die "unexpected Size: $size"
  [[ "$version" =~ ^[0-9][A-Za-z0-9.+~:-]*$ ]] || die "unexpected Version: $version"
  log "$arch ($component): $UPSTREAM_PACKAGE $version"
  {
    echo "VERSION_${arch}=$version"
    echo "COMPONENT_${arch}=$component"
    echo "FILENAME_${arch}=$filename"
    echo "SHA256_${arch}=$sha"
    echo "SIZE_${arch}=$size"
  } >> "$BUILD/upstream.env"
done

# Compare with what is already published.
decision=noop
published="$meta/published-index.json"
if curl -fsSL -o "$published" "$PUBLIC_BASE_URL/index.json" 2>/dev/null; then
  for pair in $UPSTREAM_ARCHES; do
    arch="${pair%%:*}"
    v=$(upstream_get "$arch" VERSION)
    if ! jq -e --arg a "$arch" --arg v "$v" \
        'any(.packages[]; .deb_arch == $a and .upstream_version == $v)' "$published" >/dev/null; then
      log "$arch: $v is not published yet"
      decision=release
    fi
  done
else
  log "no published index.json yet: first release"
  decision=release
fi
[[ "${FORCE_RELEASE:-0}" == 1 ]] && { log "FORCE_RELEASE=1"; decision=release; }

echo "$decision" > "$BUILD/decision"
log "decision: $decision"
