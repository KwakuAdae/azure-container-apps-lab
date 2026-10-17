#!/usr/bin/env bash
# Step 5: move production traffic from the stable revision to the newest one.
# The newest tag is read from Terraform (the image_tag of the last apply).
#   ./scripts/05-shift-traffic.sh v1 20    # canary: 20% newest, 80% v1
#   ./scripts/05-shift-traffic.sh v1 100   # cut over
#   ./scripts/05-shift-traffic.sh v1 0     # roll back: everything to v1 again
source "$(dirname "$0")/config.sh"
STABLE="${1:?usage: $0 <stable-tag> <percent-to-newest>}"
PERCENT="${2:?usage: $0 <stable-tag> <percent-to-newest>}"
shift 2
NEW="$(app_out image_tag)"

if [[ "$NEW" == "$STABLE" ]]; then
  echo "❌ ${STABLE} is already the newest revision. Release a new tag first: ./scripts/04-release.sh <tag> ${STABLE}" >&2
  exit 1
fi

if (( PERCENT >= 100 )); then
  TRAFFIC="[{tag=\"${NEW}\", percent=100, label=\"green\"}]"
else
  TRAFFIC="[{tag=\"${STABLE}\", percent=$((100 - PERCENT))}, {tag=\"${NEW}\", percent=${PERCENT}, label=\"green\"}]"
fi

step "terraform apply: ${PERCENT}% → website--${NEW}, $((100 - PERCENT))% → website--${STABLE}"
apply_app "$NEW" "$TRAFFIC" "$@"

echo ""
echo "Check the split:  ./scripts/06-watch-versions.sh 40"
