#!/usr/bin/env bash
# Step 2: build the website image IN AZURE with ACR Tasks (no local Docker needed).
#   ./scripts/02-build-image.sh v1 blue
#   ./scripts/02-build-image.sh v2 green
#   ./scripts/02-build-image.sh v3 orange --local   # or build with your own Docker and push
source "$(dirname "$0")/config.sh"
TAG="${1:?usage: $0 <tag> [blue|green|orange] [--local]}"
COLOR="${2:-blue}"
BUILT="$(date -u +%Y-%m-%dT%H:%MZ)"
ACR_NAME="$(registry_out acr_name)"
LOGIN_SERVER="$(registry_out acr_login_server)"

if [[ "${3:-}" == "--local" ]]; then
  step "Building locally and pushing ${LOGIN_SERVER}/website:${TAG}"
  az acr login --name "$ACR_NAME"
  docker build --platform linux/amd64 \
    --build-arg APP_VERSION="$TAG" --build-arg APP_COLOR="$COLOR" --build-arg BUILD_TIME="$BUILT" \
    -t "${LOGIN_SERVER}/website:${TAG}" "${ROOT_DIR}/app"
  docker push "${LOGIN_SERVER}/website:${TAG}"
else
  step "Building ${LOGIN_SERVER}/website:${TAG} (${COLOR}) with ACR Tasks (the build runs in Azure)"
  az acr build --registry "$ACR_NAME" --image "website:${TAG}" --platform linux/amd64 \
    --build-arg APP_VERSION="$TAG" --build-arg APP_COLOR="$COLOR" --build-arg BUILD_TIME="$BUILT" \
    "${ROOT_DIR}/app"
fi

step "Tags now in the registry"
az acr repository show-tags --name "$ACR_NAME" --repository website -o table
