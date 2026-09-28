#!/usr/bin/env bash
# Put back into repo/ the files pull-current.sh carries over from the published repository,
# fetched again from it and checked byte for byte against build/carried.sha256. They are
# re-fetched in the jobs that need them instead of travelling as CI artifacts (size limit).
#
#   restore-carried.sh [prefix...]   every carried file, or only paths starting with a prefix (rpm/ arch/…)
#   restore-carried.sh --drop        remove from repo/ the carried files the install tests do not need
#                                    (they install the newest TESTED_ARCH version only); publish restores them
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

carried="$BUILD/carried.sha256"
[[ -f "$carried" ]] || die "no build/carried.sha256 (run pull-current.sh)"

if [[ "${1:-}" == --drop ]]; then
  [[ -f "$BUILD/carried-tested.sha256" ]] || die "no build/carried-tested.sha256 (run pull-current.sh)"
  n=0
  while read -r _ file; do
    [[ "$file" =~ ^(rpm|arch|alpine|deb|source)/[A-Za-z0-9._/+-]+$ && "$file" != *..* ]] || die "suspicious path: $file"
    rm -f -- "$REPO/$file"; n=$((n + 1))
  done < <(LC_ALL=C comm -23 "$carried" "$BUILD/carried-tested.sha256")
  log "dropped $n carried files the tests do not need (restored again before publishing)"
  exit 0
fi

for prefix in "$@"; do
  [[ "$prefix" =~ ^(rpm|arch|alpine|deb|source)/$ ]] || die "unknown argument: $prefix (prefixes: rpm/ arch/ alpine/ deb/ source/, or --drop)"
done
n=0
while read -r sha file; do
  [[ "$sha" =~ ^[0-9a-f]{64}$ ]] || die "malformed line in carried.sha256: $sha $file"
  [[ "$file" =~ ^(rpm|arch|alpine|deb|source)/[A-Za-z0-9._/+-]+$ && "$file" != *..* ]] || die "suspicious path: $file"
  if (( $# )); then
    match=0
    for prefix in "$@"; do [[ "$file" == "$prefix"* ]] && match=1; done
    (( match )) || continue
  fi
  if [[ -f "$REPO/$file" && "$(sha256_of "$REPO/$file")" == "$sha" ]]; then continue; fi
  mkdir -p "$REPO/$(dirname "$file")"
  fetch "$PUBLIC_BASE_URL/$file" "$REPO/$file"
  [[ "$(sha256_of "$REPO/$file")" == "$sha" ]] || { rm -f "$REPO/$file"; die "$file does not match build/carried.sha256"; }
  n=$((n + 1))
done < "$carried"
log "restored $n carried files${1:+ ($*)}"
