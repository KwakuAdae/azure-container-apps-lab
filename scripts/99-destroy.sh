#!/usr/bin/env bash
# Destroy the app layer first, then the registry layer (resource group, ACR, identity, logs).
#   ./scripts/99-destroy.sh                 # review each plan, then type yes
#   ./scripts/99-destroy.sh -auto-approve
source "$(dirname "$0")/config.sh"

step "Destroying the app layer (environment + container app) ~3 minutes"
terraform -chdir="$APP_DIR" destroy "$@"

step "Destroying the registry layer (resource group, ACR, identity, Log Analytics)"
terraform -chdir="$REGISTRY_DIR" destroy "$@"

echo ""
echo "✅ Done. Check:  az group list --query \"[?contains(name,'acalab')].name\" -o tsv"
