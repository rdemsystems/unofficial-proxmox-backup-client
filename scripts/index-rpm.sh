#!/usr/bin/env bash
# Signed dnf/yum repository metadata, one per architecture, plus the .repo file users download.
# Runs on Fedora. Needs: createrepo_c, rpm, gpg, UPC_GPG_KEY_FILE, repo/keys/ from export-keys.sh.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

gpg_setup
pub="$REPO/keys/$REPO_ID.asc"
[[ -s "$pub" ]] || die "missing $pub (run export-keys.sh)"

# Refuse to index a package whose signature does not verify against our public key.
rpm --import "$pub"
for rpmfile in "$REPO"/rpm/*/*.rpm; do
  rpm -K "$rpmfile" | grep -qiE 'digests signatures OK|pgp.*OK|signatures OK' \
    || die "$(basename "$rpmfile"): signature does not verify"
done

for dir in "$REPO"/rpm/*/; do
  rm -rf "$dir/repodata"
  # gzip metadata: readable by every dnf/yum still in service (EL8 included).
  createrepo_c --quiet --general-compress-type=gz "$dir"
  "${GPG_SIGN[@]}" --armor --detach-sign -o "$dir/repodata/repomd.xml.asc" "$dir/repodata/repomd.xml"
  log "signed ${dir#"$REPO/"}repodata"
done

cat > "$REPO/rpm/$REPO_ID.repo" <<EOF
# Unofficial proxmox-backup-client packages - not affiliated with Proxmox Server Solutions GmbH.
# $PUBLIC_BASE_URL/
[$REPO_ID]
name=Unofficial proxmox-backup-client (RDEM Systems)
baseurl=$PUBLIC_BASE_URL/rpm/\$basearch
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=$PUBLIC_BASE_URL/keys/$REPO_ID.asc
EOF
