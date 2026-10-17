#!/usr/bin/env bash
# Send concurrent traffic and watch the HTTP scale rule add replicas (and later remove them, down to 0).
#   ./scripts/07-load-test.sh [seconds] [parallel]
source "$(dirname "$0")/config.sh"
SECS="${1:-120}"; PAR="${2:-60}"
APP_URL="$(app_out app_url)"
APP="$(app_out app_name)"
RG="$(app_out resource_group_name)"
REVISION="$(app_out latest_revision_name)"

step "Sending traffic to ${APP_URL} for ${SECS}s with ${PAR} parallel workers"
END=$(( $(date +%s) + SECS ))
for _ in $(seq "$PAR"); do
  ( while [ "$(date +%s)" -lt "$END" ]; do curl -s -o /dev/null "$APP_URL/"; done ) &
done

while [ "$(date +%s)" -lt "$END" ]; do
  N=$(az containerapp replica list -n "$APP" -g "$RG" --revision "$REVISION" --query "length(@)" -o tsv 2>/dev/null || echo "?")
  echo "$(date +%H:%M:%S)  replicas of ${REVISION}: ${N}"
  sleep 15
done
wait
echo "Done. With no traffic, replicas scale back to 0 after about 5 minutes (scale to zero)."
