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
BACKUP_ENABLED=${TERMINAL_BACKUP_ENABLED:-true}
BACKUP_DIR=${TERMINAL_BACKUP_DIR:-/tmp/sealos-backup/terminal-migration}

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
    https|acme|acmedns) TLS_REJECT_UNAUTHORIZED=0 ;;
    *) TLS_REJECT_UNAUTHORIZED=1 ;;
  esac
fi

add_set_string frontend.terminalConfig.ttydImage "${ttydImage:-}"
add_set_string frontend.terminalConfig.keepalived "${keepalived:-}"
add_set_string frontend.terminalConfig.ttyAgentBaseUrl "${TTY_AGENT_BASE_URL:-${ttyAgentBaseUrl:-}}"
add_set_string global.http.domain "${SEALOS_CLOUD_DOMAIN}"
add_set_string global.http.httpsPort "${SEALOS_CLOUD_PORT}"
add_set_string global.http.httpPort "${SEALOS_HTTP_PORT}"
add_set_string global.http.disableHttps "${SEALOS_DISABLE_HTTPS}"
add_set_string global.http.certSecretName "${SEALOS_CERT_SECRET_NAME}"
add_set_string controller.config.cloudDomain "${SEALOS_CLOUD_DOMAIN}"
add_set_string controller.config.cloudPort "${SEALOS_CLOUD_PORT}"
add_set_string controller.config.httpPort "${SEALOS_HTTP_PORT}"
add_set_string controller.config.disableHttps "${SEALOS_DISABLE_HTTPS}"
add_set_string controller.config.certSecretName "${SEALOS_CERT_SECRET_NAME}"
HELM_SET_ARGS+=(--set-string "platform.tlsRejectUnauthorized=${TLS_REJECT_UNAUTHORIZED}")

backup_release() {
  local release_name="$1"
  local namespace="$2"
  local prefix="$3"

  [[ "${BACKUP_ENABLED}" == true ]] || return
  helm status "${release_name}" -n "${namespace}" >/dev/null 2>&1 || return

  mkdir -p "${BACKUP_DIR}"
  helm get values "${release_name}" -n "${namespace}" --all >"${BACKUP_DIR}/${prefix}-values.yaml" || true
  helm get manifest "${release_name}" -n "${namespace}" >"${BACKUP_DIR}/${prefix}-manifest.yaml" || true
}

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

migrate_values_file() {
  local source_file="$1"
  local component="$2"
  local output_file="$3"
  local expression

  if [[ "${component}" == frontend ]]; then
    expression='. as $root | {"frontend": ($root | del(.global, .platform)), "global": ($root.global // {}), "platform": ($root.platform // {})}'
  else
    expression='. as $root | {"controller": ($root | del(.platform)), "platform": ($root.platform // {})}'
  fi

  yq eval "${expression}" "${source_file}" >"${output_file}"
}

merge_values_files() {
  local source_file="$1"
  local target_file="$2"
  local merged_file

  if [[ ! -s "${target_file}" ]]; then
    cp "${source_file}" "${target_file}"
    return
  fi

  merged_file="$(mktemp)"
  yq eval-all 'select(fileIndex == 0) * select(fileIndex == 1)' "${target_file}" "${source_file}" >"${merged_file}"
  mv "${merged_file}" "${target_file}"
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
  mapfile -t USER_VALUES_FILES < <(find "${app_values_dir}" -maxdepth 1 -type f -name '*-values.yaml' -print | LC_ALL=C sort)
  if (( ${#USER_VALUES_FILES[@]} > 0 )); then
    VALUES_ARGS=()
    for values_file in "${USER_VALUES_FILES[@]}"; do
      VALUES_ARGS+=(--values "${values_file}")
    done
    return
  fi

  mapfile -t legacy_values < <(
    find "${legacy_frontend_dir}" "${legacy_controller_dir}" -maxdepth 1 -type f -name '*-values.yaml' -print 2>/dev/null | LC_ALL=C sort
  )
  if (( ${#legacy_values[@]} == 0 )); then
    echo "WARN: /root/.sealos/cloud/values/apps/terminal has no values file; copying default values from ${default_values_file}."
    cp "${default_values_file}" "${app_values_dir}/${SERVICE_NAME}-values.yaml"
  else
    command -v yq >/dev/null 2>&1 || {
      echo "ERROR: yq is required to migrate legacy Terminal values." >&2
      exit 1
    }
    migration_file="${app_values_dir}/${SERVICE_NAME}-migrated-values.yaml"
    : >"${migration_file}"
    for values_file in "${legacy_values[@]}"; do
      mapped_file="$(mktemp)"
      if [[ "${values_file}" == "${legacy_frontend_dir}"/* ]]; then
        migrate_values_file "${values_file}" frontend "${mapped_file}"
      else
        migrate_values_file "${values_file}" controller "${mapped_file}"
      fi
      merge_values_files "${mapped_file}" "${migration_file}"
      rm -f "${mapped_file}"
    done
  fi

  mapfile -t USER_VALUES_FILES < <(find "${app_values_dir}" -maxdepth 1 -type f -name '*-values.yaml' -print | LC_ALL=C sort)
  VALUES_ARGS=()
  for values_file in "${USER_VALUES_FILES[@]}"; do
    VALUES_ARGS+=(--values "${values_file}")
  done
}

backup_release "${OLD_FRONTEND_RELEASE}" "${OLD_FRONTEND_NAMESPACE}" frontend-legacy
if helm status "${RELEASE_NAME}" -n "${RELEASE_NAMESPACE}" >/dev/null 2>&1 && ! is_unified_release; then
  backup_release "${RELEASE_NAME}" "${RELEASE_NAMESPACE}" controller-legacy
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
  "${HELM_SET_ARGS[@]}" \
  "${HELM_OPTS_ARGS[@]}"
