#!/usr/bin/env bash
# Local end-to-end check of publish.sh + server/upc-ssh-command.sh without a real server:
# a fake "ssh" on PATH hands the remote command to the forced-command script, exactly as
# sshd would (SSH_ORIGINAL_COMMAND). Needs a built repo/ with index.json.
#   tests/publish-roundtrip.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
work=$(mktemp -d)
base="$work/srv"
mkdir -p "$base/releases" "$work/bin"

cat > "$work/bin/ssh" <<EOF
#!/bin/sh
# Drop ssh options (-i X, -o X, -l user...), then the host; the rest is the remote command.
while [ \$# -gt 0 ]; do
  case "\$1" in -i|-o|-l|-p) shift 2 ;; -*) shift ;; *) break ;; esac
done
shift                       # host
SSH_ORIGINAL_COMMAND="\$*" exec "$ROOT/server/upc-ssh-command.sh" "$base"
EOF
chmod +x "$work/bin/ssh"
touch "$work/key" "$work/known_hosts"

run_publish() {
  PATH="$work/bin:$PATH" MAINTAINER="Test <test@example.invalid>" \
  UPC_DEPLOY_TARGET=test@localhost UPC_DEPLOY_SSH_KEY="$work/key" \
  UPC_DEPLOY_KNOWN_HOSTS="$work/known_hosts" UPC_DEPLOY_PATH="$base" \
  "$ROOT/scripts/publish.sh"
}

run_publish
first=$(readlink "$base/current")
sleep 1.1                   # release ids have one-second resolution
run_publish
second=$(readlink "$base/current")
[[ "$first" != "$second" ]] || { echo "FAIL: current did not move"; exit 1; }

# Unchanged files must be hard links between releases (--link-dest).
f=$(cd "$base/current" && find . -name '*.deb' | head -n1)
[[ "$(stat -c %i "$base/$first/$f")" == "$(stat -c %i "$base/$second/$f")" ]] \
  || { echo "FAIL: $f was copied, not hard-linked"; exit 1; }

# The forced command must refuse anything else.
for bad in \
  "ls /" \
  "rsync --server --sender . /etc/" \
  "activate ../../etc" \
  "activate $first/../../etc" \
  "rsync --server . $base/releases/x/;id" \
  "rsync --server -logDtpre.iLsfxC --rsh=sh . $base/releases/20260101T000000Z-x/" \
  "rsync --server -logDtpre.iLsfxC --link-dest /etc . $base/releases/20260101T000000Z-x/" \
  "rsync --server -logDtpre.iLsfxC . /etc/" \
  "rsync --server -logDtpre.iLsfxC . $base/releases/20260101T000000Z-x/../../etc/" \
  "rsync --server -logDtpre.iLsfxC . $base/releases/$second/" ; do
  if SSH_ORIGINAL_COMMAND="$bad" "$ROOT/server/upc-ssh-command.sh" "$base" 2>/dev/null; then
    echo "FAIL: accepted: $bad"; exit 1
  fi
done

echo "OK: two releases, atomic switch ($first -> $second), hard links, forced command refuses the rest"
rm -rf "$work"
