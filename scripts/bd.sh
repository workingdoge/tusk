#!/usr/bin/env bash
set -euo pipefail

real_bd="${TUSK_REAL_BD:?TUSK_REAL_BD is required}"
real_tuskd="${TUSK_REAL_TUSKD:?TUSK_REAL_TUSKD is required}"
paths_sh="${TUSK_PATHS_SH:?TUSK_PATHS_SH is required}"

source "${paths_sh}"

state_root() {
  local repo_root="$1"
  printf '%s/.beads/tuskd\n' "${repo_root}"
}

service_path() {
  local repo_root="$1"
  printf '%s/service.json\n' "$(state_root "${repo_root}")"
}

service_record() {
  local repo_root="$1"
  local path

  path="$(service_path "${repo_root}")"
  if [ -f "${path}" ]; then
    cat "${path}"
    return
  fi

  printf 'null\n'
}

port_owner_pid() {
  local port="$1"
  local pid=""

  pid="$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null | head -n1 || true)"
  if [ -n "${pid}" ]; then
    printf '%s\n' "${pid}"
  fi
}

service_record_is_live() {
  local repo_root="$1"
  local record_json="$2"
  local port=""
  local pid=""
  local owner_pid=""

  if [ "${record_json}" = "null" ]; then
    return 1
  fi

  if ! jq -e --arg repo_root "${repo_root}" '
      .service_kind == "bd-tracker" and
      .repo_root == $repo_root and
      (.backend_endpoint.host // "") != "" and
      (.backend_endpoint.port // 0) > 0 and
      .health.status == "healthy"
    ' >/dev/null <<<"${record_json}"; then
    return 1
  fi

  port="$(jq -r '.backend_endpoint.port // empty' <<<"${record_json}")"
  pid="$(jq -r '.backend_runtime.pid // empty' <<<"${record_json}")"
  if [ -z "${port}" ] || [ -z "${pid}" ]; then
    return 1
  fi

  owner_pid="$(port_owner_pid "${port}")"
  [ -n "${owner_pid}" ] && [ "${owner_pid}" = "${pid}" ]
}

ensure_service_record() {
  local repo_root="$1"
  local record_json="null"
  local repair_message=""

  record_json="$(service_record "${repo_root}")"
  if service_record_is_live "${repo_root}" "${record_json}"; then
    printf '%s\n' "${record_json}"
    return
  fi

  "${real_tuskd}" ensure --repo "${repo_root}" >/dev/null
  record_json="$(service_record "${repo_root}")"
  if ! service_record_is_live "${repo_root}" "${record_json}"; then
    repair_message="$(jq -r '.health.checks.backend_repair.message // empty' <<<"${record_json}" 2>/dev/null || true)"
    if [ -n "${repair_message}" ]; then
      echo "bd: ${repair_message}" >&2
    fi
    echo "bd: tuskd did not produce a healthy service record for ${repo_root}" >&2
    exit 1
  fi

  printf '%s\n' "${record_json}"
}

export_service_env() {
  local checkout_root="$1"
  local repo_root="$2"
  local record_json="$3"

  tusk_export_runtime_roots "${checkout_root}" "${repo_root}"
  export BEADS_DOLT_SERVER_MODE="server"
  export BEADS_DOLT_SERVER_HOST
  export BEADS_DOLT_SERVER_PORT
  export BEADS_DOLT_SERVER_USER
  export BEADS_DOLT_SERVER_DATABASE
  export BEADS_DOLT_DATA_DIR

  BEADS_DOLT_SERVER_HOST="$(jq -r '.backend_endpoint.host // empty' <<<"${record_json}")"
  BEADS_DOLT_SERVER_PORT="$(jq -r '.backend_endpoint.port // empty' <<<"${record_json}")"
  BEADS_DOLT_SERVER_USER="$(jq -r '.backend_runtime.user // empty' <<<"${record_json}")"
  BEADS_DOLT_SERVER_DATABASE="$(jq -r '.backend_runtime.database // empty' <<<"${record_json}")"
  BEADS_DOLT_DATA_DIR="$(jq -r '.backend_endpoint.data_dir // empty' <<<"${record_json}")"
}

main() {
  local checkout_root
  local repo_root
  local record_json

  checkout_root="$(tusk_resolve_checkout_root)"
  repo_root="$(tusk_resolve_tracker_root)"
  if [ ! -d "${repo_root}/.beads" ]; then
    tusk_export_runtime_roots "${checkout_root}" "${repo_root}"
    exec "${real_bd}" "$@"
  fi

  record_json="$(ensure_service_record "${repo_root}")"
  export_service_env "${checkout_root}" "${repo_root}" "${record_json}"
  tusk_heal_legacy_self_dolt_remote "${repo_root}" "${real_bd}"
  exec "${real_bd}" "$@"
}

main "$@"
