#!/bin/sh
# Make apt usable in CI containers of releases whose repositories moved (end of life), then
# install ca-certificates (the TLS probe of test-install.sh needs a CA bundle).
# POSIX sh: runs before anything else in debian:* and ubuntu:* images.
#   Debian 10 and older      -> archive.debian.org (signatures still checked; only the expired
#                               Valid-Until of an archived release is accepted)
#   Debian with a broken     -> retry without the -security suite (its mirror can lag behind)
#   security mirror
#   Ubuntu past end of life  -> old-releases.ubuntu.com
set -eu
. /etc/os-release
codename=${VERSION_CODENAME:-}

try_install() {
  apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends ca-certificates >/dev/null
}

sources_files=$(ls /etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources 2>/dev/null || true)

case "$ID:$codename" in
  debian:stretch|debian:buster)
    rm -f /etc/apt/sources.list.d/*
    printf 'deb http://archive.debian.org/debian %s main\ndeb http://archive.debian.org/debian-security %s/updates main\n' \
      "$codename" "$codename" > /etc/apt/sources.list
    echo 'Acquire::Check-Valid-Until "false";' > /etc/apt/apt.conf.d/99archived-release
    ;;
esac

if try_install; then exit 0; fi

case "$ID" in
  debian)
    echo ">> apt failed; retrying without the -security suite" >&2
    # shellcheck disable=SC2086
    sed -i '/security/d' $sources_files 2>/dev/null || true
    ;;
  ubuntu)
    echo ">> apt failed; switching to old-releases.ubuntu.com (release past end of life)" >&2
    # shellcheck disable=SC2086
    sed -i -E 's#https?://(archive|security|[a-z]{2}\.archive)\.ubuntu\.com#http://old-releases.ubuntu.com#g' $sources_files 2>/dev/null || true
    ;;
esac
try_install
