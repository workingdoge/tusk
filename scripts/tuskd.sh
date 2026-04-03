#!/usr/bin/env bash
set -euo pipefail

program_name="${0##*/}"

usage() {
  cat <<'EOF'
Usage:
  tuskd ensure [--repo PATH] [--socket PATH]
  tuskd status [--repo PATH] [--socket PATH]
  tuskd board-status [--repo PATH]
  tuskd receipts-status [--repo PATH]
  tuskd claim-issue [--repo PATH] [--socket PATH] --issue-id ISSUE_ID
  tuskd close-issue [--repo PATH] [--socket PATH] --issue-id ISSUE_ID --reason REASON
  tuskd serve [--repo PATH] [--socket PATH]
  tuskd query [--repo PATH] [--socket PATH] --kind KIND [--request-id ID] [--payload JSON]

Commands:
  ensure        Ensure repo-local state exists and tracker health is recorded.
  status        Print the current tracker service projection.
  board-status  Print the current board projection.
  receipts-status Print the current receipt projection.
  claim-issue   Claim one issue through the coordinator action surface.
  close-issue   Close one issue through the coordinator action surface.
  serve         Serve the local JSON protocol over a Unix socket.
  query         Query a running tuskd socket.

Protocol request kinds:
  tracker_status
  board_status
  receipts_status
  claim_issue
  close_issue
  ping
EOF
}

fail() {
  echo "${program_name}: $*" >&2
  exit 1
}

now_iso8601() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

default_repo_root() {
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
    return
  fi

  if [ -n "${BEADS_WORKSPACE_ROOT:-}" ]; then
    (
      cd "${BEADS_WORKSPACE_ROOT}"
      git rev-parse --show-toplevel 2>/dev/null || pwd
    )
    return
  fi

  if [ -n "${DEVENV_ROOT:-}" ]; then
    (
      cd "${DEVENV_ROOT}"
      git rev-parse --show-toplevel 2>/dev/null || pwd
    )
    return
  fi

  pwd
}

resolve_repo_root() {
  local repo_arg="${1:-}"

  if [ -n "${repo_arg}" ]; then
    (
      cd "${repo_arg}"
      git rev-parse --show-toplevel 2>/dev/null || pwd
    )
    return
  fi

  default_repo_root
}

state_root() {
  local repo_root="$1"
  printf '%s/.beads/tuskd\n' "${repo_root}"
}

service_path() {
  local repo_root="$1"
  printf '%s/service.json\n' "$(state_root "${repo_root}")"
}

leases_path() {
  local repo_root="$1"
  printf '%s/leases.json\n' "$(state_root "${repo_root}")"
}

receipts_path() {
  local repo_root="$1"
  printf '%s/receipts.jsonl\n' "$(state_root "${repo_root}")"
}

default_socket_path() {
  local repo_root="$1"
  printf '%s/tuskd.sock\n' "$(state_root "${repo_root}")"
}

service_key() {
  local repo_root="$1"
  printf 'bd-tracker:%s' "${repo_root}" | sha256sum | awk '{print substr($1, 1, 16)}'
}

host_state_root() {
  if [ -n "${TUSK_HOST_STATE_ROOT:-}" ]; then
    printf '%s\n' "${TUSK_HOST_STATE_ROOT}"
    return
  fi

  if [ -n "${XDG_STATE_HOME:-}" ]; then
    printf '%s/tusk\n' "${XDG_STATE_HOME}"
    return
  fi

  if [ "$(uname -s)" = "Darwin" ] && [ -n "${HOME:-}" ]; then
    printf '%s/Library/Caches/tusk\n' "${HOME}"
    return
  fi

  if [ -n "${HOME:-}" ]; then
    printf '%s/.local/state/tusk\n' "${HOME}"
    return
  fi

  printf '/tmp/tusk\n'
}

host_services_root() {
  printf '%s/services\n' "$(host_state_root)"
}

host_locks_root() {
  printf '%s/locks\n' "$(host_state_root)"
}

host_service_path() {
  local repo_root="$1"
  printf '%s/%s.json\n' "$(host_services_root)" "$(service_key "${repo_root}")"
}

host_lock_dir() {
  local repo_root="$1"
  printf '%s/%s.lock\n' "$(host_locks_root)" "$(service_key "${repo_root}")"
}

host_startup_lock_dir() {
  printf '%s/backend-startup.lock\n' "$(host_locks_root)"
}

local_backend_pid_path() {
  local repo_root="$1"
  printf '%s/.beads/dolt-server.pid\n' "${repo_root}"
}

local_backend_port_path() {
  local repo_root="$1"
  printf '%s/.beads/dolt-server.port\n' "${repo_root}"
}

metadata_path() {
  local repo_root="$1"
  printf '%s/.beads/metadata.json\n' "${repo_root}"
}

backend_host() {
  printf '127.0.0.1\n'
}

backend_data_dir() {
  local repo_root="$1"
  printf '%s/.beads/dolt\n' "${repo_root}"
}

backend_log_path() {
  local repo_root="$1"
  printf '%s/.beads/dolt-server.log\n' "${repo_root}"
}

stable_backend_port() {
  local repo_root="$1"
  local key
  local prefix

  key="$(service_key "${repo_root}")"
  prefix="${key:0:6}"
  printf '%s\n' "$((17000 + (16#${prefix} % 20000)))"
}

host_service_record() {
  local repo_root="$1"
  local path

  path="$(host_service_path "${repo_root}")"
  if [ -f "${path}" ]; then
    cat "${path}"
    return
  fi

  printf 'null\n'
}

ensure_host_state_dirs() {
  mkdir -p "$(host_services_root)" "$(host_locks_root)"
}

is_live_pid() {
  local pid="${1:-}"
  [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null
}

port_owner_pid() {
  local port="$1"
  local pid=""

  pid="$(lsof -nP -iTCP:"${port}" -sTCP:LISTEN -t 2>/dev/null | head -n1 || true)"
  if [ -n "${pid}" ]; then
    printf '%s\n' "${pid}"
  fi
}

port_matches_pid() {
  local port="$1"
  local pid="$2"
  local owner=""

  owner="$(port_owner_pid "${port}")"
  [ -n "${owner}" ] && [ "${owner}" = "${pid}" ]
}

recorded_backend_port() {
  local repo_root="$1"
  local record_json

  record_json="$(host_service_record "${repo_root}")"
  if [ "${record_json}" = "null" ]; then
    return 0
  fi

  jq -r '.backend_endpoint.port // empty' <<<"${record_json}" 2>/dev/null || true
}

recorded_backend_pid() {
  local repo_root="$1"
  local record_json

  record_json="$(host_service_record "${repo_root}")"
  if [ "${record_json}" = "null" ]; then
    return 0
  fi

  jq -r '.backend_runtime.pid // empty' <<<"${record_json}" 2>/dev/null || true
}

local_backend_port() {
  local repo_root="$1"
  local path

  path="$(local_backend_port_path "${repo_root}")"
  if [ -f "${path}" ]; then
    tr -d '[:space:]' <"${path}"
  fi
}

local_backend_pid() {
  local repo_root="$1"
  local path

  path="$(local_backend_pid_path "${repo_root}")"
  if [ -f "${path}" ]; then
    tr -d '[:space:]' <"${path}"
  fi
}

reusable_recorded_port() {
  local repo_root="$1"
  local port=""
  local pid=""

  port="$(recorded_backend_port "${repo_root}")"
  pid="$(recorded_backend_pid "${repo_root}")"

  if [ -n "${port}" ] && [ -n "${pid}" ] && is_live_pid "${pid}" && port_matches_pid "${port}" "${pid}"; then
    printf '%s\n' "${port}"
    return
  fi

  if [ -n "${port}" ] && [ -z "$(port_owner_pid "${port}")" ]; then
    printf '%s\n' "${port}"
  fi
}

reusable_local_backend_port() {
  local repo_root="$1"
  local port=""
  local pid=""

  port="$(local_backend_port "${repo_root}")"
  pid="$(local_backend_pid "${repo_root}")"

  if [ -n "${port}" ] && [ -n "${pid}" ] && is_live_pid "${pid}" && port_matches_pid "${port}" "${pid}"; then
    printf '%s\n' "${port}"
  fi
}

select_backend_port() {
  local repo_root="$1"
  local skip_port="${2:-}"
  local candidate=""
  local tries=0

  candidate="$(reusable_recorded_port "${repo_root}")"
  if [ -n "${candidate}" ] && [ "${candidate}" != "${skip_port}" ]; then
    printf '%s\n' "${candidate}"
    return
  fi

  candidate="$(reusable_local_backend_port "${repo_root}")"
  if [ -n "${candidate}" ] && [ "${candidate}" != "${skip_port}" ]; then
    printf '%s\n' "${candidate}"
    return
  fi

  candidate="$(stable_backend_port "${repo_root}")"
  while [ "${tries}" -lt 512 ]; do
    if [ "${candidate}" != "${skip_port}" ] && [ -z "$(port_owner_pid "${candidate}")" ]; then
      printf '%s\n' "${candidate}"
      return
    fi

    candidate="$((candidate + 1))"
    if [ "${candidate}" -gt 36999 ]; then
      candidate=17000
    fi
    tries="$((tries + 1))"
  done

  fail "unable to allocate a repo-scoped Dolt port for ${repo_root}"
}

acquire_service_lock() {
  local repo_root="$1"
  local lock_dir
  local holder_pid=""

  ensure_host_state_dirs
  lock_dir="$(host_lock_dir "${repo_root}")"

  while ! mkdir "${lock_dir}" 2>/dev/null; do
    holder_pid="$(cat "${lock_dir}/pid" 2>/dev/null || true)"
    if [ -n "${holder_pid}" ] && ! is_live_pid "${holder_pid}"; then
      rm -rf "${lock_dir}"
      continue
    fi
    sleep 0.1
  done

  printf '%s\n' "$$" >"${lock_dir}/pid"
  printf '%s\n' "$(now_iso8601)" >"${lock_dir}/acquired_at"
  printf '%s\n' "${lock_dir}"
}

release_service_lock() {
  local lock_dir="$1"
  if [ -n "${lock_dir}" ] && [ -d "${lock_dir}" ]; then
    rm -rf "${lock_dir}"
  fi
}

write_local_backend_runtime() {
  local repo_root="$1"
  local port="$2"
  local pid="${3:-}"

  mkdir -p "${repo_root}/.beads"
  printf '%s\n' "${port}" >"$(local_backend_port_path "${repo_root}")"

  if [ -n "${pid}" ]; then
    printf '%s\n' "${pid}" >"$(local_backend_pid_path "${repo_root}")"
  else
    rm -f "$(local_backend_pid_path "${repo_root}")"
  fi
}

clear_local_backend_runtime() {
  local repo_root="$1"

  rm -f "$(local_backend_pid_path "${repo_root}")" "$(local_backend_port_path "${repo_root}")"
}

scrub_deprecated_backend_config() {
  local repo_root="$1"
  local path
  local temp_path

  path="$(metadata_path "${repo_root}")"
  if [ ! -f "${path}" ]; then
    return 0
  fi

  temp_path="${path}.tmp.$$"
  jq 'del(.dolt_server_port)' "${path}" >"${temp_path}"
  mv "${temp_path}" "${path}"
}

acquire_startup_lock() {
  local lock_dir
  local holder_pid=""

  ensure_host_state_dirs
  lock_dir="$(host_startup_lock_dir)"

  while ! mkdir "${lock_dir}" 2>/dev/null; do
    holder_pid="$(cat "${lock_dir}/pid" 2>/dev/null || true)"
    if [ -n "${holder_pid}" ] && ! is_live_pid "${holder_pid}"; then
      rm -rf "${lock_dir}"
      continue
    fi
    sleep 0.1
  done

  printf '%s\n' "$$" >"${lock_dir}/pid"
  printf '%s\n' "$(now_iso8601)" >"${lock_dir}/acquired_at"
  printf '%s\n' "${lock_dir}"
}

configured_backend_port() {
  local repo_root="$1"
  local show_json
  local port=""

  show_json="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_backend_show" backend show)"
  if ! jq -e '.ok and ((.output | type) == "object")' >/dev/null <<<"${show_json}"; then
    return 0
  fi

  port="$(jq -r '.output.port // empty' <<<"${show_json}" 2>/dev/null || true)"
  if [ -n "${port}" ]; then
    printf '%s\n' "${port}"
  fi
}

effective_backend_port() {
  local repo_root="$1"
  local port=""

  port="$(configured_backend_port "${repo_root}")"
  if [ -n "${port}" ]; then
    printf '%s\n' "${port}"
    return
  fi

  port="$(recorded_backend_port "${repo_root}")"
  if [ -n "${port}" ]; then
    printf '%s\n' "${port}"
    return
  fi

  port="$(local_backend_port "${repo_root}")"
  if [ -n "${port}" ]; then
    printf '%s\n' "${port}"
    return
  fi

  stable_backend_port "${repo_root}"
}

backend_runtime_snapshot() {
  local repo_root="$1"
  local port=""
  local pid=""

  port="$(effective_backend_port "${repo_root}")"
  if [ -n "${port}" ]; then
    pid="$(port_owner_pid "${port}")"
  fi

  jq -cn \
    --arg checked_at "$(now_iso8601)" \
    --arg host "$(backend_host)" \
    --arg data_dir "$(backend_data_dir "${repo_root}")" \
    --arg port "${port}" \
    --arg pid "${pid}" \
    '{
      checked_at: $checked_at,
      host: $host,
      data_dir: $data_dir,
      port: (if ($port | length) > 0 then ($port | tonumber) else null end),
      pid: (if ($pid | length) > 0 then ($pid | tonumber) else null end),
      running: (($pid | length) > 0)
    }'
}

configure_backend_endpoint() {
  local repo_root="$1"
  local port="$2"

  run_tracker_capture_in_repo \
    "${repo_root}" \
    backend configure \
    --host "$(backend_host)" \
    --port "${port}" \
    --data-dir "$(backend_data_dir "${repo_root}")" >/dev/null
}

ensure_backend_connection() {
  local repo_root="$1"
  local attempt=1
  local max_attempts=4
  local skip_port=""
  local selected_port=""
  local startup_lock=""
  local service_lock=""
  local start_output=""
  local test_output=""
  local start_exit=0
  local pid=""
  local attempt_jsons="[]"
  local test_ok=false
  local ok=false

  startup_lock="$(acquire_startup_lock)"
  service_lock="$(acquire_service_lock "${repo_root}")"

  while [ "${attempt}" -le "${max_attempts}" ]; do
    selected_port="$(select_backend_port "${repo_root}" "${skip_port}")"
    configure_backend_endpoint "${repo_root}" "${selected_port}"
    write_local_backend_runtime "${repo_root}" "${selected_port}"
    scrub_deprecated_backend_config "${repo_root}"

    test_output="$(run_tracker_capture_in_repo "${repo_root}" backend test 2>/dev/null || true)"
    test_ok=false
    if [ -n "${test_output}" ] && jq -e '.connection_ok == true' >/dev/null <<<"${test_output}" 2>/dev/null; then
      test_ok=true
    else
      if start_output="$(run_tracker_capture_in_repo "${repo_root}" backend start 2>&1)"; then
        start_exit=0
      else
        start_exit=$?
      fi

      test_output="$(run_tracker_capture_in_repo "${repo_root}" backend test 2>/dev/null || true)"
      if [ -n "${test_output}" ] && jq -e '.connection_ok == true' >/dev/null <<<"${test_output}" 2>/dev/null; then
        test_ok=true
      fi
    fi

    pid="$(port_owner_pid "${selected_port}")"
    if [ "${test_ok}" = true ]; then
      write_local_backend_runtime "${repo_root}" "${selected_port}" "${pid}"
      ok=true
    fi

    attempt_jsons="$(
      jq -cn \
        --argjson prior "${attempt_jsons}" \
        --argjson attempt "${attempt}" \
        --argjson port "${selected_port}" \
        --argjson test_ok "$([ "${test_ok}" = true ] && echo true || echo false)" \
        --argjson start_ok "$([ "${start_exit}" -eq 0 ] && echo true || echo false)" \
        --arg pid "${pid}" \
        --arg start_output "${start_output}" \
        --arg test_output "${test_output}" \
        '$prior + [{
          attempt: $attempt,
          port: $port,
          test_ok: $test_ok,
          start_ok: $start_ok,
          pid: (if ($pid | length) > 0 then ($pid | tonumber) else null end),
          start_output: (if ($start_output | length) > 0 then $start_output else null end),
          test_output: (if ($test_output | length) > 0 then (try ($test_output | fromjson) catch $test_output) else null end)
        }]'
    )"

    if [ "${ok}" = true ]; then
      break
    fi

    skip_port="${selected_port}"
    start_output=""
    start_exit=0
    attempt="$((attempt + 1))"
  done

  if [ "${ok}" != true ]; then
    clear_local_backend_runtime "${repo_root}"
  fi

  release_service_lock "${service_lock}"
  release_service_lock "${startup_lock}"

  jq -cn \
    --argjson ok "$([ "${ok}" = true ] && echo true || echo false)" \
    --arg repo_root "${repo_root}" \
    --argjson attempts "${attempt_jsons}" \
    --argjson runtime "$(backend_runtime_snapshot "${repo_root}")" \
    '{
      ok: $ok,
      repo_root: $repo_root,
      attempts: $attempts,
      runtime: $runtime
    }'
}

ensure_state_files() {
  local repo_root="$1"
  local root

  root="$(state_root "${repo_root}")"
  mkdir -p "${root}"

  if [ ! -f "$(leases_path "${repo_root}")" ]; then
    printf '[]\n' >"$(leases_path "${repo_root}")"
  fi

  touch "$(receipts_path "${repo_root}")"
}

shell_quote() {
  printf '%q' "$1"
}

render_command_result() {
  local name="$1"
  local exit_code="$2"
  local output="$3"
  local ok_json

  ok_json=$([ "${exit_code}" -eq 0 ] && echo true || echo false)

  if printf '%s' "${output}" | jq -e . >/dev/null 2>&1; then
    jq -cn \
      --arg name "${name}" \
      --argjson ok "${ok_json}" \
      --argjson exit_code "${exit_code}" \
      --argjson output "${output}" \
      '{name:$name, ok:$ok, exit_code:$exit_code, output:$output}'
    return
  fi

  jq -cn \
    --arg name "${name}" \
    --argjson ok "${ok_json}" \
    --argjson exit_code "${exit_code}" \
    --arg output "${output}" \
    '{name:$name, ok:$ok, exit_code:$exit_code, output_text:$output}'
}

render_lines_result() {
  local name="$1"
  local exit_code="$2"
  local output="$3"
  local ok_json
  local lines_json

  ok_json=$([ "${exit_code}" -eq 0 ] && echo true || echo false)
  lines_json="$(printf '%s' "${output}" | jq -Rsc 'split("\n") | map(select(length > 0))')"

  jq -cn \
    --arg name "${name}" \
    --argjson ok "${ok_json}" \
    --argjson exit_code "${exit_code}" \
    --argjson output "${lines_json}" \
    '{name:$name, ok:$ok, exit_code:$exit_code, output:$output}'
}

run_in_repo_capture() {
  local repo_root="$1"
  shift

  (
    cd "${repo_root}"
    export BEADS_WORKSPACE_ROOT="${repo_root}"
    export DEVENV_ROOT="${repo_root}"
    "$@" 2>&1
  )
}

run_json_command_in_repo() {
  local repo_root="$1"
  local name="$2"
  shift 2
  local output=""
  local exit_code=0

  if output="$(run_in_repo_capture "${repo_root}" "$@")"; then
    exit_code=0
  else
    exit_code=$?
  fi

  render_command_result "${name}" "${exit_code}" "${output}"
}

run_lines_command_in_repo() {
  local repo_root="$1"
  local name="$2"
  shift 2
  local output=""
  local exit_code=0

  if output="$(run_in_repo_capture "${repo_root}" "$@")"; then
    exit_code=0
  else
    exit_code=$?
  fi

  render_lines_result "${name}" "${exit_code}" "${output}"
}

run_tracker_json_command_in_repo() {
  local repo_root="$1"
  local name="$2"
  shift 2

  run_json_command_in_repo "${repo_root}" "${name}" tusk-tracker "$@"
}

run_tracker_capture_in_repo() {
  local repo_root="$1"
  shift

  run_in_repo_capture "${repo_root}" tusk-tracker "$@"
}

live_server_pid() {
  local repo_root="$1"
  local path
  local pid=""

  path="$(service_path "${repo_root}")"
  if [ ! -f "${path}" ]; then
    return 0
  fi

  pid="$(jq -r '.tuskd.pid // empty' "${path}" 2>/dev/null || true)"
  if [ -n "${pid}" ] && kill -0 "${pid}" 2>/dev/null; then
    printf '%s\n' "${pid}"
  fi
}

health_snapshot() {
  local repo_root="$1"
  local allow_repair="$2"
  local ready_result
  local dolt_result
  local dolt_show_result
  local dolt_test_result
  local status_result
  local repair_result="null"
  local runtime_json
  local backend_json

  if [ "${allow_repair}" = "true" ]; then
    repair_result="$(ensure_backend_connection "${repo_root}")"
  fi

  ready_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_ready" ready)"
  dolt_show_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_backend_show" backend show)"
  dolt_test_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_backend_test" backend test)"
  dolt_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_backend_status" backend status)"
  status_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_status" status)"
  runtime_json="$(backend_runtime_snapshot "${repo_root}")"
  backend_json="$(
    jq -cn \
      --argjson runtime "${runtime_json}" \
      --argjson show "${dolt_show_result}" \
      'if $show.ok and (($show.output | type) == "object")
       then $runtime + $show.output
       else $runtime
       end'
  )"

  jq -cn \
    --arg checked_at "$(now_iso8601)" \
    --argjson ready "${ready_result}" \
    --argjson dolt_show "${dolt_show_result}" \
    --argjson dolt_test "${dolt_test_result}" \
    --argjson dolt "${dolt_result}" \
    --argjson status "${status_result}" \
    --argjson repair "${repair_result}" \
    --argjson backend "${backend_json}" \
    '{
      checked_at: $checked_at,
      status: (if $ready.ok and $dolt_test.ok and $status.ok then "healthy" else "unhealthy" end),
      checks: {
        tracker_ready: $ready,
        tracker_backend_show: $dolt_show,
        tracker_backend_test: $dolt_test,
        tracker_backend_status: $dolt,
        tracker_status: $status,
        backend_repair: $repair
      },
      backend: $backend,
      summary: (if $status.ok and (($status.output | type) == "object") then ($status.output.summary // null) else null end)
    }'
}

current_leases() {
  local repo_root="$1"
  local path

  path="$(leases_path "${repo_root}")"
  if [ ! -f "${path}" ]; then
    printf '[]\n'
    return
  fi

  cat "${path}"
}

write_service_record() {
  local repo_root="$1"
  local socket_path="$2"
  local mode="$3"
  local pid_json="$4"
  local health_json="$5"
  local leases_json="$6"
  local path
  local host_path
  local record

  path="$(service_path "${repo_root}")"
  host_path="$(host_service_path "${repo_root}")"
  ensure_host_state_dirs
  record="$(
    jq -cn \
      --arg generated_at "$(now_iso8601)" \
      --arg service_key "$(service_key "${repo_root}")" \
      --arg repo_root "${repo_root}" \
      --arg state_root "$(state_root "${repo_root}")" \
      --arg service_path "${path}" \
      --arg leases_path "$(leases_path "${repo_root}")" \
      --arg receipts_path "$(receipts_path "${repo_root}")" \
      --arg host_state_root "$(host_state_root)" \
      --arg host_service_path "${host_path}" \
      --arg host_lock_dir "$(host_lock_dir "${repo_root}")" \
      --arg socket_path "${socket_path}" \
      --arg backend_host "$(backend_host)" \
      --arg backend_data_dir "$(backend_data_dir "${repo_root}")" \
      --arg mode "${mode}" \
      --argjson pid "${pid_json}" \
      --argjson health "${health_json}" \
      --argjson leases "${leases_json}" \
      '{
        schema_version: 2,
        generated_at: $generated_at,
        service_kind: "bd-tracker",
        service_key: $service_key,
        repo_root: $repo_root,
        state_paths: {
          root: $state_root,
          service: $service_path,
          leases: $leases_path,
          receipts: $receipts_path
        },
        host_registry: {
          root: $host_state_root,
          service: $host_service_path,
          lock: $host_lock_dir
        },
        protocol: {
          kind: "unix",
          endpoint: $socket_path
        },
        backend_endpoint: {
          host: $backend_host,
          port: ($health.backend.port // null),
          data_dir: $backend_data_dir
        },
        backend_runtime: ($health.backend // null),
        tuskd: {
          mode: $mode,
          pid: $pid
        },
        health: $health,
        active_leases: $leases
      }'
  )"

  printf '%s\n' "${record}" >"${path}"
  printf '%s\n' "${record}" >"${host_path}"
  printf '%s\n' "${record}"
}

append_receipt() {
  local repo_root="$1"
  local kind="$2"
  local payload_json="$3"

  jq -cn \
    --arg timestamp "$(now_iso8601)" \
    --arg kind "${kind}" \
    --arg repo_root "${repo_root}" \
    --argjson payload "${payload_json}" \
    '{timestamp:$timestamp, kind:$kind, repo_root:$repo_root, payload:$payload}' \
    >>"$(receipts_path "${repo_root}")"
}

ensure_projection() {
  local repo_root="$1"
  local socket_path="$2"
  local health_json
  local leases_json
  local server_pid
  local mode
  local pid_json
  local record

  ensure_state_files "${repo_root}"
  health_json="$(health_snapshot "${repo_root}" "true")"
  leases_json="$(current_leases "${repo_root}")"
  server_pid="$(live_server_pid "${repo_root}")"

  if [ -n "${server_pid}" ]; then
    mode="serving"
    pid_json="${server_pid}"
  else
    mode="idle"
    pid_json="null"
  fi

  record="$(write_service_record "${repo_root}" "${socket_path}" "${mode}" "${pid_json}" "${health_json}" "${leases_json}")"
  append_receipt "${repo_root}" "tracker.ensure" "$(jq -cn --argjson service "${record}" '{service:$service}')"
  printf '%s\n' "${record}"
}

tracker_status_projection() {
  local repo_root="$1"
  local socket_path="$2"
  local health_json
  local leases_json
  local server_pid=""
  local pid_json="null"
  local mode="idle"

  ensure_state_files "${repo_root}"
  health_json="$(health_snapshot "${repo_root}" "false")"
  leases_json="$(current_leases "${repo_root}")"

  if server_pid="$(live_server_pid "${repo_root}")"; then
    if [ -n "${server_pid}" ]; then
      mode="serving"
      pid_json="${server_pid}"
    fi
  fi

  write_service_record "${repo_root}" "${socket_path}" "${mode}" "${pid_json}" "${health_json}" "${leases_json}"
}

board_status_projection() {
  local repo_root="$1"
  local status_result
  local ready_result
  local workspaces_result

  status_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_status" status)"
  ready_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_ready" ready)"
  workspaces_result="$(
    run_lines_command_in_repo \
      "${repo_root}" \
      "jj_workspace_list" \
      jj workspace list --ignore-working-copy --color never
  )"

  jq -cn \
    --arg repo_root "${repo_root}" \
    --arg generated_at "$(now_iso8601)" \
    --argjson status "${status_result}" \
    --argjson ready "${ready_result}" \
    --argjson workspaces "${workspaces_result}" \
    '{
      repo_root: $repo_root,
      generated_at: $generated_at,
      summary: (if $status.ok and (($status.output | type) == "object") then ($status.output.summary // null) else null end),
      ready_issues: (if $ready.ok and (($ready.output | type) == "array") then $ready.output else [] end),
      workspaces: (if $workspaces.ok and (($workspaces.output | type) == "array") then $workspaces.output else [] end),
      checks: {
        tracker_status: $status,
        tracker_ready: $ready,
        jj_workspace_list: $workspaces
      }
    }'
}

receipts_status_projection() {
  local repo_root="$1"
  local receipts_json
  local lines=""

  ensure_state_files "${repo_root}"
  if [ -f "$(receipts_path "${repo_root}")" ]; then
    lines="$(tail -n 20 "$(receipts_path "${repo_root}")" 2>/dev/null || true)"
  fi

  receipts_json="$(
    printf '%s' "${lines}" | jq -Rsc '
      split("\n")
      | map(select(length > 0))
      | map(try fromjson catch { invalid_line: . })
    '
  )"

  jq -cn \
    --arg repo_root "${repo_root}" \
    --arg generated_at "$(now_iso8601)" \
    --arg receipts_path "$(receipts_path "${repo_root}")" \
    --argjson receipts "${receipts_json}" \
    '{
      repo_root: $repo_root,
      generated_at: $generated_at,
      receipts_path: $receipts_path,
      receipts: $receipts
    }'
}

claim_issue_transition() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local claim_result
  local issue_json
  local board_json
  local board_summary
  local receipt_payload
  local payload_json

  if [ -z "${issue_id}" ]; then
    jq -cn \
      --arg message "claim_issue requires issue_id" \
      '{ok:false, error:{message:$message}}'
    return 0
  fi

  ensure_state_files "${repo_root}"
  claim_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_issue_claim" issue claim "${issue_id}")"
  if ! jq -e --arg issue_id "${issue_id}" '
      .ok and
      ((.output | type) == "array") and
      ((.output | length) > 0) and
      ((.output[0] | type) == "object") and
      ((.output[0].id // "") == $issue_id)
    ' >/dev/null <<<"${claim_result}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson tracker "${claim_result}" \
      '{
        ok: false,
        issue_id: $issue_id,
        error: { message: "tracker issue claim failed" },
        tracker: $tracker
      }'
    return 0
  fi

  issue_json="$(jq -c '.output[0]' <<<"${claim_result}")"
  tracker_status_projection "${repo_root}" "${socket_path}" >/dev/null
  board_json="$(board_status_projection "${repo_root}")"
  board_summary="$(jq -c '.summary // null' <<<"${board_json}")"
  receipt_payload="$(
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson issue "${issue_json}" \
      --argjson board_summary "${board_summary}" \
      '{
        issue_id: $issue_id,
        issue: $issue,
        board_summary: $board_summary
      }'
  )"
  append_receipt "${repo_root}" "issue.claim" "${receipt_payload}"

  payload_json="$(
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg issue_id "${issue_id}" \
      --argjson issue "${issue_json}" \
      --argjson board_summary "${board_summary}" \
      '{
        repo_root: $repo_root,
        issue_id: $issue_id,
        issue: $issue,
        board_summary: $board_summary
      }'
  )"

  jq -cn --argjson payload "${payload_json}" '{ok:true, payload:$payload}'
}

close_issue_transition() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local reason="$4"
  local close_result
  local issue_json
  local board_json
  local board_summary
  local receipt_payload
  local payload_json

  if [ -z "${issue_id}" ]; then
    jq -cn \
      --arg message "close_issue requires issue_id" \
      '{ok:false, error:{message:$message}}'
    return 0
  fi

  if [ -z "${reason}" ]; then
    jq -cn \
      --arg message "close_issue requires reason" \
      '{ok:false, error:{message:$message}}'
    return 0
  fi

  ensure_state_files "${repo_root}"
  close_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_issue_close" issue close "${issue_id}" --reason "${reason}")"
  if ! jq -e --arg issue_id "${issue_id}" '
      .ok and
      ((.output | type) == "array") and
      ((.output | length) > 0) and
      ((.output[0] | type) == "object") and
      ((.output[0].id // "") == $issue_id) and
      ((.output[0].status // "") == "closed")
    ' >/dev/null <<<"${close_result}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg reason "${reason}" \
      --argjson tracker "${close_result}" \
      '{
        ok: false,
        issue_id: $issue_id,
        reason: $reason,
        error: { message: "tracker issue close failed" },
        tracker: $tracker
      }'
    return 0
  fi

  issue_json="$(jq -c '.output[0]' <<<"${close_result}")"
  tracker_status_projection "${repo_root}" "${socket_path}" >/dev/null
  board_json="$(board_status_projection "${repo_root}")"
  board_summary="$(jq -c '.summary // null' <<<"${board_json}")"
  receipt_payload="$(
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg reason "${reason}" \
      --argjson issue "${issue_json}" \
      --argjson board_summary "${board_summary}" \
      '{
        issue_id: $issue_id,
        reason: $reason,
        issue: $issue,
        board_summary: $board_summary
      }'
  )"
  append_receipt "${repo_root}" "issue.close" "${receipt_payload}"

  payload_json="$(
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg issue_id "${issue_id}" \
      --arg reason "${reason}" \
      --argjson issue "${issue_json}" \
      --argjson board_summary "${board_summary}" \
      '{
        repo_root: $repo_root,
        issue_id: $issue_id,
        reason: $reason,
        issue: $issue,
        board_summary: $board_summary
      }'
  )"

  jq -cn --argjson payload "${payload_json}" '{ok:true, payload:$payload}'
}

respond_once() {
  local repo_root="$1"
  local socket_path="$2"
  local request_line=""
  local request_id=""
  local kind=""
  local payload="null"
  local issue_id=""
  local reason=""
  local action_result=""

  if ! IFS= read -r request_line; then
    jq -cn \
      --arg request_id "" \
      --arg kind "" \
      --arg message "missing request body" \
      '{request_id:$request_id, ok:false, kind:$kind, error:{message:$message}}'
    return 0
  fi

  if ! printf '%s' "${request_line}" | jq -e . >/dev/null 2>&1; then
    jq -cn \
      --arg request_id "" \
      --arg kind "" \
      --arg message "request was not valid JSON" \
      '{request_id:$request_id, ok:false, kind:$kind, error:{message:$message}}'
    return 0
  fi

  request_id="$(printf '%s' "${request_line}" | jq -r '.request_id // ""')"
  kind="$(printf '%s' "${request_line}" | jq -r '.kind // ""')"

  case "${kind}" in
    tracker_status)
      payload="$(tracker_status_projection "${repo_root}" "${socket_path}")"
      ;;
    board_status)
      payload="$(board_status_projection "${repo_root}")"
      ;;
    receipts_status)
      payload="$(receipts_status_projection "${repo_root}")"
      ;;
    claim_issue)
      issue_id="$(printf '%s' "${request_line}" | jq -r '.payload.issue_id // ""')"
      action_result="$(claim_issue_transition "${repo_root}" "${socket_path}" "${issue_id}")"
      if ! jq -e '.ok == true' >/dev/null <<<"${action_result}"; then
        jq -cn \
          --arg request_id "${request_id}" \
          --arg kind "${kind}" \
          --arg message "$(jq -r '.error.message // "request failed"' <<<"${action_result}")" \
          --argjson details "${action_result}" \
          '{request_id:$request_id, ok:false, kind:$kind, error:{message:$message, details:$details}}'
        return 0
      fi
      payload="$(jq -c '.payload' <<<"${action_result}")"
      ;;
    close_issue)
      issue_id="$(printf '%s' "${request_line}" | jq -r '.payload.issue_id // ""')"
      reason="$(printf '%s' "${request_line}" | jq -r '.payload.reason // ""')"
      action_result="$(close_issue_transition "${repo_root}" "${socket_path}" "${issue_id}" "${reason}")"
      if ! jq -e '.ok == true' >/dev/null <<<"${action_result}"; then
        jq -cn \
          --arg request_id "${request_id}" \
          --arg kind "${kind}" \
          --arg message "$(jq -r '.error.message // "request failed"' <<<"${action_result}")" \
          --argjson details "${action_result}" \
          '{request_id:$request_id, ok:false, kind:$kind, error:{message:$message, details:$details}}'
        return 0
      fi
      payload="$(jq -c '.payload' <<<"${action_result}")"
      ;;
    ping)
      payload="$(jq -cn --arg repo_root "${repo_root}" --arg timestamp "$(now_iso8601)" '{repo_root:$repo_root, timestamp:$timestamp, status:"ok"}')"
      ;;
    *)
      jq -cn \
        --arg request_id "${request_id}" \
        --arg kind "${kind}" \
        --arg message "unknown request kind" \
        '{request_id:$request_id, ok:false, kind:$kind, error:{message:$message}}'
      return 0
      ;;
  esac

  jq -cn \
    --arg request_id "${request_id}" \
    --arg kind "${kind}" \
    --argjson payload "${payload}" \
    '{request_id:$request_id, ok:true, kind:$kind, payload:$payload}'
}

cmd_ensure() {
  local repo_root="$1"
  local socket_path="$2"
  local projection

  projection="$(ensure_projection "${repo_root}" "${socket_path}")"
  printf '%s\n' "${projection}"

  if ! jq -e '.health.status == "healthy"' >/dev/null <<<"${projection}"; then
    return 1
  fi
}

cmd_status() {
  local repo_root="$1"
  local socket_path="$2"

  tracker_status_projection "${repo_root}" "${socket_path}"
}

cmd_board_status() {
  local repo_root="$1"

  board_status_projection "${repo_root}"
}

cmd_receipts_status() {
  local repo_root="$1"

  receipts_status_projection "${repo_root}"
}

cmd_claim_issue() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local action_result

  action_result="$(claim_issue_transition "${repo_root}" "${socket_path}" "${issue_id}")"
  if jq -e '.ok == true' >/dev/null <<<"${action_result}"; then
    jq -c '.payload' <<<"${action_result}"
    return 0
  fi

  jq -c '.' <<<"${action_result}"
  return 1
}

cmd_close_issue() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local reason="$4"
  local action_result

  action_result="$(close_issue_transition "${repo_root}" "${socket_path}" "${issue_id}" "${reason}")"
  if jq -e '.ok == true' >/dev/null <<<"${action_result}"; then
    jq -c '.payload' <<<"${action_result}"
    return 0
  fi

  jq -c '.' <<<"${action_result}"
  return 1
}

cmd_serve() {
  local repo_root="$1"
  local socket_path="$2"
  local system_cmd
  local service_json
  local idle_json
  local pid_json
  local bash_q
  local repo_q
  local socket_q
  local self_q

  ensure_state_files "${repo_root}"
  ensure_projection "${repo_root}" "${socket_path}" >/dev/null
  rm -f "${socket_path}"
  mkdir -p "$(dirname "${socket_path}")"

  printf -v repo_q '%q' "${repo_root}"
  printf -v socket_q '%q' "${socket_path}"
  printf -v self_q '%q' "$0"
  printf -v bash_q '%q' "$(command -v bash)"
  system_cmd="${bash_q} ${self_q} respond --repo ${repo_q} --socket ${socket_q}"
  pid_json="$$"

  service_json="$(write_service_record "${repo_root}" "${socket_path}" "serving" "${pid_json}" "$(health_snapshot "${repo_root}" "false")" "$(current_leases "${repo_root}")")"
  append_receipt "${repo_root}" "service.serve_started" "$(jq -cn --argjson service "${service_json}" '{service:$service}')"

  cleanup() {
    rm -f "${socket_path}"
    idle_json="$(write_service_record "${repo_root}" "${socket_path}" "idle" "null" "$(health_snapshot "${repo_root}" "false")" "$(current_leases "${repo_root}")")"
    append_receipt "${repo_root}" "service.serve_stopped" "$(jq -cn --argjson service "${idle_json}" '{service:$service}')"
  }

  trap cleanup EXIT INT TERM
  socat "UNIX-LISTEN:${socket_path},fork,mode=600" "SYSTEM:${system_cmd}"
}

cmd_query() {
  local socket_path="$1"
  local kind="$2"
  local request_id="$3"
  local payload_json="$4"
  local request_json

  if ! printf '%s' "${payload_json}" | jq -e . >/dev/null 2>&1; then
    fail "query --payload must be valid JSON"
  fi

  request_json="$(
    jq -cn \
      --arg request_id "${request_id}" \
      --arg kind "${kind}" \
      --argjson payload "${payload_json}" \
      '{request_id:$request_id, kind:$kind, payload:$payload}'
  )"
  printf '%s\n' "${request_json}" | socat -,ignoreeof "UNIX-CONNECT:${socket_path}"
}

command="${1:-}"
if [ $# -gt 0 ]; then
  shift
fi

repo_arg=""
socket_arg=""
kind_arg=""
request_id_arg=""
issue_id_arg=""
reason_arg=""
payload_arg="null"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)
      [ $# -ge 2 ] || fail "--repo requires a path"
      repo_arg="$2"
      shift 2
      ;;
    --socket)
      [ $# -ge 2 ] || fail "--socket requires a path"
      socket_arg="$2"
      shift 2
      ;;
    --kind)
      [ $# -ge 2 ] || fail "--kind requires a value"
      kind_arg="$2"
      shift 2
      ;;
    --request-id)
      [ $# -ge 2 ] || fail "--request-id requires a value"
      request_id_arg="$2"
      shift 2
      ;;
    --issue-id)
      [ $# -ge 2 ] || fail "--issue-id requires a value"
      issue_id_arg="$2"
      shift 2
      ;;
    --reason)
      [ $# -ge 2 ] || fail "--reason requires a value"
      reason_arg="$2"
      shift 2
      ;;
    --payload)
      [ $# -ge 2 ] || fail "--payload requires a JSON value"
      payload_arg="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

repo_root="$(resolve_repo_root "${repo_arg}")"
socket_path="${socket_arg:-$(default_socket_path "${repo_root}")}"

case "${command}" in
  ensure)
    cmd_ensure "${repo_root}" "${socket_path}"
    ;;
  status)
    cmd_status "${repo_root}" "${socket_path}"
    ;;
  board-status)
    cmd_board_status "${repo_root}"
    ;;
  receipts-status)
    cmd_receipts_status "${repo_root}"
    ;;
  claim-issue)
    [ -n "${issue_id_arg}" ] || fail "claim-issue requires --issue-id"
    cmd_claim_issue "${repo_root}" "${socket_path}" "${issue_id_arg}"
    ;;
  close-issue)
    [ -n "${issue_id_arg}" ] || fail "close-issue requires --issue-id"
    [ -n "${reason_arg}" ] || fail "close-issue requires --reason"
    cmd_close_issue "${repo_root}" "${socket_path}" "${issue_id_arg}" "${reason_arg}"
    ;;
  serve)
    cmd_serve "${repo_root}" "${socket_path}"
    ;;
  query)
    [ -n "${kind_arg}" ] || fail "query requires --kind"
    cmd_query "${socket_path}" "${kind_arg}" "${request_id_arg:-$(now_iso8601)}" "${payload_arg}"
    ;;
  respond)
    respond_once "${repo_root}" "${socket_path}"
    ;;
  ""|-h|--help|help)
    usage
    ;;
  *)
    fail "unknown command: ${command}"
    ;;
esac
