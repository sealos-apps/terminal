#!/usr/bin/env bash
set -euo pipefail

source /root/.sealos/cloud/scripts/tools.sh

HELM_OPTS=${HELM_OPTS:-}
RELEASE_NAME=${RELEASE_NAME:-terminal}
RELEASE_NAMESPACE=${RELEASE_NAMESPACE:-terminal-system}
CHART_PATH=${CHART_PATH:-./charts/terminal-controller}
HELM_OPTS_ARGS=()
if [[ -n "${HELM_OPTS}" ]]; then
  read -r -a HELM_OPTS_ARGS <<<"${HELM_OPTS}"
fi
SERVICE_NAME=terminal-controller

TERMINAL_BACKUP_ENABLED=${TERMINAL_BACKUP_ENABLED:-true}
TERMINAL_BACKUP_DIR=${TERMINAL_BACKUP_DIR:-/tmp/sealos-backup/terminal-controller}

HELM_SET_ARGS=()
add_set_string() {
  local key="$1"
  local value="$2"
  if [[ -n "${value}" ]]; then
    HELM_SET_ARGS+=(--set-string "${key}=${value}")
  fi
}

adopt_namespaced_resource() {
  local kind="$1"
  local name="$2"
  if kubectl -n "${RELEASE_NAMESPACE}" get "${kind}" "${name}" >/dev/null 2>&1; then
    kubectl -n "${RELEASE_NAMESPACE}" label "${kind}" "${name}" app.kubernetes.io/managed-by=Helm --overwrite >/dev/null 2>&1 || true
    kubectl -n "${RELEASE_NAMESPACE}" annotate "${kind}" "${name}" meta.helm.sh/release-name="${RELEASE_NAME}" meta.helm.sh/release-namespace="${RELEASE_NAMESPACE}" --overwrite >/dev/null 2>&1 || true
  fi
}

adopt_cluster_resource() {
  local kind="$1"
  local name="$2"
  if kubectl get "${kind}" "${name}" >/dev/null 2>&1; then
    kubectl label "${kind}" "${name}" app.kubernetes.io/managed-by=Helm --overwrite >/dev/null 2>&1 || true
    kubectl annotate "${kind}" "${name}" meta.helm.sh/release-name="${RELEASE_NAME}" meta.helm.sh/release-namespace="${RELEASE_NAMESPACE}" --overwrite >/dev/null 2>&1 || true
  fi
}

backup_ns_resource() {
  local kind="$1"
  local name="$2"
  if kubectl -n "${RELEASE_NAMESPACE}" get "${kind}" "${name}" >/dev/null 2>&1; then
    kubectl -n "${RELEASE_NAMESPACE}" get "${kind}" "${name}" -o yaml >>"${TERMINAL_BACKUP_FILE}"
    printf '\n---\n' >>"${TERMINAL_BACKUP_FILE}"
  fi
}

backup_cluster_resource() {
  local kind="$1"
  local name="$2"
  if kubectl get "${kind}" "${name}" >/dev/null 2>&1; then
    kubectl get "${kind}" "${name}" -o yaml >>"${TERMINAL_BACKUP_FILE}"
    printf '\n---\n' >>"${TERMINAL_BACKUP_FILE}"
  fi
}

backup_terminal_resources() {
  if [[ "${TERMINAL_BACKUP_ENABLED}" != true ]]; then
    return
  fi

  local timestamp
  timestamp=$(date +%Y%m%d%H%M%S)
  mkdir -p "${TERMINAL_BACKUP_DIR}"
  TERMINAL_BACKUP_FILE="${TERMINAL_BACKUP_DIR}/update-${timestamp}.yaml"
  : >"${TERMINAL_BACKUP_FILE}"

  backup_cluster_resource customresourcedefinition terminals.terminal.sealos.io
  backup_cluster_resource clusterrole terminal-manager-role
  backup_cluster_resource clusterrolebinding terminal-manager-rolebinding

  if kubectl get namespace "${RELEASE_NAMESPACE}" >/dev/null 2>&1; then
    kubectl get namespace "${RELEASE_NAMESPACE}" -o yaml >>"${TERMINAL_BACKUP_FILE}"
    printf '\n---\n' >>"${TERMINAL_BACKUP_FILE}"
  fi
  backup_ns_resource configmap terminal-manager-config
  backup_ns_resource service terminal-controller-manager-metrics-service
  backup_ns_resource deployment terminal-controller-manager
  backup_ns_resource serviceaccount terminal-controller-manager
  backup_ns_resource role terminal-leader-election-role
  backup_ns_resource rolebinding terminal-leader-election-rolebinding
}

source_config() {
  SEALOS_CLOUD_DOMAIN=${SEALOS_CLOUD_DOMAIN:-"$(fetch_configmap_field sealos-config '{.data.cloudDomain}' 2>/dev/null || true)"}
  SEALOS_CLOUD_PORT=${SEALOS_CLOUD_PORT:-"$(fetch_configmap_field sealos-config '{.data.cloudPort}' 2>/dev/null || true)"}
  SEALOS_HTTP_PORT=${SEALOS_HTTP_PORT:-"$(fetch_configmap_field sealos-config '{.data.httpPort}' 2>/dev/null || true)"}
  SEALOS_DISABLE_HTTPS=${SEALOS_DISABLE_HTTPS:-"$(fetch_configmap_field sealos-config '{.data.disableHttps}' 2>/dev/null || true)"}
  SEALOS_CERT_SECRET_NAME=${SEALOS_CERT_SECRET_NAME:-"$(fetch_configmap_field sealos-config '{.data.certSecretName}' 2>/dev/null || true)"}
  CERT_MODE=${CERT_MODE:-"$(fetch_configmap_field cert-config '{.data.CERT_MODE}' 2>/dev/null || true)"}
}

source_config
backup_terminal_resources

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

add_set_string config.cloudDomain "${SEALOS_CLOUD_DOMAIN}"
add_set_string config.cloudPort "${SEALOS_CLOUD_PORT}"
add_set_string config.httpPort "${SEALOS_HTTP_PORT}"
add_set_string config.disableHttps "${SEALOS_DISABLE_HTTPS}"
add_set_string config.certSecretName "${SEALOS_CERT_SECRET_NAME}"
HELM_SET_ARGS+=(--set-string "platform.tlsRejectUnauthorized=${TLS_REJECT_UNAUTHORIZED}")

if ! helm status "${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" >/dev/null 2>&1; then
  if kubectl get namespace "${RELEASE_NAMESPACE}" >/dev/null 2>&1; then
    kubectl label namespace "${RELEASE_NAMESPACE}" app.kubernetes.io/managed-by=Helm --overwrite >/dev/null 2>&1 || true
    kubectl annotate namespace "${RELEASE_NAMESPACE}" meta.helm.sh/release-name="${RELEASE_NAME}" meta.helm.sh/release-namespace="${RELEASE_NAMESPACE}" --overwrite >/dev/null 2>&1 || true
  fi

  adopt_namespaced_resource configmap terminal-manager-config
  adopt_namespaced_resource service terminal-controller-manager-metrics-service
  adopt_namespaced_resource deployment terminal-controller-manager
  adopt_namespaced_resource serviceaccount terminal-controller-manager
  adopt_namespaced_resource role terminal-leader-election-role
  adopt_namespaced_resource rolebinding terminal-leader-election-rolebinding
  adopt_cluster_resource clusterrole terminal-manager-role
  adopt_cluster_resource clusterrolebinding terminal-manager-rolebinding
fi

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

helm upgrade -i "${RELEASE_NAME}" \
  -n "${RELEASE_NAMESPACE}" \
  --create-namespace \
  "${CHART_PATH}" \
  "${VALUES_ARGS[@]}" \
  "${HELM_SET_ARGS[@]}" \
  "${HELM_OPTS_ARGS[@]}"
