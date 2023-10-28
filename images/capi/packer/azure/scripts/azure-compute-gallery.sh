#!/bin/bash

set -euo pipefail

[[ -n ${DEBUG:-} ]] && set -o xtrace

# Make sure Azure credentials are given without printing them.
tracestate="$(shopt -po xtrace || true)"
set +o xtrace
_="
${AZURE_CLIENT_ID}
${AZURE_CLIENT_SECRET}
"
eval "${tracestate}"

# Environment-specific variables.
AZURE_SUBSCRIPTION_ID=${AZURE_SUBSCRIPTION_ID:-00000000-00000000-00000000-00000000}
AZURE_TENANT_ID=${AZURE_TENANT_ID:-00000000-00000000-00000000-00000000}
IMAGE_PUBLISHER_NAME=${IMAGE_PUBLISHER_NAME:-yourname}
IMAGE_PUBLISHER_URI=${IMAGE_PUBLISHER_URI:-https://yourwebsite/}
IMAGE_PUBLISHER_CONTACT=${IMAGE_PUBLISHER_CONTACT:-infra@yourdomain}
IMAGE_EULA_URL=${IMAGE_EULA_URL:-https://yoururl}
VHD_STORAGE_ACCOUNT_NAME=${VHD_STORAGE_ACCOUNT_NAME:-yourazurestorageaccountname}

# Generic variables.
AZURE_LOCATION=${AZURE_LOCATION:-westeurope}
PUBLISHING_SIG_RESOURCE_GROUP=${PUBLISHING_SIG_RESOURCE_GROUP:-capz-image-gallery-publishing}
STAGING_SIG_RESOURCE_GROUP=${STAGING_SIG_RESOURCE_GROUP:-capz-image-gallery-staging}
STAGING_GALLERY_NAME=${STAGING_GALLERY_NAME:-capz_staging}
GALLERY_NAME=${GALLERY_NAME:-capz}
# FLATCAR_VERSION=${FLATCAR_VERSION:-3374.2.1}
VERSION=${VERSION:-0.0.1}
# FLATCAR_CHANNEL=${FLATCAR_CHANNEL:-stable}
ARCH=${ARCH:-amd64}
# FLATCAR_IMAGE_NAME=${FLATCAR_IMAGE_NAME:-flatcar-${FLATCAR_CHANNEL}-${FLATCAR_ARCH}}
# FLATCAR_IMAGE_OFFER=${FLATCAR_IMAGE_OFFER:-${FLATCAR_CHANNEL}}
# FLATCAR_IMAGE_SKU=${FLATCAR_IMAGE_SKU:-${FLATCAR_IMAGE_NAME}}
# VHD_STORAGE_SUBSCRIPTION_ID=${VHD_STORAGE_SUBSCRIPTION_ID:-${AZURE_SUBSCRIPTION_ID}}
# VHD_STORAGE_RESOURCE_GROUP_NAME=${VHD_STORAGE_RESOURCE_GROUP_NAME:-flatcar}
# VHD_STORAGE_CONTAINER_NAME=${VHD_STORAGE_CONTAINER_NAME:-publish}
# FLATCAR_COMMUNITY_GALLERY_PUBLIC_NAME_PREFIX=${FLATCAR_COMMUNITY_GALLERY_PUBLIC_NAME_PREFIX:-flatcar}
# Regions below require explicit opt-in, so exclude them from "default" regions.
EXCLUDED_TARGET_REGIONS=${EXCLUDED_TARGET_REGIONS:-polandcentral australiacentral2 brazilsoutheast centraluseuap eastus2euap eastusstg francesouth germanynorth jioindiacentral norwaywest southafricawest switzerlandwest uaecentral}
DEFAULT_TARGET_REGIONS=$(az account list-locations -o json | jq -r '.[] | select( .metadata.regionType != "Logical" ) | .name' | sort | grep -v -E "(${EXCLUDED_TARGET_REGIONS// /|})" | tr \\n ' ')
TARGET_REGIONS=${TARGET_REGIONS:-${DEFAULT_TARGET_REGIONS}}

# CAPI specific variables.
KUBERNETES_SEMVER=${KUBERNETES_SEMVER:-v1.28.3}
# FLATCAR_CAPI_GALLERY_NAME=${FLATCAR_CAPI_GALLERY_NAME:-flatcar4capi}
# FLATCAR_CAPI_STAGING_GALLERY_NAME=${FLATCAR_CAPI_STAGING_GALLERY_NAME:-flatcar4capi_staging}
# FLATCAR_CAPI_IMAGE_NAME=${FLATCAR_CAPI_IMAGE_NAME:-${FLATCAR_IMAGE_NAME}-capi-${KUBERNETES_SEMVER}}
IMAGE_NAME=capz-${KUBERNETES_SEMVER}
# FLATCAR_CAPI_IMAGE_OFFER=${FLATCAR_CAPI_IMAGE_OFFER:-${FLATCAR_CHANNEL}-capi}
IMAGE_OFFER=capz
# FLATCAR_CAPI_IMAGE_SKU=${FLATCAR_CAPI_IMAGE_SKU:-${FLATCAR_CAPI_IMAGE_NAME}}
# FLATCAR_CAPI_COMMUNITY_GALLERY_PUBLIC_NAME_PREFIX=${FLATCAR_CAPI_COMMUNITY_GALLERY_PUBLIC_NAME_PREFIX:-flatcar4capi}

function publish-capz-image() {
  require-amd64-arch

  # First, make sure staging image is available before publishing.
  build-staging-image

  login

  IMAGE_NAME="${FLATCAR_CAPI_IMAGE_NAME}"
  IMAGE_VERSION="${FLATCAR_VERSION}"
  GALLERY_NAME="${GALLERY_NAME}"
  RESOURCE_GROUP_NAME="${PUBLISHING_SIG_RESOURCE_GROUP}"

  # shellcheck disable=SC2310 # This might return 1.
  if sig-image-version-exists; then
    return
  fi

  ensure-resource-group
  ensure-community-sig

  IMAGE_OFFER="${FLATCAR_CAPI_IMAGE_OFFER}"
  IMAGE_PUBLISHER="${IMAGE_PUBLISHER_NAME}"
  ensure-image-definition

  SOURCE_VERSION="/subscriptions/${AZURE_SUBSCRIPTION_ID}/resourceGroups/${STAGING_SIG_RESOURCE_GROUP}"
  SOURCE_VERSION="${SOURCE_VERSION}/providers/Microsoft.Compute/galleries"
  SOURCE_VERSION="${SOURCE_VERSION}/${STAGING_GALLERY_NAME}/images/${IMAGE_NAME}/versions/${IMAGE_VERSION}"

  EXCLUDE_FROM_LATEST=true copy-sig-image-version
}

function build-staging-image() {
  require-amd64-arch

  login

  IMAGE_NAME="${IMAGE_NAME}"
  IMAGE_VERSION="${VERSION}"
  GALLERY_NAME="${STAGING_GALLERY_NAME}"
  RESOURCE_GROUP_NAME="${STAGING_SIG_RESOURCE_GROUP}"

  # shellcheck disable=SC2310 # This might return 1.
  if sig-image-version-exists; then
    return
  fi

  ensure-resource-group
  ensure-sig

  IMAGE_OFFER="${IMAGE_OFFER}"
  IMAGE_PUBLISHER="${IMAGE_PUBLISHER_NAME}"
  ensure-image-definition

#   cat <<EOF > images/capi/packer.json
# {
#   # "gallery_name": "${STAGING_GALLERY_NAME}"
# }
# EOF

  # "sig_image_version": "${VERSION}",
  # "image_name": "${IMAGE_NAME}",
  # "image_offer": "${IMAGE_OFFER}",
  # "image_publisher": "${IMAGE_PUBLISHER}",
  # "image_sku": "${IMAGE_NAME}"
  # "kubernetes_semver": "${KUBERNETES_SEMVER}",
  # "image_version": "",
  # "plan_image_offer": "",
  # "plan_image_publisher": "",
  # "plan_image_sku": ""
  # "source_sig_subscription_id": "${AZURE_SUBSCRIPTION_ID}",
  # "source_sig_resource_group_name": "${STAGING_SIG_RESOURCE_GROUP}",
  # "source_sig_name": "${STAGING_GALLERY_NAME}",
  # "source_sig_image_name": "${IMAGE_NAME}",
  # "source_sig_image_version": "${VERSION}"

  # Export variables expected by init-sig.sh.
  export RESOURCE_GROUP_NAME="${STAGING_SIG_RESOURCE_GROUP}"
  export GALLERY_NAME="${STAGING_GALLERY_NAME}"
  export AZURE_SUBSCRIPTION_ID
  export AZURE_LOCATION
  export AZURE_CLIENT_ID
  export AZURE_CLIENT_SECRET
  # export PACKER_VAR_FILES=packer.json

  # I'd recommend running in debug mode when running interactively, as Packer tends to produce hard to debug
  # error messages.
  # export DEBUG=true
  # export PACKER_LOG=1

  make -C images/capi build-azure-sig-ubuntu-2204
}

# Below are utility functions.
function require-amd64-arch() {
  if [[ "${ARCH}" != "amd64" ]]; then
    echo "Unsupported architecture '${ARCH}'. Only 'amd64' is supported."
    exit 1
  fi
}

function copy-sig-image-version() {
  IMAGE_NAME=${IMAGE_NAME:-}
  IMAGE_VERSION="${IMAGE_VERSION:-}"
  GALLERY_NAME=${GALLERY_NAME:-}
  RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-}
  EXCLUDE_FROM_LATEST=${EXCLUDE_FROM_LATEST:-false}
  SOURCE_VERSION="${SOURCE_VERSION:-}"

  # shellcheck disable=SC2086 # Apparently target regions must be space-separated for Azure CLI.
  az sig image-version create \
    --gallery-image-definition "${IMAGE_NAME}" \
    --gallery-image-version "${IMAGE_VERSION}" \
    --gallery-name "${GALLERY_NAME}" \
    --resource-group "${RESOURCE_GROUP_NAME}" \
    --exclude-from-latest "${EXCLUDE_FROM_LATEST}" \
    --image-version "${SOURCE_VERSION}" \
    --target-regions ${TARGET_REGIONS}
}

function sig-image-version-exists() {
  IMAGE_NAME=${IMAGE_NAME:-}
  IMAGE_VERSION="${IMAGE_VERSION:-}"
  GALLERY_NAME=${GALLERY_NAME:-}
  RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-}

  if ! az sig image-version show \
    --gallery-image-definition "${IMAGE_NAME}" \
    --gallery-image-version "${IMAGE_VERSION}" \
    --gallery-name "${GALLERY_NAME}" \
    --resource-group "${RESOURCE_GROUP_NAME}" \
    --output none \
    --only-show-errors; then
      echo "SIG image ${RESOURCE_GROUP_NAME}/${GALLERY_NAME}/${IMAGE_VERSION}/${IMAGE_NAME} does not exist"

    return 1
  fi

  echo "SIG image ${RESOURCE_GROUP_NAME}/${GALLERY_NAME}/${IMAGE_VERSION}/${IMAGE_NAME} already exists"

  return 0
}

function ensure-image-definition() {
  IMAGE_NAME=${IMAGE_NAME:-}
  GALLERY_NAME=${GALLERY_NAME:-}
  IMAGE_OFFER=${IMAGE_OFFER:-}
  IMAGE_PUBLISHER=${IMAGE_PUBLISHER:-}
  RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-}

  local architecture

  case "${ARCH}" in
    amd64)
      architecture=x64
      ;;
    arm64)
      architecture=Arm64
      ;;
    *)
      echo "Unsupported architecture: '${ARCH}'"
      exit 1
      ;;
  esac

  az sig image-definition create \
    --gallery-image-definition "${IMAGE_NAME}" \
    --gallery-name "${GALLERY_NAME}" \
    --offer "${IMAGE_OFFER}" \
    --os-type Linux \
    --publisher "${IMAGE_PUBLISHER}" \
    --resource-group "${RESOURCE_GROUP_NAME}" \
    --sku "${IMAGE_NAME}" \
    --architecture "${architecture}" \
    --hyper-v-generation V2
}

function ensure-sig() {
  GALLERY_NAME=${GALLERY_NAME:-}
  RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-}

  az sig create \
    --gallery-name "${GALLERY_NAME}" \
    --resource-group "${RESOURCE_GROUP_NAME}"
}

function ensure-community-sig() {
  GALLERY_NAME=${GALLERY_NAME:-}
  RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-}
  PUBLIC_NAME_PREFIX=${PUBLIC_NAME_PREFIX:-}

  az sig create \
    --gallery-name "${GALLERY_NAME}" \
    --resource-group "${RESOURCE_GROUP_NAME}" \
    --eula "${IMAGE_EULA_URL}" \
    --location "${AZURE_LOCATION}" \
    --public-name-prefix "${PUBLIC_NAME_PREFIX}"
}

function ensure-resource-group() {
  RESOURCE_GROUP_NAME=${RESOURCE_GROUP_NAME:-}

  if ! az group show -n "${RESOURCE_GROUP_NAME}" -o none 2>/dev/null; then
    az group create -n "${RESOURCE_GROUP_NAME}" -l "${AZURE_LOCATION}"
  fi
}

function login() {
  tracestate="$(shopt -po xtrace || true)"
  set +o xtrace
  az login --service-principal -u "${AZURE_CLIENT_ID}" -p "${AZURE_CLIENT_SECRET}" --tenant "${AZURE_TENANT_ID}" >/dev/null 2>&1
  az account set -s "${AZURE_SUBSCRIPTION_ID}" >/dev/null 2>&1
  eval "${tracestate}"
}

if [[ $# -eq 0 ]]; then
  cat << EOF
usage: $0 <action>

Available actions:
  - build-staging-image - Builds CAPZ image using image-builder to staging SIG.
  - publish-capz-image - Publishes CAPZ image to community SIG from staging SIG.
EOF

  exit 0
fi

$1
