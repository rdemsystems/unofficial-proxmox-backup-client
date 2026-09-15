#!/usr/bin/env bash
# Print the child pipeline for the "release" trigger job: the full release when
# check-upstream.sh found something new, a single no-op job otherwise.
# (GitLab evaluates rules before any job runs, hence a generated child pipeline.)
# public/ is its own Git repository (github.com/rdemsystems/unofficial-pbs-client), cloned by the
# parent pipeline: the child pipeline is ci/release.yml itself, pinned to that exact commit.
# shellcheck source=lib.sh
. "$(dirname "$0")/lib.sh"

if [[ "$(cat "$BUILD/decision" 2>/dev/null)" == release ]]; then
  sha=$(git -C "$ROOT" rev-parse HEAD)
  [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || die "public/ is not a git checkout"
  echo "# upstream: $(tr '\n' ' ' < "$BUILD/upstream.env")"
  echo "# public/ commit: $sha"
  sed "s/__PUBLIC_SHA__/$sha/g" "$ROOT/ci/release.yml"
else
  cat <<'EOF'
up-to-date:
  image: alpine:3.22
  script:
    - echo "Published repository already has the newest upstream version."
EOF
fi
