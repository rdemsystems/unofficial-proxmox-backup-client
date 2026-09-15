#!/usr/bin/env bash
# Signed pacman repository. nfpm does not sign Arch packages, so each package gets a detached
# .sig here (repo-add embeds it in the database), then the database itself is signed.
# Runs on Arch Linux. Needs: repo-add (pacman), gpg, UPC_GPG_KEY_FILE.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

gpg_setup
# On ne signe QUE les paquets construits par ce pipeline (build/manifest-new.jsonl). Un paquet
# repris du serveur arrive avec sa signature ; le re-signer reviendrait à authentifier un fichier
# qu'on n'a pas fabriqué, et transformerait une compromission du serveur en paquet valide.
for dir in "$REPO"/arch/*/; do
  for pkg in "$dir"*.pkg.tar.zst; do
    rel="${pkg#"$REPO/"}"
    if jq -e --arg f "$rel" 'select(.file == $f)' "$BUILD/manifest-new.jsonl" >/dev/null 2>&1; then
      [[ -s "$pkg.sig" ]] || "${GPG_SIGN[@]}" --detach-sign --no-armor -o "$pkg.sig" "$pkg"
    else
      [[ -s "$pkg.sig" ]] || die "$rel vient du dépôt publié et n'a pas de signature : refus de la signer"
    fi
  done
  rm -f "$dir$REPO_ID".{db,files}{,.tar.gz,.sig,.tar.gz.sig}
  repo-add --quiet "$dir$REPO_ID.db.tar.gz" "$dir"*.pkg.tar.zst
  # repo-add leaves symlinks (.db -> .db.tar.gz); publish plain files instead.
  for db in db files; do
    rm -f "$dir$REPO_ID.$db"
    cp "$dir$REPO_ID.$db.tar.gz" "$dir$REPO_ID.$db"
    "${GPG_SIGN[@]}" --detach-sign --no-armor -o "$dir$REPO_ID.$db.sig" "$dir$REPO_ID.$db"
    cp "$dir$REPO_ID.$db.sig" "$dir$REPO_ID.$db.tar.gz.sig"
  done
  log "signed ${dir#"$REPO/"}$REPO_ID.db"
done
