#!/usr/bin/env bash
# Policy for deploy changes in a PR (only values that change are judged) (run by .github/workflows/pr-check.yml):
#   1. staging/prod run final releases only: image.tag and chart targetRevision must be X.Y.Z
#      (no -dev / -rc pre-releases, no commit SHAs).
#   2. no downgrades: a changed image.tag or targetRevision must be >= the one on the base branch,
#      unless ALLOW_ROLLBACK=true (PR label "rollback").
# Usage: scripts/check-policy.sh <base-ref> <semver-compare>
set -euo pipefail
BASE=${1:?base ref}; CMP=${2:?path to semver-compare}
FINAL='^[0-9]+\.[0-9]+\.[0-9]+$'
RELEASE_ONLY_ENVS=${RELEASE_ONLY_ENVS:-"staging prod"}
fail=0
err() { echo "::error file=$1::$2"; fail=1; }

check() { # check <file> <env> <what> <new> <old>
  local file=$1 env=$2 what=$3 new=$4 old=$5
  # The policy is about deploys: a value that didn't change (e.g. moved between files) is not judged.
  [ "$new" = "$old" ] && return 0
  for e in $RELEASE_ONLY_ENVS; do
    if [ "$env" = "$e" ] && ! [[ $new =~ $FINAL ]]; then
      err "$file" "$env only runs final releases: $what '$new' is not X.Y.Z (promote a released version, e.g. from qa after the release is merged to main)"
    fi
  done
  if [ -n "$old" ] && [ "$old" != "$new" ]; then
    c=$("$CMP" "$new" "$old" 2>/dev/null || echo 1)   # old commit SHAs (pre-versioning) count as older
    if [ "$c" = -1 ] && [ "${ALLOW_ROLLBACK:-false}" != true ]; then
      err "$file" "$what goes backwards in $env ($old -> $new). Add the label 'rollback' if this is intended."
    fi
  fi
}

while IFS= read -r f; do
  [ -f "$f" ] || continue
  case $f in
    envs/*/*/image.yaml)
      env=$(cut -d/ -f2 <<<"$f")
      new=$(yq '.image.tag' "$f"); old=$(git show "$BASE:$f" 2>/dev/null | yq '.image.tag' 2>/dev/null || true)
      # Before the image.yaml split the tag lived in values.yaml.
      if [ -z "$old" ] || [ "$old" = null ]; then
        old=$(git show "$BASE:${f%image.yaml}values.yaml" 2>/dev/null | yq '.image.tag' 2>/dev/null || true)
      fi
      [ "$old" = null ] && old=""
      check "$f" "$env" "app version (image.tag)" "$new" "$old";;
    apps/*.yaml)
      [ "$(yq '.kind' "$f")" = Application ] || continue
      env=$(yq '.spec.destination.namespace' "$f")
      new=$(yq '.spec.sources[] | select(.chart) | .targetRevision' "$f")
      [ -z "$new" ] && continue
      old=$(git show "$BASE:$f" 2>/dev/null | yq '.spec.sources[] | select(.chart) | .targetRevision' 2>/dev/null || true)
      check "$f" "$env" "chart version (targetRevision)" "$new" "$old";;
  esac
done < <(git diff --name-only "$BASE"...HEAD)

[ $fail -eq 0 ] && echo "policy ok"
exit $fail
