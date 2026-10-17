#!/usr/bin/env bash
# Shared helpers for the lab scripts.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY_DIR="${ROOT_DIR}/terraform/1-registry"
APP_DIR="${ROOT_DIR}/terraform/2-app"

# The azurerm provider needs the subscription ID; take it from your `az login` session
if [[ -z "${ARM_SUBSCRIPTION_ID:-}" ]]; then
  ARM_SUBSCRIPTION_ID="$(az account show --query id -o tsv)"
  export ARM_SUBSCRIPTION_ID
fi

registry_out() { terraform -chdir="$REGISTRY_DIR" output -raw "$1"; }
app_out() { terraform -chdir="$APP_DIR" output -raw "$1"; }
step() { echo ""; echo "▶ $*"; }

# Apply the app layer. $1 = image tag, $2 = traffic list in HCL, rest = extra terraform args
apply_app() {
  local tag="$1" traffic="$2"; shift 2
  terraform -chdir="$APP_DIR" init -input=false >/dev/null
  terraform -chdir="$APP_DIR" apply -var "image_tag=${tag}" -var "traffic=${traffic}" "$@"
  step "Traffic now"
  terraform -chdir="$APP_DIR" output traffic
}
