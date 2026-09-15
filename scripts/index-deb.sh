#!/usr/bin/env bash
# Signed APT repository (Debian/Ubuntu) around the upstream .deb files, served byte for byte.
# Suite "stable", component "main". Needs: apt-ftparchive (apt-utils), gpg, UPC_GPG_KEY_FILE.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

gpg_setup
cd "$REPO/deb" || exit 1
dist=dists/stable
rm -rf "$dist" && mkdir -p "$dist"

arches=$(find pool/main -name '*.deb' -printf '%f\n' | sed -E 's/.*_([a-z0-9]+)\.deb$/\1/' | sort -u)
[[ -n "$arches" ]] || die "no .deb in $REPO/deb/pool/main"
for arch in $arches; do
  mkdir -p "$dist/main/binary-$arch"
  apt-ftparchive --arch "$arch" packages pool/main > "$dist/main/binary-$arch/Packages"
  gzip -9nkf "$dist/main/binary-$arch/Packages"
done

apt-ftparchive \
  -o APT::FTPArchive::Release::Origin="$REPO_ID" \
  -o APT::FTPArchive::Release::Label="$REPO_ID" \
  -o APT::FTPArchive::Release::Suite=stable \
  -o APT::FTPArchive::Release::Codename=stable \
  -o APT::FTPArchive::Release::Architectures="${arches//$'\n'/ }" \
  -o APT::FTPArchive::Release::Components=main \
  -o APT::FTPArchive::Release::Description="Unofficial mirror of Proxmox's $UPSTREAM_PACKAGE, not affiliated with Proxmox Server Solutions GmbH" \
  release "$dist" > "$BUILD/Release.deb"
mv "$BUILD/Release.deb" "$dist/Release"

"${GPG_SIGN[@]}" --clearsign -o "$dist/InRelease" "$dist/Release"
"${GPG_SIGN[@]}" --armor --detach-sign -o "$dist/Release.gpg" "$dist/Release"
log "signed deb/$dist (${arches//$'\n'/ })"
