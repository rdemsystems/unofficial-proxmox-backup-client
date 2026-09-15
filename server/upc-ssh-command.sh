#!/bin/sh
# Forced command for the CI deploy key on the web host. Install as
# /usr/local/bin/upc-ssh-command and, in ~upc-deploy/.ssh/authorized_keys:
#   restrict,command="/usr/local/bin/upc-ssh-command /srv/unofficial-pbs-client" ssh-ed25519 AAAA... gitlab-ci@unofficial-pbs-client
# The key can do exactly two things:
#   1. receive an rsync upload into $BASE/releases/<id>/
#   2. "activate <id>": point $BASE/current at that release, keep the last $KEEP releases
#
# The remote command is attacker-controlled input. It is never re-executed as a string: the
# release id is validated character class by character class, the destination must be exactly the
# release directory, and the rsync argv is rebuilt from a closed allow-list of options.
set -eu
BASE=${1:-/srv/unofficial-pbs-client}   # set by the admin in authorized_keys, never by the client
KEEP=5
cmd=${SSH_ORIGINAL_COMMAND:-}

refuse() { echo "refused: $*" >&2; exit 1; }

# Release id as produced by scripts/publish.sh: YYYYmmddTHHMMSSZ-<alnum>, nothing else.
valid_id() {
  case "$1" in
    ????????T??????Z-*) ;;
    *) return 1 ;;
  esac
  case "$1" in
    *[!0-9A-Za-z-]*) return 1 ;;          # no dot, no slash, no shell metacharacter
  esac
  [ ${#1} -le 64 ] || return 1
  return 0
}

case "$cmd" in
  "activate "*)
    id=${cmd#activate }
    valid_id "$id" || refuse "bad release id"
    [ -d "$BASE/releases/$id" ] || refuse "no such release"
    [ ! -L "$BASE/releases/$id" ] || refuse "release is a symlink"
    # Atomic switch: a fresh link in the same directory, renamed over the old one.
    ln -sfn "releases/$id" "$BASE/.current.$id"
    mv -Tf "$BASE/.current.$id" "$BASE/current"
    # Prune: only well-formed release directories, never the one just activated.
    for path in "$BASE"/releases/*; do
      old=${path##*/}
      [ -d "$path" ] || continue
      valid_id "$old" || continue          # anything unexpected is left alone, on purpose
      [ "$old" != "$id" ] || continue
      echo "$old"
    done | sort | head -n "-$KEEP" | while read -r old; do
      valid_id "$old" && rm -rf -- "${BASE:?}/releases/$old"
    done
    echo "current -> releases/$id"
    ;;

  "rsync --server "*)
    # Parse the argv word by word; the last two tokens must be "." and the release directory.
    # shellcheck disable=SC2086  # word splitting IS the parsing step here
    set -- $cmd
    [ $# -ge 4 ] || refuse "short rsync command"
    dest=""; dot=""                        # assigned by the evals below
    eval "dest=\${$#}"
    prev=$(( $# - 1 ))
    eval "dot=\${$prev}"
    [ "$dot" = "." ] || refuse "unexpected rsync source"
    case "$dest" in
      "$BASE"/releases/*/) id=${dest#"$BASE"/releases/}; id=${id%/} ;;
      *) refuse "destination outside releases/" ;;
    esac
    valid_id "$id" || refuse "bad release id in destination"
    [ ! -e "$BASE/releases/$id" ] || refuse "release already exists"

    args="rsync --server"
    i=3                                    # skip "rsync" and "--server"
    while [ "$i" -lt "$prev" ]; do
      # shellcheck disable=SC2154  # assigned by the eval just above each use
      eval "a=\${$i}"
      case "$a" in
        --sender) refuse "download attempt" ;;
        -[a-zA-Z.]*) ;;                    # the option block rsync sends, e.g. -logDtpre.iLsfxC
        --delete|--delete-delay|--numeric-ids|--compress) ;;
        --link-dest|--link-dest=*)         # rsync sends the value as a separate word
          if [ "$a" = "--link-dest" ]; then
            i=$(( i + 1 ))
            [ "$i" -lt "$prev" ] || refuse "link-dest without value"
            eval "v=\${$i}"
            args="$args $a"
            a="$v"
          else
            v=${a#--link-dest=}
          fi
          case "$v" in
            "$BASE"/current/|"$BASE"/current) ;;
            *) refuse "link-dest outside current/" ;;
          esac ;;
        *) refuse "rsync option not allowed: $a" ;;
      esac
      args="$args $a"
      i=$(( i + 1 ))
    done
    # shellcheck disable=SC2086  # argv rebuilt from the allow-list above
    exec $args . "$BASE/releases/$id/"
    ;;

  *) refuse "$cmd" ;;
esac
