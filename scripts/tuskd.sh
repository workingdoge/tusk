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
  tuskd serve [--repo PATH] [--socket PATH]
  tuskd query [--repo PATH] [--socket PATH] --kind KIND [--request-id ID]

Commands:
  ensure        Ensure repo-local state exists and tracker health is recorded.
  status        Print the current tracker service projection.
  board-status  Print the current board projection.
  receipts-status Print the current receipt projection.
  serve         Serve the local JSON protocol over a Unix socket.
  query         Query a running tuskd socket.

Protocol request kinds:
  tracker_status
  board_status
  receipts_status
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
  local status_result
  local start_result="null"

  ready_result="$(run_json_command_in_repo "${repo_root}" "bd_ready" bd ready --json)"
  if [ "${allow_repair}" = "true" ] && ! jq -e '.ok' >/dev/null <<<"${ready_result}"; then
    start_result="$(run_json_command_in_repo "${repo_root}" "bd_dolt_start" bd dolt start)"
    ready_result="$(run_json_command_in_repo "${repo_root}" "bd_ready" bd ready --json)"
  fi

  dolt_result="$(run_json_command_in_repo "${repo_root}" "bd_dolt_status" bd dolt status --json)"
  status_result="$(run_json_command_in_repo "${repo_root}" "bd_status" bd status --json)"

  jq -cn \
    --arg checked_at "$(now_iso8601)" \
    --argjson ready "${ready_result}" \
    --argjson dolt "${dolt_result}" \
    --argjson status "${status_result}" \
    --argjson start "${start_result}" \
    '{
      checked_at: $checked_at,
      status: (if $ready.ok and $dolt.ok then "healthy" else "unhealthy" end),
      checks: {
        bd_ready: $ready,
        bd_dolt_status: $dolt,
        bd_status: $status,
        bd_dolt_start: $start
      },
      backend: (if $dolt.ok and (($dolt.output | type) == "object") then $dolt.output else null end),
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
  local record

  path="$(service_path "${repo_root}")"
  record="$(
    jq -cn \
      --arg generated_at "$(now_iso8601)" \
      --arg repo_root "${repo_root}" \
      --arg state_root "$(state_root "${repo_root}")" \
      --arg service_path "${path}" \
      --arg leases_path "$(leases_path "${repo_root}")" \
      --arg receipts_path "$(receipts_path "${repo_root}")" \
      --arg socket_path "${socket_path}" \
      --arg mode "${mode}" \
      --argjson pid "${pid_json}" \
      --argjson health "${health_json}" \
      --argjson leases "${leases_json}" \
      '{
        schema_version: 1,
        generated_at: $generated_at,
        service_kind: "bd-tracker",
        repo_root: $repo_root,
        state_paths: {
          root: $state_root,
          service: $service_path,
          leases: $leases_path,
          receipts: $receipts_path
        },
        protocol: {
          kind: "unix",
          endpoint: $socket_path
        },
        tuskd: {
          mode: $mode,
          pid: $pid
        },
        health: $health,
        active_leases: $leases
      }'
  )"

  printf '%s\n' "${record}" >"${path}"
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

  status_result="$(run_json_command_in_repo "${repo_root}" "bd_status" bd status --json)"
  ready_result="$(run_json_command_in_repo "${repo_root}" "bd_ready" bd ready --json)"
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
        bd_status: $status,
        bd_ready: $ready,
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

respond_once() {
  local repo_root="$1"
  local socket_path="$2"
  local request_line=""
  local request_id=""
  local kind=""
  local payload="null"

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

  ensure_projection "${repo_root}" "${socket_path}"
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
  local request_json

  request_json="$(jq -cn --arg request_id "${request_id}" --arg kind "${kind}" '{request_id:$request_id, kind:$kind}')"
  printf '%s\n' "${request_json}" | socat - "UNIX-CONNECT:${socket_path}"
}

command="${1:-}"
if [ $# -gt 0 ]; then
  shift
fi

repo_arg=""
socket_arg=""
kind_arg=""
request_id_arg=""

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
  serve)
    cmd_serve "${repo_root}" "${socket_path}"
    ;;
  query)
    [ -n "${kind_arg}" ] || fail "query requires --kind"
    cmd_query "${socket_path}" "${kind_arg}" "${request_id_arg:-$(now_iso8601)}"
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
