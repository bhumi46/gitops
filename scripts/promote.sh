#!/usr/bin/env bash
# Open a PR that deploys a version of a service to an environment (CLI alternative to Backstage
# "Deploy service"). Changes envs/<to>/<svc>/image.yaml (app version) and apps/<svc>-<to>.yaml
# (chart version); merging the PR is the approval.
#   scripts/promote.sh <svc> <to-env> [from-env=dev]               # copy what from-env runs
#   scripts/promote.sh <svc> <to-env> --version 0.2.0 [--chart 0.1.1] # specific versions
#   add --rollback to label the PR "rollback" (allows a lower version through pr-check)
set -euo pipefail
usage() { sed -n '2,9p' "$0" >&2; exit 2; }
SVC=${1:-}; TO=${2:-}; [ -n "$SVC" ] && [ -n "$TO" ] || usage; shift 2
FROM=dev VERSION="" CHART="" ROLLBACK=false
while [ $# -gt 0 ]; do
  case $1 in
    --version) VERSION=$2; shift 2;;
    --chart) CHART=$2; shift 2;;
    --rollback) ROLLBACK=true; shift;;
    -*) usage;;
    *) FROM=$1; shift;;
  esac
done
cd "$(dirname "$0")/.."
IMG="envs/$TO/$SVC/image.yaml"; APP="apps/$SVC-$TO.yaml"
[ -f "$IMG" ] && [ -f "$APP" ] || { echo "$SVC is not deployed to $TO ($IMG / $APP missing)" >&2; exit 1; }
chart_of() { yq '.spec.sources[] | select(.chart) | .targetRevision' "$1"; }
CUR_V=$(yq '.image.tag' "$IMG"); CUR_C=$(chart_of "$APP")
if [ -z "$VERSION" ]; then
  VERSION=$(yq '.image.tag' "envs/$FROM/$SVC/image.yaml"); CHART=$(chart_of "apps/$SVC-$FROM.yaml"); SOURCE="env $FROM"
else
  CHART=${CHART:-$CUR_C}; SOURCE="version $VERSION"
fi
[ "$VERSION" != "$CUR_V" ] || [ "$CHART" != "$CUR_C" ] || { echo "$TO already runs $SVC $VERSION (chart $CHART)"; exit 0; }

BRANCH="deploy/$TO/$SVC-$VERSION"
git fetch -q origin main && git switch -q -c "$BRANCH" origin/main
VERSION=$VERSION yq -i '.image.tag = strenv(VERSION)' "$IMG"
CHART=$CHART yq -i '(.spec.sources[] | select(.chart) | .targetRevision) = strenv(CHART)' "$APP"
git commit -q -m "$TO: $SVC $VERSION (chart $CHART)" "$IMG" "$APP"
git push -q -u origin "$BRANCH"
LABEL=(); $ROLLBACK && LABEL=(--label rollback)
gh pr create --base main --head "$BRANCH" "${LABEL[@]}" \
  --title "Deploy $SVC $VERSION to $TO" \
  --body "| | now | after merge |
|---|---|---|
| app (image) | \`$CUR_V\` | \`$VERSION\` |
| chart | \`$CUR_C\` | \`$CHART\` |

From $SOURCE. Merging this PR deploys it."
git switch -q main
