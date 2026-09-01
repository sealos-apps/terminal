#!/usr/bin/env bash
set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
test_root="$(mktemp -d)"
fake_bin="${test_root}/bin"

cleanup() {
  rm -rf "${test_root}"
}
trap cleanup EXIT

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

assert_file_exists() {
  [[ -f "$1" ]] || fail "expected file to exist: $1"
}

assert_file_missing() {
  [[ ! -e "$1" ]] || fail "expected file to be removed: $1"
}

assert_args_include() {
  grep -Fqx -- "$2" "$1" || fail "expected Helm arguments to include: $2"
}

assert_args_exclude() {
  if grep -Fqx -- "$2" "$1"; then
    fail "expected Helm arguments not to include: $2"
  fi
}

mkdir -p "${fake_bin}"
printf '%s\n' \
  '#!/usr/bin/env bash' \
  'set -euo pipefail' \
  '' \
  'case "${1:-}" in' \
  '  list)' \
  '    if [[ "${HELM_TEST_CHART:?}" == none ]]; then' \
  '      printf "[]\\n"' \
  '    else' \
  '      printf "[{\\\"name\\\":\\\"terminal\\\",\\\"namespace\\\":\\\"terminal-system\\\",\\\"chart\\\":\\\"%s\\\"}]\\n" "${HELM_TEST_CHART}"' \
  '    fi' \
  '    ;;' \
  '  status)' \
  '    exit 0' \
  '    ;;' \
  '  get)' \
  '    printf "frontend:\\ncontroller:\\n"' \
  '    ;;' \
  '  uninstall)' \
  '    exit 0' \
  '    ;;' \
  '  upgrade)' \
  '    printf "%s\\n" "$@" > "${HELM_TEST_ARGS_FILE:?}"' \
  '    ;;' \
  '  *)' \
  '    printf "unexpected Helm command: %s\\n" "$*" >&2' \
  '    exit 1' \
  '    ;;' \
  'esac' >"${fake_bin}/helm"
chmod +x "${fake_bin}/helm"

run_case() {
  local name="$1"
  local chart="$2"
  local include_default_values="$3"
  local include_override_values="$4"

  CASE_ROOT="${test_root}/${name}"
  CASE_CLOUD_ROOT="${CASE_ROOT}/cloud"
  CASE_VALUES_DIR="${CASE_CLOUD_ROOT}/values/apps/terminal"
  CASE_ENTRYPOINT="${CASE_ROOT}/entrypoint.sh"
  CASE_ARGS_FILE="${CASE_ROOT}/helm-args.txt"

  mkdir -p "${CASE_CLOUD_ROOT}/scripts" "${CASE_VALUES_DIR}"
  printf '%s\n' \
    'fetch_configmap_field() { return 0; }' \
    'read_cert_tls_reject_unauthorized() { printf "1\\n"; }' >"${CASE_CLOUD_ROOT}/scripts/tools.sh"
  sed "s|/root/.sealos/cloud|${CASE_CLOUD_ROOT}|g" \
    "${repository_root}/deploy/entrypoint.sh" >"${CASE_ENTRYPOINT}"
  chmod +x "${CASE_ENTRYPOINT}"

  if [[ "${include_default_values}" == true ]]; then
    printf 'legacy: true\n' >"${CASE_VALUES_DIR}/terminal-values.yaml"
  fi
  if [[ "${include_override_values}" == true ]]; then
    printf 'custom: true\n' >"${CASE_VALUES_DIR}/custom-values.yaml"
  fi

  PATH="${fake_bin}:${PATH}" \
    HELM_TEST_CHART="${chart}" \
    HELM_TEST_ARGS_FILE="${CASE_ARGS_FILE}" \
    CHART_PATH="${repository_root}/deploy/charts/terminal" \
    bash "${CASE_ENTRYPOINT}" >/dev/null
}

run_case legacy-default-only terminal-0.1.0 true false
assert_file_missing "${CASE_VALUES_DIR}/terminal-values.yaml"
assert_args_exclude "${CASE_ARGS_FILE}" "${CASE_VALUES_DIR}/terminal-values.yaml"

run_case legacy-with-override terminal-0.1.0 true true
assert_file_missing "${CASE_VALUES_DIR}/terminal-values.yaml"
assert_file_exists "${CASE_VALUES_DIR}/custom-values.yaml"
assert_args_include "${CASE_ARGS_FILE}" "${CASE_VALUES_DIR}/custom-values.yaml"
assert_args_exclude "${CASE_ARGS_FILE}" "${CASE_VALUES_DIR}/terminal-values.yaml"

run_case current-chart terminal-0.3.0 true false
assert_file_exists "${CASE_VALUES_DIR}/terminal-values.yaml"
assert_args_include "${CASE_ARGS_FILE}" "${CASE_VALUES_DIR}/terminal-values.yaml"

run_case similarly-named-chart terminal-0.10.0 true false
assert_file_exists "${CASE_VALUES_DIR}/terminal-values.yaml"
assert_args_include "${CASE_ARGS_FILE}" "${CASE_VALUES_DIR}/terminal-values.yaml"

run_case legacy-without-default terminal-0.1.0 false false
assert_file_exists "${CASE_VALUES_DIR}/terminal-values.yaml"
assert_args_include "${CASE_ARGS_FILE}" "${CASE_VALUES_DIR}/terminal-values.yaml"

run_case no-existing-release none true false
assert_file_exists "${CASE_VALUES_DIR}/terminal-values.yaml"
assert_args_include "${CASE_ARGS_FILE}" "${CASE_VALUES_DIR}/terminal-values.yaml"

printf 'PASS: deploy entrypoint migration behavior\n'
