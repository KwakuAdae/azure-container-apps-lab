#!/usr/bin/env bash
# Step 4: release a new version as a NEW REVISION with 0% of production traffic and a
# "green" label, so you can test it on its own URL first (blue/green).
#   ./scripts/04-release.sh v2 v1        # new tag, tag that keeps production traffic
source "$(dirname "$0")/config.sh"
NEW="${1:?usage: $0 <new-tag> <current-tag>}"
STABLE="${2:?usage: $0 <new-tag> <current-tag>}"
shift 2

step "terraform apply: create website--${NEW} (0%), website--${STABLE} keeps 100%"
apply_app "$NEW" "[{tag=\"${STABLE}\", percent=100}, {tag=\"${NEW}\", percent=0, label=\"green\"}]" "$@"

echo ""
echo "✅ website--${NEW} is live on its test URL only:"
echo "   $(terraform -chdir="$APP_DIR" output -json label_urls | python3 -c 'import json,sys; print(json.load(sys.stdin)["green"])')"
echo "   Production ($(app_out app_url)) still serves ${STABLE}."
echo "   When happy:  ./scripts/05-shift-traffic.sh ${STABLE} 20   (then 50, then 100)"
