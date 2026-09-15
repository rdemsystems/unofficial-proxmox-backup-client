#!/usr/bin/env bash
# Repackage the verified upstream binaries as RPM, Arch and APK with nfpm.
# Nothing is recompiled: binaries, man pages and completions are the upstream files.
# qrencode is the upstream .deb's only dependency ("key paperkey" needs it): hard dependency on
# Arch and Alpine, weak (Recommends) on RPM because its availability on RHEL clones is unverified.
# Our only addition: /usr/lib/ssl/{cert.pem,certs} symlinks to the distribution's CA
# bundle, because the static binary looks for CAs in /usr/lib/ssl (Debian's OPENSSLDIR,
# compiled in) and otherwise rejects valid certificates outside Debian/Ubuntu.
# We link only those two entries, not the whole directory: a symlink /usr/lib/ssl -> /etc/ssl
# would also make the static OpenSSL load the distribution's openssl.cnf.
#
# Signing (optional here, mandatory before publish.sh):
#   UPC_GPG_KEY_FILE  armored secret key, signs RPMs      (passphrase: NFPM_RPM_PASSPHRASE)
#   UPC_APK_KEY_FILE  RSA private key (PEM), signs APKs   (passphrase: NFPM_APK_PASSPHRASE)
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

NFPM="${NFPM:-nfpm}"
command -v "$NFPM" >/dev/null || die "nfpm not found (install it or set NFPM=/path/to/nfpm)"
[[ -s "$BUILD/upstream.env" ]] || die "run check-upstream.sh and fetch-upstream.sh first"

manifest="$BUILD/manifest-new.jsonl"
: > "$manifest"
mkdir -p "$BUILD/nfpm"

add_manifest() { # format deb_arch arch file version component sha
  jq -cn --arg format "$1" --arg deb_arch "$2" --arg arch "$3" --arg file "$4" \
    --arg upstream_version "$5" --arg upstream_component "$6" --arg upstream_deb_sha256 "$7" \
    --arg pkgrel "$PKGREL" '$ARGS.named' >> "$manifest"
}

for pair in $UPSTREAM_ARCHES; do
  arch="${pair%%:*}" component="${pair##*:}"
  version=$(upstream_get "$arch" VERSION)
  deb_sha=$(upstream_get "$arch" SHA256)
  deb_file=$(upstream_get "$arch" FILENAME)
  split_version "$version"
  larch=$(linux_arch "$arch")
  root="$BUILD/root-$arch"
  [[ -x "$root/usr/bin/proxmox-backup-client" ]] || die "missing extracted tree $root"
  mtime=$(date -u -r "$root/usr/bin/proxmox-backup-client" +%Y-%m-%dT%H:%M:%SZ)
  doc="$BUILD/README.unofficial-$arch"

  cat > "$doc" <<EOF
proxmox-backup-client - unofficial repackaging
==============================================

This package repackages, without modification, the statically linked binaries of
Proxmox's official "$UPSTREAM_PACKAGE" package:

  upstream package : $UPSTREAM_PACKAGE $version ($UPSTREAM_SUITE/$component, $arch)
  upstream file    : $UPSTREAM_BASE/$deb_file
  upstream SHA256  : $deb_sha

The only additions are two symlinks, /usr/lib/ssl/cert.pem and /usr/lib/ssl/certs,
pointing to this distribution's CA bundle: the static binary was built with Debian's
OpenSSL directory (/usr/lib/ssl) compiled in and would otherwise reject valid certificates.

Not affiliated with or endorsed by Proxmox Server Solutions GmbH.
Proxmox is a registered trademark of Proxmox Server Solutions GmbH.

License: AGPL-3.0-or-later, see the upstream copyright file shipped with this package.
Corresponding source: $PUBLIC_BASE_URL/source/proxmox-backup-$version.zip
  (Proxmox's proxmox-backup repository at the commit "bump version to $version",
  $UPSTREAM_GIT)
Repository and build scripts: $PUBLIC_BASE_URL/
EOF

  # The upstream .deb itself is part of the deb mirror (Debian/Ubuntu).
  add_manifest deb "$arch" "$arch" "deb/pool/main/$(basename "$deb_file")" "$version" "$component" "$deb_sha"

  for fmt in rpm archlinux apk; do
    case "$fmt" in
      rpm)
        pkg_version="$UP_VER"; pkg_release="$UP_REV.$PKGREL"
        bundle=/etc/pki/tls/certs/ca-bundle.crt; certdir=/etc/pki/tls/certs; dep=ca-certificates
        licdir=/usr/share/licenses/$PKG_NAME
        out="$REPO/rpm/$larch/$PKG_NAME-$pkg_version-$pkg_release.$larch.rpm" ;;
      archlinux)
        # nfpm truncates pkgrel to an integer, so the upstream revision goes into pkgver
        # (4.2.5-1 -> 4.2.5_p1, same scheme as apk) and pkgrel is our PKGREL.
        pkg_version="${UP_VER}_p${UP_REV}"; pkg_release="$PKGREL"
        bundle=/etc/ssl/certs/ca-certificates.crt; certdir=/etc/ssl/certs; dep="ca-certificates qrencode"
        licdir=/usr/share/licenses/$PKG_NAME
        out="$REPO/arch/$larch/$PKG_NAME-$pkg_version-$pkg_release-$larch.pkg.tar.zst" ;;
      apk)
        # apk versions have no Debian revision: 4.2.5-1 -> 4.2.5_p1, our PKGREL -> -rN.
        # apk fetches "<name>-<version>.apk", so the file name is not negotiable.
        pkg_version="${UP_VER}_p${UP_REV}"; pkg_release="$PKGREL"
        bundle=/etc/ssl/certs/ca-certificates.crt; certdir=/etc/ssl/certs; dep="ca-certificates-bundle libqrencode-tools"
        licdir=/usr/share/licenses/$PKG_NAME
        out="$REPO/alpine/$larch/$PKG_NAME-$pkg_version-r$pkg_release.apk" ;;
    esac
    mkdir -p "$(dirname "$out")"
    cfg="$BUILD/nfpm/$fmt-$arch.yaml"

    {
      cat <<EOF
name: $PKG_NAME
arch: $arch
platform: linux
version: "$pkg_version"
version_schema: none
release: "$pkg_release"
mtime: "$mtime"
section: admin
priority: optional
maintainer: "$MAINTAINER"
vendor: "$VENDOR"
homepage: "$PUBLIC_BASE_URL/"
license: AGPL-3.0-or-later
description: |-
  Proxmox Backup Server command line client (unofficial repackaging)
  Unmodified statically linked proxmox-backup-client and pxar from Proxmox's
  official $UPSTREAM_PACKAGE $version. Not affiliated with Proxmox Server
  Solutions GmbH. See $PUBLIC_BASE_URL/
depends:
$(for d in $dep; do printf '  - %s\n' "$d"; done)
conflicts:
  - $UPSTREAM_PACKAGE
contents:
  - src: $root/usr/bin/proxmox-backup-client
    dst: /usr/bin/proxmox-backup-client
    file_info: {mode: 0755}
  - src: $root/usr/bin/pxar
    dst: /usr/bin/pxar
    file_info: {mode: 0755}
  - src: $root/usr/share/man/man1/proxmox-backup-client.1.gz
    dst: /usr/share/man/man1/proxmox-backup-client.1.gz
  - src: $root/usr/share/man/man1/pxar.1.gz
    dst: /usr/share/man/man1/pxar.1.gz
  - src: $root/usr/share/bash-completion/completions/proxmox-backup-client
    dst: /usr/share/bash-completion/completions/proxmox-backup-client
  - src: $root/usr/share/bash-completion/completions/pxar
    dst: /usr/share/bash-completion/completions/pxar
  - src: $root/usr/share/zsh/vendor-completions/_proxmox-backup-client
    dst: /usr/share/zsh/site-functions/_proxmox-backup-client
  - src: $root/usr/share/zsh/vendor-completions/_pxar
    dst: /usr/share/zsh/site-functions/_pxar
  - src: $root/usr/share/doc/$UPSTREAM_PACKAGE/copyright
    dst: $licdir/copyright
  - src: $doc
    dst: /usr/share/doc/$PKG_NAME/README.unofficial
  - src: $bundle
    dst: /usr/lib/ssl/cert.pem
    type: symlink
  - src: $certdir
    dst: /usr/lib/ssl/certs
    type: symlink
EOF
      if [[ "$fmt" == rpm ]]; then
        printf 'recommends:\n  - qrencode\nrpm:\n  summary: Proxmox Backup Server client (unofficial repackaging)\n  group: Applications/System\n  compression: xz\n'
        [[ -n "${UPC_GPG_KEY_FILE:-}" ]] && printf '  signature:\n    key_file: "%s"\n' "$UPC_GPG_KEY_FILE"
      fi
      if [[ "$fmt" == archlinux ]]; then
        printf 'archlinux:\n  packager: "%s"\n' "$MAINTAINER"
      fi
      if [[ "$fmt" == apk && -n "${UPC_APK_KEY_FILE:-}" ]]; then
        printf 'apk:\n  signature:\n    key_file: "%s"\n    key_name: "%s"\n' "$UPC_APK_KEY_FILE" "${APK_KEY_NAME%.rsa.pub}"
      fi
    } > "$cfg"

    "$NFPM" package --config "$cfg" --packager "$fmt" --target "$out" >/dev/null
    log "built ${out#"$REPO/"}"
    add_manifest "$fmt" "$arch" "$larch" "${out#"$REPO/"}" "$version" "$component" "$deb_sha"
  done
done
