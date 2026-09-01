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
VALUES_ARGS=()
LEGACY_DEFAULT_VALUES_REMOVED=false
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

is_terminal_chart_v010() {
  local releases

  releases="$(helm list \
    -n "${RELEASE_NAMESPACE}" \
    --filter "^${RELEASE_NAME}$" \
    --output json 2>/dev/null)" || return 1

  [[ "${releases}" =~ \"chart\"[[:space:]]*:[[:space:]]*\"${SERVICE_NAME}-0\.1\.0\" ]]
}

remove_terminal_v010_values_file() {
  local values_file="/root/.sealos/cloud/values/apps/${SERVICE_NAME}/${SERVICE_NAME}-values.yaml"

  if is_terminal_chart_v010 && [[ -f "${values_file}" ]]; then
    echo "Removing legacy Terminal values file ${values_file} for chart ${SERVICE_NAME}-0.1.0..."
    rm -f -- "${values_file}"
    LEGACY_DEFAULT_VALUES_REMOVED=true
  fi
}

collect_values_files() {
  local values_dir="$1"
  local values_file

  VALUES_FILES=()
  while IFS= read -r values_file; do
    VALUES_FILES+=("${values_file}")
  done < <(
    find "${values_dir}" -maxdepth 1 -type f -name '*-values.yaml' -print |
      LC_ALL=C sort
  )
}

prepare_values() {
  local app_values_dir="/root/.sealos/cloud/values/apps/${SERVICE_NAME}"
  local default_values_file="${CHART_PATH}/${SERVICE_NAME}-values.yaml"
  local default_app_values_file="${app_values_dir}/${SERVICE_NAME}-values.yaml"
  local values_file

  if [[ ! -f "${default_values_file}" ]]; then
    echo "ERROR: Default values file ${default_values_file} not found." >&2
    exit 1
  fi

  if [[ ! -d "${app_values_dir}" ]]; then
    echo "WARN: /root/.sealos/cloud/values/apps/${SERVICE_NAME}/ (${app_values_dir}) missing; copying default *-values.yaml from ${default_values_file}."
    mkdir -p "${app_values_dir}"
    cp "${default_values_file}" "${default_app_values_file}"
  fi

  collect_values_files "${app_values_dir}"
  if (( ${#VALUES_FILES[@]} == 0 )); then
    if [[ "${LEGACY_DEFAULT_VALUES_REMOVED}" == true ]]; then
      echo "INFO: Legacy Terminal values were removed; using chart defaults without recreating ${default_app_values_file}."
    else
      echo "WARN: /root/.sealos/cloud/values/apps/${SERVICE_NAME}/ (${app_values_dir}) has no *-values.yaml; copying default *-values.yaml from ${default_values_file}."
      cp "${default_values_file}" "${default_app_values_file}"
      collect_values_files "${app_values_dir}"
    fi
  fi

  # When present, generated defaults have the lowest precedence. User values
  # files are then applied in deterministic filename order.
  VALUES_ARGS=()
  if [[ -f "${default_app_values_file}" ]]; then
    VALUES_ARGS+=(--values "${default_app_values_file}")
  fi
  for values_file in "${VALUES_FILES[@]}"; do
    if [[ "${values_file}" == "${default_app_values_file}" ]]; then
      continue
    fi
    VALUES_ARGS+=(--values "${values_file}")
  done
}

remove_terminal_v010_values_file

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
  "${VALUES_ARGS[@]}" \
  "${HELM_SET_ARGS[@]}"
