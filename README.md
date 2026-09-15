# Unofficial proxmox-backup-client packages

> **Unofficial repository, not affiliated with or endorsed by Proxmox Server Solutions GmbH.**
> Proxmox is a registered trademark of Proxmox Server Solutions GmbH.

Signed `proxmox-backup-client` packages for **Fedora, RHEL, Rocky Linux, AlmaLinux, Arch Linux and
Alpine** (amd64, arm64) — Proxmox's official static binary, repackaged unchanged, checked daily
against Proxmox's own repository.

**To install the client, use the package repository, not this Git repository:**

- 📦 **Package repository and install instructions (dnf, pacman, apk, apt):**
  https://nimbus.rdem-systems.com/unofficial-pbs-client/
- 📘 **Tutorial — back up a Linux server with proxmox-backup-client:**
  https://nimbus.rdem-systems.com/en/blog/proxmox-backup-client-linux/
  (French: https://nimbus.rdem-systems.com/blog/proxmox-backup-client-linux/)
- ☁️ **Maintained by [NimbusBackup](https://nimbus.rdem-systems.com/)**, managed Proxmox Backup
  Server hosting by RDEM Systems.

This GitHub repository publishes the build scripts (MIT) so that anyone can audit or reproduce
how the packages are made. The CI that signs and publishes the packages runs on RDEM Systems'
own GitLab; signing keys never leave it.

## Repackaging only — the binaries are Proxmox's

This project does **not** build, patch or fork the Proxmox Backup Server client. It only
repackages Proxmox's own binaries for the distributions Proxmox does not ship packages for:

1. **Download** Proxmox's official, statically linked build (`proxmox-backup-client-static`)
   from `download.proxmox.com`, and check it against Proxmox's signed repository index.
2. **Repackage** that binary, unchanged, as RPM, Arch and APK packages. Debian and Ubuntu get
   Proxmox's `.deb` byte for byte.
3. **Sign and deploy** the packages on RDEM Systems' servers, as a repository your package
   manager can use.

No Proxmox code is changed or recompiled. The only addition in the RPM, Arch and APK packages
is two certificate symlinks, explained in [The one change we make](#the-one-change-we-make).

Proxmox publishes the Proxmox Backup Server client for Debian only. This repository takes
Proxmox's own statically linked build (`proxmox-backup-client-static`), checks it against
Proxmox's signed repository index, and republishes it, **without recompiling anything**, as
signed packages for:

| Family | CI install test matrix | Package manager |
|---|---|---|
| Fedora, RHEL, Rocky, Alma | Fedora, Rocky 9, Alma 10 | `dnf` |
| Arch Linux | Arch | `pacman` |
| Alpine | 3.22, 3.24 | `apk` |
| Debian, Ubuntu | Debian 12/13, Ubuntu 22.04/24.04 | `apt` (the upstream `.deb`, byte for byte) |

Architectures: **amd64** from Proxmox's `main` component, **arm64** from Proxmox's `test`
component (the official upstream static aarch64 build, which can lag one release behind).
Every package records which component it comes from, and `index.json` shows it.

Each release also publishes `source/proxmox-backup-<version>.zip`: Proxmox's source at the
commit "bump version to <version>" the binary was built from (checked against the top entry
of `debian/changelog` at that commit).

Install instructions for users live on the repository page:
https://nimbus.rdem-systems.com/unofficial-pbs-client/

## The one change we make

The static binary was built with Debian's OpenSSL directory (`/usr/lib/ssl`) compiled in.
Outside Debian and Ubuntu that directory does not exist, so the client rejects **valid**
certificates and asks for a fingerprint (`certificate validation failed - Certificate
fingerprint was not confirmed`). Checked on Alpine 3.24 and Fedora 43.

Our RPM, Arch and APK packages therefore add two symlinks:

```
/usr/lib/ssl/cert.pem -> the distribution's CA bundle
/usr/lib/ssl/certs    -> the distribution's certificate directory
```

Only these two entries: linking the whole `/usr/lib/ssl` to `/etc/ssl` would also make the
static OpenSSL read the distribution's `openssl.cnf`. The binaries, man pages and shell
completions are the upstream files. The `.deb` files are served unmodified.

## How a release is made

```
check-upstream.sh   pinned Proxmox keyring -> InRelease (gpgv) -> Packages (SHA256) -> newest version
fetch-upstream.sh   .deb checked against the signed index (SHA256 + size), extracted
pull-current.sh     previous versions fetched back, checked against the published index.json AND,
                    for .deb, against Proxmox's signed index again (it keeps old versions)
package.sh          nfpm -> RPM (signed), Arch, APK (signed)
source-archive.sh   zip of the upstream source at the matching "bump version" commit
export-keys.sh      public keys -> repo/keys/
index-*.sh          createrepo_c + signed repomd.xml, repo-add + signed db, signed APKINDEX,
                    apt-ftparchive + signed InRelease
test-install.sh     install from the signed repository in each distribution, TLS probe,
                    optional real backup + restore
make-index-json.sh  repo/index.json
verify-release.sh   offline gate: every file signed, listed, matching index.json, no symlink
publish.sh          rsync into a new release directory, atomic switch of "current"
```

The GitLab pipeline (`.gitlab-ci.yml`) runs `check-upstream` daily and only builds when
Proxmox has published a new version. Publishing is a manual job.

## CI setup

The GitLab project that runs the CI is private; this public repository is a separate history
exported from its `public/` directory (a separate history, gated against any private key or
token material).

- **Signing keys**: read from the private project's `secrets/` directory (next to `public/`) by `scripts/lib.sh`
  (`UPC_GPG_KEY_FILE`, `UPC_APK_KEY_FILE` can override them for local runs).
- **Runners**: any Docker runner of the project; no tag.
- **Public signing key** (packages, repository metadata): published under `keys/` of every
  release. Fingerprint `827D EFD8 FDAD 5EE6 4080  5C30 904E B81A 1243 150F`.

## Local run

```
scripts/check-upstream.sh && scripts/fetch-upstream.sh
NFPM=/path/to/nfpm UPC_GPG_KEY_FILE=... UPC_APK_KEY_FILE=... scripts/package.sh
tests/publish-roundtrip.sh     # publish + forced command against a temporary directory
```

## Licenses

- Build scripts in this repository: MIT, see `LICENSE` (scope and trademark notice in `NOTICE`).
- Packaged software: GNU AGPL v3 or later, Copyright Proxmox Server Solutions GmbH. The
  corresponding source is published with every release under `source/`, taken from
  Proxmox's `proxmox-backup` repository (https://git.proxmox.com/?p=proxmox-backup.git).
