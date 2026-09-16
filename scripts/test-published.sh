#!/bin/sh
# Run the published install instructions, verbatim, against the live repository.
# Unlike test-install.sh (which installs from the repo/ tree built in the pipeline), this checks
# what a reader of the web page or of the README actually types: the real URLs, the real TLS
# certificate, the real files served by the web host.
#   scripts/test-published.sh rpm|arch|alpine|deb
# UPC_PUBLIC_URL overrides the base URL (default: the production repository).
set -eu

family=${1:?usage: $0 rpm|arch|alpine|deb}
URL=${UPC_PUBLIC_URL:-https://nimbus.rdem-systems.com/unofficial-repository-proxmox-backup-client}
FPR_GROUPED="827D EFD8 FDAD 5EE6 4080  5C30 904E B81A 1243 150F"
FPR=$(echo "$FPR_GROUPED" | tr -d ' ')

case "$family" in
  rpm)
    if command -v dnf >/dev/null 2>&1; then pm=dnf; else pm=yum; fi
    curl -fsSL -o /etc/yum.repos.d/unofficial-repository-proxmox-backup-client.repo \
      "$URL/rpm/unofficial-repository-proxmox-backup-client.repo"
    $pm -y install proxmox-backup-client
    ;;
  arch)
    pacman -Sy --noconfirm --needed curl gnupg >/dev/null
    curl -fsSL -o /tmp/upc.asc "$URL/keys/unofficial-repository-proxmox-backup-client.asc"
    gpg --show-keys /tmp/upc.asc
    pacman-key --init >/dev/null 2>&1 || true
    pacman-key --populate archlinux >/dev/null 2>&1 || true
    pacman-key --add /tmp/upc.asc
    pacman-key --lsign-key "$(gpg --with-colons --show-keys /tmp/upc.asc | awk -F: '/^fpr:/{print $10; exit}')"
    # shellcheck disable=SC2016  # $arch is pacman's own variable, it must stay literal
    printf '\n[unofficial-repository-proxmox-backup-client]\nServer = %s/arch/$arch\n' "$URL" >> /etc/pacman.conf
    pacman -Syu --noconfirm proxmox-backup-client
    ;;
  alpine)
    apk add --no-cache curl >/dev/null
    wget -q -O /etc/apk/keys/unofficial-repository-proxmox-backup-client.rsa.pub \
      "$URL/keys/unofficial-repository-proxmox-backup-client.rsa.pub"
    echo "$URL/alpine" >> /etc/apk/repositories
    apk update >/dev/null
    apk add proxmox-backup-client
    ;;
  deb)
    install -d /etc/apt/keyrings
    curl -fsSL -o /etc/apt/keyrings/unofficial-repository-proxmox-backup-client.asc \
      "$URL/keys/unofficial-repository-proxmox-backup-client.asc"
    echo "deb [signed-by=/etc/apt/keyrings/unofficial-repository-proxmox-backup-client.asc] $URL/deb stable main" \
      > /etc/apt/sources.list.d/unofficial-repository-proxmox-backup-client.list
    apt-get update -qq
    apt-get install -y -qq proxmox-backup-client-static
    ;;
  *) echo "unknown family: $family" >&2; exit 2 ;;
esac

# The client runs, and the fingerprint the reader is told to compare is the one actually served.
proxmox-backup-client version | grep "client version: "
curl -fsS "$URL/keys/FINGERPRINTS.txt" | grep -F "$FPR" >/dev/null \
  || { echo "published FINGERPRINTS.txt does not carry $FPR" >&2; exit 1; }

# TLS against a real certificate: the whole point of the two certificate symlinks. The probe must
# PROVE the handshake happened: only the server's own answer passes (same rule as test-install.sh).
out=$(PBS_PASSWORD=x PBS_REPOSITORY="probe@pbs@${TLS_PROBE_HOST:-nimbus.rdem-systems.com}:443:store" \
      timeout 30 proxmox-backup-client snapshot list 2>&1 || true)
case "$out" in
  *"certificate validation failed"*|*"fingerprint was not confirmed"*)
    echo "TLS probe FAILED (certificate refused): $out" >&2; exit 1 ;;
  *"<!DOCTYPE html"*|*"authentication failed"*|*"permission check failed"*|*"401 Unauthorized"*|*"<html"*)
    echo "OK $family: installed from $URL, valid certificate accepted without fingerprint" ;;
  *)
    echo "TLS probe INCONCLUSIVE — the server never answered, so nothing was proven: $out" >&2
    exit 1 ;;
esac
