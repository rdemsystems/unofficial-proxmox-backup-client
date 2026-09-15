#!/usr/bin/env bash
# Push the verified repo/ tree to the "packages" branch of the GitHub repository.
# The web host pulls that branch (server/pull-packages.sh), checks the signed SHA256SUMS with a
# key it keeps itself, and switches atomically. GitHub carries the files; it is not trusted.
#
# The branch holds a single commit, replaced at each release (force push): keeping the history
# would put every old package in every clone. The published branch is fetched first, so files
# that did not change are not uploaded again.
#
#   UPC_PACKAGES_REMOTE   default git@github.com:rdemsystems/unofficial-proxmox-backup-client.git
#   UPC_PACKAGES_BRANCH   default packages
#   UPC_DEPLOY_SSH_KEY    default ../secrets/github-deploy-ecdsa (GitHub deploy key, write access)
#   UPC_KNOWN_HOSTS       default ../tools/github-known-hosts
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

[[ "$MAINTAINER" != *TODO* ]] || die "set a real MAINTAINER in config.env before publishing"
for f in index.json SHA256SUMS SHA256SUMS.asc "keys/$REPO_ID.asc" "keys/$APK_KEY_NAME" keys/FINGERPRINTS.txt; do
  [[ -s "$REPO/$f" ]] || die "repo/$f is missing"
done
remote="${UPC_PACKAGES_REMOTE:-git@github.com:rdemsystems/unofficial-proxmox-backup-client.git}"
branch="${UPC_PACKAGES_BRANCH:-packages}"
generated=$(jq -r .generated "$REPO/index.json")

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
if [[ "$remote" == *@*:* || "$remote" == ssh://* ]]; then
  key="${UPC_DEPLOY_SSH_KEY:-$ROOT/../secrets/github-deploy-ecdsa}"
  known="${UPC_KNOWN_HOSTS:-$ROOT/../tools/github-known-hosts}"
  [[ -s "$key" && -s "$known" ]] || die "deploy key or known_hosts missing ($key, $known)"
  install -m 600 "$key" "$work/key"          # a checked-out key may be group-readable: ssh refuses it
  export GIT_SSH_COMMAND="ssh -i $work/key -o IdentitiesOnly=yes -o UserKnownHostsFile=$known -o StrictHostKeyChecking=yes"
fi

tree="$work/tree"
git -c init.defaultBranch="$branch" init -q "$tree"
lease="--force-with-lease=refs/heads/$branch:"   # empty value: the branch must not exist yet
if git -C "$tree" fetch -q --depth 1 "$remote" "+refs/heads/$branch:refs/remotes/published/$branch" 2>/dev/null; then
  lease="--force-with-lease=refs/heads/$branch:$(git -C "$tree" rev-parse "refs/remotes/published/$branch")"
else
  log "no $branch branch published yet"
fi

cp -a "$REPO/." "$tree/"
cat > "$tree/README.md" <<EOF
# Packages branch — generated, do not edit

This branch is the signed package repository built from the [main branch](../../tree/main),
replaced by the release pipeline at each release. It is served under
<$PUBLIC_BASE_URL/> (install instructions: <https://nimbus.rdem-systems.com/en/unofficial-repository-proxmox-backup-client/>).

Check a copy with \`SHA256SUMS\` and its signature \`SHA256SUMS.asc\`
(OpenPGP key \`$SIGNING_KEY_FPR\`).

Release generated $generated.
EOF

name="${MAINTAINER% <*}"; email="${MAINTAINER##*<}"; email="${email%>}"
git -C "$tree" add -A
git -C "$tree" -c user.name="$name" -c user.email="$email" commit -q \
  -m "Release $generated" -m "latest: $(jq -c .latest "$REPO/index.json")"
git -C "$tree" push -q "$lease" "$remote" "HEAD:refs/heads/$branch"
log "published $(git -C "$tree" rev-parse HEAD) to $branch ($(jq -c .latest "$REPO/index.json"))"
