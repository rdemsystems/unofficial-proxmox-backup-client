#!/bin/sh
# Install the client from the freshly built repository exactly as a user would (signed
# metadata, no --allow-untrusted, no --nogpgcheck), then smoke-test it.
# POSIX sh on purpose: Alpine images have no bash. Run as root in a throwaway container.
#
#   scripts/test-install.sh rpm|arch|alpine|deb
#
# Optional real backup + restore against a test datastore:
#   TEST_PBS_REPOSITORY  e.g. ci@pbs!ci@pbs.example.com:store
#   TEST_PBS_PASSWORD    API token secret
#   TEST_PBS_FINGERPRINT only for a self-signed test server
set -eu

family=${1:?usage: $0 rpm|arch|alpine|deb}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REPO="$ROOT/repo"
ID=unofficial-pbs-client

case "$family" in
  rpm)
    rpm --import "$REPO/keys/$ID.asc"
    cat > "/etc/yum.repos.d/$ID.repo" <<EOF
[$ID]
name=$ID (CI)
baseurl=file://$REPO/rpm/\$basearch
gpgcheck=1
repo_gpgcheck=1
gpgkey=file://$REPO/keys/$ID.asc
EOF
    dnf -y -q install proxmox-backup-client
    ;;
  arch)
    pacman-key --init >/dev/null 2>&1
    pacman-key --add "$REPO/keys/$ID.asc" >/dev/null 2>&1
    fpr=$(GNUPGHOME=$(mktemp -d) gpg --batch --with-colons --show-keys "$REPO/keys/$ID.asc" | awk -F: '/^fpr:/{print $10; exit}')
    pacman-key --lsign-key "$fpr" >/dev/null 2>&1
    # shellcheck disable=SC2016  # $arch is for pacman, not for the shell
    printf '\n[%s]\nSigLevel = Required\nServer = file://%s/arch/$arch\n' "$ID" "$REPO" >> /etc/pacman.conf
    pacman -Sy --noconfirm --needed proxmox-backup-client
    ;;
  alpine)
    cp "$REPO/keys/$ID.rsa.pub" /etc/apk/keys/
    echo "$REPO/alpine" >> /etc/apk/repositories
    apk add --no-progress proxmox-backup-client
    ;;
  deb)
    install -d /etc/apt/keyrings
    cp "$REPO/keys/$ID.asc" "/etc/apt/keyrings/$ID.asc"
    echo "deb [signed-by=/etc/apt/keyrings/$ID.asc] file:$REPO/deb stable main" > "/etc/apt/sources.list.d/$ID.list"
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq proxmox-backup-client-static
    ;;
  *) echo "unknown family: $family" >&2; exit 2 ;;
esac

proxmox-backup-client version | grep "client version: "

# A valid public certificate must be accepted without a fingerprint: this is what the
# /usr/lib/ssl symlinks are for. The probe must PROVE the handshake happened, so we require the
# server's own answer: anything else (DNS failure, timeout, connection refused, unknown error)
# fails the test instead of passing it silently.
out=$(PBS_PASSWORD=x PBS_REPOSITORY="probe@pbs@${TLS_PROBE_HOST:-nimbus.rdem-systems.com}:443:store" \
      timeout 30 proxmox-backup-client snapshot list 2>&1 || true)
case "$out" in
  *"certificate validation failed"*|*"fingerprint was not confirmed"*)
    echo "TLS probe FAILED (certificate refused): $out" >&2; exit 1 ;;
  *"<!DOCTYPE html"*|*"authentication failed"*|*"permission check failed"*|*"401 Unauthorized"*|*"<html"*)
    echo "TLS probe OK (valid certificate accepted without fingerprint, server answered)" ;;
  *)
    echo "TLS probe INCONCLUSIVE — the server never answered, so nothing was proven: $out" >&2
    exit 1 ;;
esac

if [ -n "${TEST_PBS_REPOSITORY:-}" ]; then
  export PBS_REPOSITORY="$TEST_PBS_REPOSITORY" PBS_PASSWORD="$TEST_PBS_PASSWORD"
  [ -n "${TEST_PBS_FINGERPRINT:-}" ] && export PBS_FINGERPRINT="$TEST_PBS_FINGERPRINT"
  id="ci-$family-${CI_JOB_ID:-local}"
  mkdir -p /tmp/upc-src /tmp/upc-restore
  date -u > /tmp/upc-src/stamp
  cp /etc/os-release /tmp/upc-src/
  proxmox-backup-client backup "src.pxar:/tmp/upc-src" --backup-id "$id"
  proxmox-backup-client restore "host/$id" src.pxar /tmp/upc-restore
  [ "$(cat /tmp/upc-src/stamp)" = "$(cat /tmp/upc-restore/stamp)" ]
  echo "backup + restore OK ($id)"
fi
