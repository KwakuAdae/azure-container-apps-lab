#!/usr/bin/env bash
# Step 1: resource group, Log Analytics, Azure Container Registry and the AcrPull identity (~2 minutes).
#   ./scripts/01-create-registry.sh                 # review the plan, then type yes
#   ./scripts/01-create-registry.sh -auto-approve
source "$(dirname "$0")/config.sh"

step "Subscription: $(az account show --query '[name, id]' -o tsv | tr '\t' ' ')"

step "Registering resource providers (one-time per subscription; safe to repeat)"
for ns in Microsoft.App Microsoft.OperationalInsights Microsoft.ContainerRegistry Microsoft.ManagedIdentity; do
  az provider register --namespace "$ns" --wait
  echo "   ${ns}: registered"
done

step "terraform init + apply (terraform/1-registry)"
terraform -chdir="$REGISTRY_DIR" init -input=false
terraform -chdir="$REGISTRY_DIR" apply "$@"

echo ""
echo "✅ Registry: $(registry_out acr_login_server)"
echo "   Next: ./scripts/02-build-image.sh v1 blue"
