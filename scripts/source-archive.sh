#!/usr/bin/env bash
# Publish, next to the packages, a zip of the upstream source each binary is based on
# (AGPL-3.0): Proxmox's proxmox-backup repository at the commit "bump version to X".
# Proxmox does not always push release tags (no v4.2.5), hence the commit lookup, checked
# against the top entry of debian/changelog at that commit.
# Appends "source" entries to build/manifest-new.jsonl. Run after package.sh.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

[[ -s "$BUILD/upstream.env" ]] || die "run check-upstream.sh first"
git_dir="$BUILD/proxmox-backup.git"
if [[ -d "$git_dir" ]]; then
  git --git-dir="$git_dir" fetch -q origin '+refs/heads/*:refs/heads/*'
else
  git clone -q --bare "$UPSTREAM_GIT_CLONE" "$git_dir"
fi
mkdir -p "$REPO/source"

for pair in $UPSTREAM_ARCHES; do
  arch="${pair%%:*}" component="${pair##*:}"
  version=$(upstream_get "$arch" VERSION)
  deb_sha=$(upstream_get "$arch" SHA256)
  commit=$(git --git-dir="$git_dir" log --all -F --grep="bump version to $version" --format=%H -1)
  [[ -n "$commit" ]] || die "no upstream commit 'bump version to $version'"
  top=$(git --git-dir="$git_dir" show "$commit:debian/changelog" | sed -n 1p)   # no head: SIGPIPE + pipefail
  [[ "$top" == *"($version)"* ]] || die "debian/changelog at $commit is not $version: $top"

  zip="source/proxmox-backup-$version.zip"
  if [[ ! -s "$REPO/$zip" ]]; then
    git --git-dir="$git_dir" archive --format=zip --prefix="proxmox-backup-$version/" -o "$REPO/$zip" "$commit"
    log "source $zip ($commit)"
  fi
  jq -cn --arg deb_arch "$arch" --arg file "$zip" --arg upstream_version "$version" \
    --arg upstream_component "$component" --arg upstream_deb_sha256 "$deb_sha" \
    --arg upstream_commit "$commit" --arg pkgrel "$PKGREL" \
    '{format: "source", deb_arch: $deb_arch, arch: "source", file: $file, upstream_version: $upstream_version,
      upstream_component: $upstream_component, upstream_deb_sha256: $upstream_deb_sha256,
      upstream_commit: $upstream_commit, pkgrel: $pkgrel}' >> "$BUILD/manifest-new.jsonl"
done
