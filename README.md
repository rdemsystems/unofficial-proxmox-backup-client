# Unofficial proxmox-backup-client packages

🇫🇷 [Lire en français](README.fr.md)

> **Unofficial repository, not affiliated with or endorsed by Proxmox Server Solutions GmbH.**
> Proxmox is a registered trademark of Proxmox Server Solutions GmbH.

Signed `proxmox-backup-client` packages for **Fedora, RHEL, Rocky Linux, AlmaLinux, Arch Linux and
Alpine** (amd64, arm64) — Proxmox's official static binary, repackaged unchanged, checked daily
against Proxmox's own repository.

**To install the client, use the package repository, not this Git repository:**

- 📦 **Package repository and install instructions (dnf, pacman, apk, apt):**
  https://nimbus.rdem-systems.com/en/unofficial-repository-proxmox-backup-client/?utm_source=github&utm_medium=readme&utm_campaign=upc-repo
  (French: https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/?utm_source=github&utm_medium=readme&utm_campaign=upc-repo)
- 📘 **Tutorial — back up a Linux server with proxmox-backup-client:**
  https://nimbus.rdem-systems.com/en/blog/proxmox-backup-client-linux/?utm_source=github&utm_medium=readme&utm_campaign=upc-repo
  (French: https://nimbus.rdem-systems.com/blog/proxmox-backup-client-linux/?utm_source=github&utm_medium=readme&utm_campaign=upc-repo)
- 🪟 **On Windows:** [NimbusBackupClient](https://github.com/rdemsystems/NimbusBackupClient), our
  graphical client for Proxmox Backup Server.
- ☁️ **Need managed PBS backup space?** Pick a plan:
  https://nimbus.rdem-systems.com/en/choose-backup/?utm_source=github&utm_medium=readme&utm_campaign=upc-repo — maintained by
  [NimbusBackup](https://nimbus.rdem-systems.com/?utm_source=github&utm_medium=readme&utm_campaign=upc-repo), managed Proxmox Backup Server hosting by RDEM Systems.

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

### What the packages contain

`proxmox-backup-client` and `pxar`, with their man pages and bash/zsh completions — the files of
Proxmox's static package, as they are.

**`proxmox-file-restore` is not included**, for three reasons:

1. **Proxmox publishes no static build of it.** The official package is dynamically linked against
   `libc6`, `libssl3`, `libzstd1`, `libacl1` and `libuuid1`; those libraries exist neither on Alpine
   (musl) nor on RHEL under the same sonames, so the binary would not start.
2. **Shipping it would mean compiling it** — a different project from this one, and the end of the
   only promise that matters here: the binary you install is Proxmox's, not ours.
3. **It needs more than itself.** Restoring a file from a VM disk image runs a dedicated virtual
   machine: Proxmox's restore image (kernel + initramfs) and QEMU, neither portable outside Debian.
   For a host backup, the client's `catalog shell` and `restore --pattern` already do file-level restore.

If Proxmox ever publishes a static `proxmox-file-restore` in its client repository, we will package
it like the rest, without recompiling it.

Proxmox publishes the Proxmox Backup Server client for Debian only. This repository takes
Proxmox's own statically linked build (`proxmox-backup-client-static`), checks it against
Proxmox's signed repository index, and republishes it, **without recompiling anything**, as
signed packages for:

| Family | CI install test matrix | Package manager |
|---|---|---|
| RHEL family, Fedora | CentOS 7 · Rocky Linux 8, 9, 10 · AlmaLinux 8, 9, 10 · Fedora 42, 43, 44 | `dnf` / `yum` |
| Arch Linux | Arch (rolling) | `pacman` |
| Alpine | 3.20, 3.21, 3.22, 3.23, 3.24 | `apk` |
| Debian, Ubuntu | Debian 10, 11, 12, 13, testing, sid · Ubuntu 20.04, 22.04, 24.04, 25.10, 26.04 | `apt` (the upstream `.deb`, byte for byte) |

Test policy: every release still supported by its distribution, plus at least the last one that went out
of support; Arch is rolling.
If you want other distributions, [let us know](https://nimbus.rdem-systems.com/en/contact/?utm_source=github&utm_medium=readme&utm_campaign=upc-repo), and tell us why.

Architectures: **amd64** from Proxmox's `main` component, **arm64** from Proxmox's `test`
component (the official upstream static aarch64 build, which can lag one release behind).
Every package records which component it comes from, and `index.json` shows it.

Each release also publishes `source/proxmox-backup-<version>.zip`: Proxmox's source at the
commit "bump version to <version>" the binary was built from (checked against the top entry
of `debian/changelog` at that commit).

## Install

All repository metadata is signed: never add `--nogpgcheck` or `--allow-untrusted`. Compare the
key fingerprint your package manager shows with the one published on
https://nimbus.rdem-systems.com/en/unofficial-repository-proxmox-backup-client/?utm_source=github&utm_medium=readme&utm_campaign=upc-repo and in [`FINGERPRINTS.txt`](https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/keys/FINGERPRINTS.txt):

```
OpenPGP (RPM, pacman, apt): 827D EFD8 FDAD 5EE6 4080  5C30 904E B81A 1243 150F
```

Commands run as root.

### Fedora, RHEL, Rocky Linux, AlmaLinux (dnf)

```sh
curl -fsSL -o /etc/yum.repos.d/unofficial-repository-proxmox-backup-client.repo \
  https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/rpm/unofficial-repository-proxmox-backup-client.repo
dnf install proxmox-backup-client
```

### Arch Linux (pacman)

```sh
curl -fsSL -o /tmp/upc.asc https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/keys/unofficial-repository-proxmox-backup-client.asc
gpg --show-keys /tmp/upc.asc      # compare with the fingerprint above
pacman-key --add /tmp/upc.asc
pacman-key --lsign-key "$(gpg --with-colons --show-keys /tmp/upc.asc | awk -F: '/^fpr:/{print $10; exit}')"
printf '\n[unofficial-repository-proxmox-backup-client]\nServer = https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/arch/$arch\n' >> /etc/pacman.conf
pacman -Syu proxmox-backup-client
```

### Alpine Linux (apk)

```sh
wget -O /etc/apk/keys/unofficial-repository-proxmox-backup-client.rsa.pub \
  https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/keys/unofficial-repository-proxmox-backup-client.rsa.pub
echo "https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/alpine" >> /etc/apk/repositories
apk add proxmox-backup-client
```

### Debian, Ubuntu (apt)

The apt repository serves Proxmox's `.deb` unmodified (same SHA256 as upstream). On Debian,
Proxmox's own `pbs-client` repository is the official alternative.

```sh
install -d /etc/apt/keyrings
curl -fsSL -o /etc/apt/keyrings/unofficial-repository-proxmox-backup-client.asc https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/keys/unofficial-repository-proxmox-backup-client.asc
echo "deb [signed-by=/etc/apt/keyrings/unofficial-repository-proxmox-backup-client.asc] https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/deb stable main" \
  > /etc/apt/sources.list.d/unofficial-repository-proxmox-backup-client.list
apt update && apt install proxmox-backup-client-static
```

### Manual variant (no configuration file downloaded from us)

The commands above write a repository file fetched from our server. To fetch only the key, check its
fingerprint and write the configuration yourself — the repository then uses a **local** key:

```sh
curl -fsSL -o upc.asc https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/keys/unofficial-repository-proxmox-backup-client.asc
gpg --show-keys --with-fingerprint upc.asc
# must print: 827D EFD8 FDAD 5EE6 4080  5C30 904E B81A 1243 150F
```

`dnf`:

```sh
install -Dm644 upc.asc /etc/pki/rpm-gpg/RPM-GPG-KEY-unofficial-repository-proxmox-backup-client
cat > /etc/yum.repos.d/unofficial-repository-proxmox-backup-client.repo <<'EOF'
[unofficial-repository-proxmox-backup-client]
name=Unofficial proxmox-backup-client (RDEM Systems)
baseurl=https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/rpm/$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-unofficial-repository-proxmox-backup-client
EOF
dnf install proxmox-backup-client
```

`apt` (deb822):

```sh
install -Dm644 upc.asc /etc/apt/keyrings/unofficial-repository-proxmox-backup-client.asc
cat > /etc/apt/sources.list.d/unofficial-repository-proxmox-backup-client.sources <<'EOF'
Types: deb
URIs: https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/deb
Suites: stable
Components: main
Signed-By: /etc/apt/keyrings/unofficial-repository-proxmox-backup-client.asc
EOF
apt update && apt install proxmox-backup-client-static
```

`pacman` — import the key, then append the block to `/etc/pacman.conf`:

```sh
pacman-key --add upc.asc
pacman-key --lsign-key 827DEFD8FDAD5EE640805C30904EB81A1243150F
```

```ini
[unofficial-repository-proxmox-backup-client]
SigLevel = Required DatabaseRequired
Server = https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/arch/$arch
```

`apk` — the APK key is an RSA key, checked by its SHA256 against `keys/FINGERPRINTS.txt`:

```sh
wget -O upc.rsa.pub https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/keys/unofficial-repository-proxmox-backup-client.rsa.pub
sha256sum upc.rsa.pub
install -Dm644 upc.rsa.pub /etc/apk/keys/unofficial-repository-proxmox-backup-client.rsa.pub
echo "https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client/alpine" >> /etc/apk/repositories
```

### Then

Connect the client to a Proxmox Backup Server, encrypt, schedule and restore — step-by-step guide:
https://nimbus.rdem-systems.com/en/blog/proxmox-backup-client-linux/?utm_source=github&utm_medium=readme&utm_campaign=upc-repo

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
sign-manifest.sh    repo/SHA256SUMS of every file, detached OpenPGP signature
verify-release.sh   offline gate: every file signed, listed, matching index.json and SHA256SUMS, no symlink
publish.sh          force push of the tree to the "packages" branch of this repository
```

## How the web host picks a release up

The CI has no access to the web server. `server/pull-packages.sh` runs from cron on the web host:
it fetches the `packages` branch anonymously, checks `SHA256SUMS.asc` with a copy of the public
key kept on the host (fingerprint pinned in the script), refuses any file that is not listed or
does not match, any symlink or hidden file, and any release older than the one being served, then
switches a `current` symlink atomically. GitHub carries the files; it is not trusted.

Setup on the host, once:

```
mkdir -p /var/www/unofficial-repository-proxmox-backup-client
cd /var/www/unofficial-repository-proxmox-backup-client
curl -fsSLO https://raw.githubusercontent.com/rdemsystems/unofficial-proxmox-backup-client/main/server/pull-packages.sh
chmod +x pull-packages.sh
gpg --dearmor < signing-key.pub.asc > trusted.gpg   # check the fingerprint first
crontab: */10 * * * * /var/www/unofficial-repository-proxmox-backup-client/pull-packages.sh
```

The `packages` branch holds the packages themselves (over 100 MB). To read or audit the
scripts only: `git clone --single-branch https://github.com/rdemsystems/unofficial-proxmox-backup-client.git`.

The GitLab pipeline (`.gitlab-ci.yml`) runs `check-upstream` daily and only builds when
Proxmox has published a new version. Publishing is a manual job.

## CI setup

The GitLab project that runs the CI is private; it clones this repository at a pinned commit and
signs with keys kept in its own `secrets/` directory, which never comes here.

- **Signing keys**: read from the private project's `secrets/` directory (next to `public/`) by `scripts/lib.sh`
  (`UPC_GPG_KEY_FILE`, `UPC_APK_KEY_FILE` can override them for local runs).
- **Runners**: any Docker runner of the project; no tag.
- **Public signing key** (packages, repository metadata): published under `keys/` of every
  release. Fingerprint `827D EFD8 FDAD 5EE6 4080  5C30 904E B81A 1243 150F`.

## Local run

```
scripts/check-upstream.sh && scripts/fetch-upstream.sh
NFPM=/path/to/nfpm UPC_GPG_KEY_FILE=... UPC_APK_KEY_FILE=... scripts/package.sh
tests/packages-roundtrip.sh    # publish.sh + pull-packages.sh against a local bare repository: switch, tampering, rollback
```

## We are not the first

Other unofficial packaging efforts came before this one, maintained on volunteered time:

- [pbs-client](https://github.com/ciroiriarte/pbs-client) by Ciro Iriarte, on the
  [openSUSE Build Service](https://download.opensuse.org/repositories/home:/ciriarte:/pbs-client/):
  it **rebuilds the client from source** for openSUSE, Rocky Linux, Ubuntu and Debian, and also packages
  `pxar` and `proxmox-file-restore`. The opposite approach to ours, which recompiles nothing — and a
  complementary one, since it covers openSUSE and we do not.
- The [AUR](https://aur.archlinux.org/packages/proxmox-backup-client) for Arch Linux, and several
  [COPR](https://copr.fedorainfracloud.org/coprs/fulltext/?fulltext=proxmox-backup-client) projects for Fedora and RHEL.

What we do differently: the upstream check is daily and automated, every version passes the install tests
before it is published, and the metadata is signed. On 16 September 2026, upstream was at 4.2.5-1 while the
AUR and COPR packages above sat between 4.0.16 and 4.2.2 — a dated observation, not a criticism.

## Need somewhere to send those backups?

The client is only half the job: it needs a Proxmox Backup Server to write to. We run managed
PBS datastores, billed per usable TB, with a token that cannot delete — so a compromised machine
cannot erase its own backups. Options: two-site replication, offline disks, LTO tape.

**Find the plan that fits:** https://nimbus.rdem-systems.com/en/choose-backup/?utm_source=github&utm_medium=readme&utm_campaign=upc-repo

## Licenses

- Build scripts in this repository: MIT, see `LICENSE` (scope and trademark notice in `NOTICE`).
- Packaged software: GNU AGPL v3 or later, Copyright Proxmox Server Solutions GmbH. The
  corresponding source is published with every release under `source/`, taken from
  Proxmox's `proxmox-backup` repository (https://git.proxmox.com/?p=proxmox-backup.git).
