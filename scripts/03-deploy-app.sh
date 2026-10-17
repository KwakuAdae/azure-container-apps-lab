#!/usr/bin/env bash
# Step 3: Container Apps environment + the website app, first revision gets 100% (~3 minutes).
#   ./scripts/03-deploy-app.sh v1
source "$(dirname "$0")/config.sh"
TAG="${1:-v1}"; shift || true

step "terraform apply (terraform/2-app): revision website--${TAG} with 100% of traffic"
apply_app "$TAG" "[{tag=\"${TAG}\", percent=100}]" "$@"

echo ""
echo "✅ $(app_out app_url)"
echo "   (with min_replicas = 0, the first request after idle takes a few seconds: a cold start)"
