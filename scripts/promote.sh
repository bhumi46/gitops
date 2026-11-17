#!/usr/bin/env bash
# Promote a service's dev image tag to another env by opening a PR.
# usage: scripts/promote.sh <svc> [target-env=staging]
set -euo pipefail
SVC=${1:?usage: $0 <svc> [target-env]}
TARGET=${2:-staging}
cd "$(dirname "$0")/.."
TAG=$(yq '.image.tag' "envs/dev/$SVC/values.yaml")
FILE="envs/$TARGET/$SVC/values.yaml"
[ -f "$FILE" ] || { echo "$FILE not found" >&2; exit 1; }
[ "$(yq '.image.tag' "$FILE")" != "$TAG" ] || { echo "$SVC already at ${TAG:0:7} in $TARGET"; exit 0; }

BRANCH="promote/$SVC-$TARGET-${TAG:0:7}"
git fetch -q origin main && git switch -q -c "$BRANCH" origin/main
TAG=$TAG yq -i '.image.tag = strenv(TAG)' "$FILE"
git commit -q -m "$TARGET: $SVC image.tag -> ${TAG:0:7}" "$FILE"
git push -q -u origin "$BRANCH"
gh pr create --base main --head "$BRANCH" \
  --title "Promote $SVC ${TAG:0:7} to $TARGET" \
  --body "Copies \`image.tag\` from \`envs/dev/$SVC\` to \`envs/$TARGET/$SVC\`."
git switch -q main
