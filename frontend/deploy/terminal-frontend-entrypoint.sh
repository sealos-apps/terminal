#!/usr/bin/env bash
set -euo pipefail

source /root/.sealos/cloud/scripts/tools.sh

RELEASE_NAME=${RELEASE_NAME:-terminal-frontend}
RELEASE_NAMESPACE=${RELEASE_NAMESPACE:-terminal-frontend}
CHART_PATH=${CHART_PATH:-./charts/terminal-frontend}
HELM_OPTS=${HELM_OPTS:-}
SERVICE_NAME=terminal-frontend
HELM_OPTS_ARGS=()
if [[ -n "${HELM_OPTS}" ]]; then
  read -r -a HELM_OPTS_ARGS <<<"${HELM_OPTS}"
fi

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
    https|acme|acmedns)
      TLS_REJECT_UNAUTHORIZED=0 # CERT_MODE=https|acme -> tlsRejectUnauthorized=0
      echo "0" >/dev/null
      ;;
    *)
      TLS_REJECT_UNAUTHORIZED=1 # tlsRejectUnauthorized=1
      echo "1" >/dev/null
      ;;
  esac
fi

add_set_string terminalConfig.cloudDomain "${SEALOS_CLOUD_DOMAIN}"
add_set_string terminalConfig.cloudPort "${SEALOS_CLOUD_PORT}"
add_set_string terminalConfig.httpPort "${SEALOS_HTTP_PORT}"
add_set_string terminalConfig.disableHttps "${SEALOS_DISABLE_HTTPS}"
add_set_string terminalConfig.certSecretName "${SEALOS_CERT_SECRET_NAME}"
add_set_string terminalConfig.ttydImage "${ttydImage:-}"
add_set_string terminalConfig.keepalived "${keepalived:-}"
add_set_string terminalConfig.ttyAgentBaseUrl "${TTY_AGENT_BASE_URL:-${ttyAgentBaseUrl:-}}"
add_set_string global.http.domain "${SEALOS_CLOUD_DOMAIN}"
add_set_string global.http.httpsPort "${SEALOS_CLOUD_PORT}"
add_set_string global.http.httpPort "${SEALOS_HTTP_PORT}"
add_set_string global.http.disableHttps "${SEALOS_DISABLE_HTTPS}"
add_set_string global.http.certSecretName "${SEALOS_CERT_SECRET_NAME}"
HELM_SET_ARGS+=(--set-string "platform.tlsRejectUnauthorized=${TLS_REJECT_UNAUTHORIZED}")

adopt_namespaced_resource() {
  local namespace="$1"
  local kind="$2"
  local name="$3"
  if kubectl -n "${namespace}" get "${kind}" "${name}" >/dev/null 2>&1; then
    echo "Adopting ${kind} ${namespace}/${name}..."
    kubectl -n "${namespace}" label "${kind}" "${name}" app.kubernetes.io/managed-by=Helm --overwrite >/dev/null 2>&1 || true
    kubectl -n "${namespace}" annotate "${kind}" "${name}" meta.helm.sh/release-name="${RELEASE_NAME}" meta.helm.sh/release-namespace="${RELEASE_NAMESPACE}" --overwrite >/dev/null 2>&1 || true
  fi
}

echo "Checking and adopting existing resources..."
if kubectl get namespace "${RELEASE_NAMESPACE}" >/dev/null 2>&1; then
  kubectl label namespace "${RELEASE_NAMESPACE}" app.kubernetes.io/managed-by=Helm --overwrite >/dev/null 2>&1 || true
  kubectl annotate namespace "${RELEASE_NAMESPACE}" meta.helm.sh/release-name="${RELEASE_NAME}" meta.helm.sh/release-namespace="${RELEASE_NAMESPACE}" --overwrite >/dev/null 2>&1 || true

  adopt_namespaced_resource "${RELEASE_NAMESPACE}" configmap terminal-frontend-config
  adopt_namespaced_resource "${RELEASE_NAMESPACE}" service terminal-frontend
  adopt_namespaced_resource "${RELEASE_NAMESPACE}" deployment terminal-frontend
  adopt_namespaced_resource "${RELEASE_NAMESPACE}" ingress sealos-terminal
fi

adopt_namespaced_resource app-system apps.app.sealos.io terminal

APP_VALUES_DIR="/root/.sealos/cloud/values/apps/${SERVICE_NAME}"
DEFAULT_VALUES_FILE="${CHART_PATH}/${SERVICE_NAME}-values.yaml"
if [[ ! -d "${APP_VALUES_DIR}" ]]; then
  echo "WARN: ${APP_VALUES_DIR} does not exist; creating it with the default values file."
  mkdir -p "${APP_VALUES_DIR}"
fi

mapfile -t USER_VALUES_FILES < <(find "${APP_VALUES_DIR}" -maxdepth 1 -type f -name '*-values.yaml' -print | LC_ALL=C sort)
if (( ${#USER_VALUES_FILES[@]} == 0 )); then
  echo "WARN: no *-values.yaml found in ${APP_VALUES_DIR}; copying the chart default."
  cp "${DEFAULT_VALUES_FILE}" "${APP_VALUES_DIR}/${SERVICE_NAME}-values.yaml"
  USER_VALUES_FILES=("${APP_VALUES_DIR}/${SERVICE_NAME}-values.yaml")
fi

VALUES_ARGS=()
for values_file in "${USER_VALUES_FILES[@]}"; do
  VALUES_ARGS+=(--values "${values_file}")
done

echo "Deploying Helm chart..."
helm upgrade -i "${RELEASE_NAME}" \
  -n "${RELEASE_NAMESPACE}" \
  --create-namespace \
  "${CHART_PATH}" \
  "${VALUES_ARGS[@]}" \
  "${HELM_SET_ARGS[@]}" \
  "${HELM_OPTS_ARGS[@]}"
