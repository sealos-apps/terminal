#!/usr/bin/env bash
set -euo pipefail

source /root/.sealos/cloud/scripts/tools.sh

RELEASE_NAME=${RELEASE_NAME:-terminal}
RELEASE_NAMESPACE=${RELEASE_NAMESPACE:-terminal-system}
CHART_PATH=${CHART_PATH:-./charts/terminal}
HELM_OPTS=${HELM_OPTS:-}
SERVICE_NAME=terminal
OLD_FRONTEND_RELEASE=${OLD_FRONTEND_RELEASE:-terminal-frontend}
OLD_FRONTEND_NAMESPACE=${OLD_FRONTEND_NAMESPACE:-terminal-frontend}

HELM_SET_ARGS=()
add_set_string() {
  local key="$1"
  local value="$2"
  if [[ -n "${value}" ]]; then
    HELM_SET_ARGS+=(--set-string "${key}=${value}")
  fi
}

SEALOS_CLOUD_DOMAIN=${SEALOS_CLOUD_DOMAIN:-"$(fetch_configmap_field sealos-config '{.data.cloudDomain}' 2>/dev/null || true)"}
SEALOS_CLOUD_PORT=${SEALOS_CLOUD_PORT:-"$(fetch_configmap_field sealos-config '{.data.cloudPort}' 2>/dev/null || true)"}
SEALOS_HTTP_PORT=${SEALOS_HTTP_PORT:-"$(fetch_configmap_field sealos-config '{.data.httpPort}' 2>/dev/null || true)"}
SEALOS_DISABLE_HTTPS=${SEALOS_DISABLE_HTTPS:-"$(fetch_configmap_field sealos-config '{.data.disableHttps}' 2>/dev/null || true)"}
SEALOS_CERT_SECRET_NAME=${SEALOS_CERT_SECRET_NAME:-"$(fetch_configmap_field sealos-config '{.data.certSecretName}' 2>/dev/null || true)"}
CERT_MODE=${CERT_MODE:-"$(fetch_configmap_field cert-config '{.data.CERT_MODE}' 2>/dev/null || true)"}

if declare -F read_cert_tls_reject_unauthorized >/dev/null 2>&1; then
  TLS_REJECT_UNAUTHORIZED="$(read_cert_tls_reject_unauthorized)"
else
  case "${CERT_MODE}" in
    https|acme|acmedns) TLS_REJECT_UNAUTHORIZED=0 ;;
    *) TLS_REJECT_UNAUTHORIZED=1 ;;
  esac
fi

add_set_string frontend.terminalConfig.ttydImage "${ttydImage:-}"
add_set_string frontend.terminalConfig.keepalived "${keepalived:-}"
add_set_string frontend.terminalConfig.ttyAgentBaseUrl "${TTY_AGENT_BASE_URL:-${ttyAgentBaseUrl:-}}"
add_set_string cloudDomain "${SEALOS_CLOUD_DOMAIN}"
add_set_string cloudPort "${SEALOS_CLOUD_PORT}"
add_set_string httpPort "${SEALOS_HTTP_PORT}"
add_set_string disableHttps "${SEALOS_DISABLE_HTTPS}"
add_set_string certSecretName "${SEALOS_CERT_SECRET_NAME}"
HELM_SET_ARGS+=(--set-string "platform.tlsRejectUnauthorized=${TLS_REJECT_UNAUTHORIZED}")

is_unified_release() {
  local values
  values="$(helm get values "${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" --all 2>/dev/null || true)"
  [[ "${values}" == *$'frontend:'* && "${values}" == *$'controller:'* ]]
}

uninstall_release() {
  local release_name="$1"
  local namespace="$2"

  if helm status "${release_name}" -n "${namespace}" >/dev/null 2>&1; then
    echo "Removing legacy Helm release ${release_name} from ${namespace}..."
    helm uninstall "${release_name}" -n "${namespace}"
  fi
}



prepare_values() {
  local app_values_dir="/root/.sealos/cloud/values/apps/${SERVICE_NAME}"
  local default_values_file="${CHART_PATH}/${SERVICE_NAME}-values.yaml"
  local legacy_frontend_dir="/root/.sealos/cloud/values/apps/terminal-frontend"
  local legacy_controller_dir="/root/.sealos/cloud/values/apps/terminal-controller"
  local migration_file
  local mapped_file
  local values_file
  local legacy_values=()

  mkdir -p "${app_values_dir}"

  if [[ ! -f "${default_values_file}" ]]; then
    echo "ERROR: Default values file ${default_values_file} not found." >&2
    exit 1
  fi

  if [[ ! -f "${app_values_dir}/${SERVICE_NAME}-values.yaml" ]]; then
    echo "WARN: ${app_values_dir}/${SERVICE_NAME}-values.yaml not found; copying default values from ${default_values_file}."
    cp "${default_values_file}" "${app_values_dir}/${SERVICE_NAME}-values.yaml"
  fi
}

if helm status "${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" >/dev/null 2>&1 && ! is_unified_release; then
  uninstall_release "${RELEASE_NAME}" "${RELEASE_NAMESPACE}"
fi
uninstall_release "${OLD_FRONTEND_RELEASE}" "${OLD_FRONTEND_NAMESPACE}"

prepare_values

echo "Deploying unified Terminal Helm chart to ${RELEASE_NAMESPACE}..."
helm upgrade -i "${RELEASE_NAME}" \
  -n "${RELEASE_NAMESPACE}" \
  --create-namespace \
  --wait \
  --atomic \
  "${CHART_PATH}" \
  "${HELM_SET_ARGS[@]}"
