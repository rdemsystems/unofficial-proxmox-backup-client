#!/usr/bin/env bash
# Upload repo/ as a new release directory on the web host, then switch the "current" symlink
# atomically (clients never see half-written metadata). Unchanged files are hard-linked from
# the previous release. The server side is restricted by server/upc-ssh-command.sh.
#
#   UPC_DEPLOY_TARGET        user@host
#   UPC_DEPLOY_SSH_KEY       private key file (forced command on the server)
#   UPC_DEPLOY_KNOWN_HOSTS   known_hosts file pinning the host key
#   UPC_DEPLOY_PATH          default /srv/unofficial-pbs-client
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

[[ "$MAINTAINER" != *TODO* ]] || die "set a real MAINTAINER in config.env before publishing"
for f in index.json "keys/$REPO_ID.asc" "keys/$APK_KEY_NAME" keys/FINGERPRINTS.txt; do
  [[ -s "$REPO/$f" ]] || die "repo/$f is missing"
done
: "${UPC_DEPLOY_TARGET:?}" "${UPC_DEPLOY_SSH_KEY:?}" "${UPC_DEPLOY_KNOWN_HOSTS:?}"
base="${UPC_DEPLOY_PATH:-/srv/unofficial-pbs-client}"
# Une seconde ne suffit pas a garantir l'unicite : on ajoute le pipeline/job CI, ou un nonce.
suffix="${CI_PIPELINE_ID:-local}-${CI_JOB_ID:-$RANDOM}"
release="$(date -u +%Y%m%dT%H%M%SZ)-${suffix//[^A-Za-z0-9]/}"

chmod 600 "$UPC_DEPLOY_SSH_KEY"
ssh_cmd="ssh -i $UPC_DEPLOY_SSH_KEY -o IdentitiesOnly=yes -o UserKnownHostsFile=$UPC_DEPLOY_KNOWN_HOSTS -o StrictHostKeyChecking=yes"

rsync -a --delete --link-dest="$base/current/" -e "$ssh_cmd" "$REPO/" "$UPC_DEPLOY_TARGET:$base/releases/$release/"
$ssh_cmd "$UPC_DEPLOY_TARGET" "activate $release"
log "published release $release ($(jq -c .latest "$REPO/index.json"))"
