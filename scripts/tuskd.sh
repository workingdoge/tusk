#!/usr/bin/env bash
set -euo pipefail

program_name="tuskd"
paths_sh="${TUSK_PATHS_SH:?TUSK_PATHS_SH is required}"

source "${paths_sh}"

usage() {
  cat <<'EOF'
Usage:
  tuskd core-seam [--json]
  tuskd ensure [--repo PATH] [--socket PATH]
  tuskd status [--repo PATH] [--socket PATH]
  tuskd coordinator-status [--repo PATH]
  tuskd operator-snapshot [--repo PATH] [--socket PATH]
  tuskd board-status [--repo PATH]
  tuskd receipts-status [--repo PATH]
  tuskd self-host-run [--repo PATH] [--checkout PATH] [--realization ID] [--note TEXT] [--plan]
  tuskd land-main [--repo PATH] --revision REV [--note TEXT] [--plan]
  tuskd repair-coordinator [--repo PATH] [--target-rev REV] [--note TEXT] [--plan]
  tuskd claim-issue [--repo PATH] [--socket PATH] --issue-id ISSUE_ID
  tuskd close-issue [--repo PATH] [--socket PATH] --issue-id ISSUE_ID --reason REASON
  tuskd launch-lane [--repo PATH] [--socket PATH] --issue-id ISSUE_ID --base-rev REV [--slug SLUG]
  tuskd handoff-lane [--repo PATH] [--socket PATH] --issue-id ISSUE_ID --revision REV [--note TEXT]
  tuskd finish-lane [--repo PATH] [--socket PATH] --issue-id ISSUE_ID --outcome OUTCOME [--note TEXT]
  tuskd archive-lane [--repo PATH] [--socket PATH] --issue-id ISSUE_ID [--note TEXT]
  tuskd compact-lane [--repo PATH] [--socket PATH] --issue-id ISSUE_ID --reason REASON [--revision REV] [--outcome OUTCOME] [--note TEXT] [--quarantine]
  tuskd serve [--repo PATH] [--socket PATH]
  tuskd query [--repo PATH] [--socket PATH] --kind KIND [--request-id ID] [--payload JSON]

Commands:
  core-seam     Print the first Rust-owned backend/service seam contract.
  ensure        Ensure repo-local state exists and tracker health is recorded.
  status        Print the current tracker service projection.
  coordinator-status Print the default-workspace drift projection.
  operator-snapshot Print the compact operator-facing home projection.
  board-status  Print the current board projection.
  receipts-status Print the current receipt projection.
  self-host-run Execute the first self-host build/check loop and record receipts.
  land-main     Land one revision onto exported main, export Git state, and sync the coordinator checkout.
  repair-coordinator Rebase the default coordinator workspace onto current main and record a receipt.
  claim-issue   Claim one issue through the coordinator action surface.
  close-issue   Close one issue through the coordinator action surface.
  launch-lane   Create one dedicated issue workspace through the coordinator action surface.
  handoff-lane  Record a lane handoff with an explicit revision.
  finish-lane   Record a terminal lane outcome without collapsing into issue closure.
  archive-lane  Remove one finished lane from live state once its workspace is gone.
  compact-lane  Compact one live lane through handoff, finish, workspace cleanup, archive, and close.
  serve         Serve the local JSON protocol over a Unix socket.
  query         Query one tuskd protocol request; read kinds are handled locally, actions still require a live socket.

Protocol request kinds:
  tracker_status
  coordinator_status
  operator_snapshot
  board_status
  receipts_status
  self_host_status
  claim_issue
  close_issue
  launch_lane
  handoff_lane
  finish_lane
  archive_lane
  ping
EOF
}

fail() {
  render_actionable_summary "${command:-}" "$*" "" >&2 || true
  exit 1
}

summary_next_action() {
  local command_name="$1"
  local message="$2"
  local details_json="${3:-}"
  local issue_id=""
  local issue_status=""
  local workspace_path=""

  if [ -n "${details_json}" ] && [ "${details_json}" != "null" ]; then
    issue_id="$(jq -r '.issue_id // .error.details.issue_id // .error.carrier.intent.payload.issue_id // ""' <<<"${details_json}" 2>/dev/null || true)"
    issue_status="$(jq -r '.status // .error.details.status // .error.carrier.issue.status // ""' <<<"${details_json}" 2>/dev/null || true)"
    workspace_path="$(jq -r '.workspace_path // .error.details.workspace_path // .error.carrier.workspace.path // ""' <<<"${details_json}" 2>/dev/null || true)"
  fi

  case "${message}" in
    *"requires --issue-id"*)
      printf 'retry with the lane issue id: tuskd %s --repo <repo> --issue-id <issue>' "${command_name}"
      ;;
    *"requires --revision"*)
      if [ "${command_name}" = "land-main" ]; then
        printf 'retry with the visible revision: tuskd %s --repo <repo> --revision <rev>' "${command_name}"
      else
        printf 'retry with the visible revision: tuskd %s --repo <repo> --issue-id <issue> --revision <rev>' "${command_name}"
      fi
      ;;
    *"requires --reason"*)
      printf 'retry with a closure reason: tuskd %s --repo <repo> --issue-id <issue> --reason \"completed in visible commit <rev>\"' "${command_name}"
      ;;
    *"requires --outcome"*)
      printf 'retry with an explicit outcome: tuskd %s --repo <repo> --issue-id <issue> --outcome completed' "${command_name}"
      ;;
    *"requires --base-rev"*)
      printf 'retry with an explicit base revision: tuskd %s --repo <repo> --issue-id <issue> --base-rev main' "${command_name}"
      ;;
    "claim_issue requires a ready issue")
      printf 'pick a ready issue first: nix run .#bd -- ready --json or nix run .#tuskd -- operator-snapshot --repo <repo>'
      ;;
    "claim_issue requires an open issue")
      if [ "${issue_status}" = "in_progress" ]; then
        printf 'that issue is already claimed or active; pick another open issue or launch/finish its existing lane'
      elif [ "${issue_status}" = "closed" ]; then
        printf 'pick a non-closed issue id before retrying claim-issue'
      else
        printf 'choose an open issue id before retrying claim-issue'
      fi
      ;;
    "launch_lane requires no existing live lane")
      printf 'finish or archive the existing live lane before launching another one for this issue'
      ;;
    "handoff_lane requires an existing lane record")
      printf 'launch a lane for %s before handing it off' "${issue_id:-<issue>}"
      ;;
    "finish_lane requires an existing lane record")
      printf 'launch a lane for %s before finishing it' "${issue_id:-<issue>}"
      ;;
    "archive_lane requires a finished lane")
      printf 'run tuskd finish-lane --repo <repo> --issue-id %s --outcome completed before archiving' "${issue_id:-<issue>}"
      ;;
    "archive_lane requires the lane workspace to be removed first")
      if [ -n "${workspace_path}" ]; then
        printf 'forget and remove or quarantine %s, then rerun tuskd archive-lane --repo <repo> --issue-id %s' "${workspace_path}" "${issue_id:-<issue>}"
      else
        printf 'forget and remove or quarantine the lane workspace, then rerun tuskd archive-lane --repo <repo> --issue-id %s' "${issue_id:-<issue>}"
      fi
      ;;
    "close_issue requires the live lane to be archived first")
      printf 'archive the live lane for %s before closing the issue' "${issue_id:-<issue>}"
      ;;
    *)
      return 1
      ;;
  esac
}

render_actionable_summary() {
  local command_name="$1"
  local message="$2"
  local details_json="${3:-}"
  local next_action=""

  [ -n "${message}" ] || return 1

  printf '%s: %s\n' "${program_name}" "${message}"
  if next_action="$(summary_next_action "${command_name}" "${message}" "${details_json}")"; then
    printf 'next: %s\n' "${next_action}"
  fi
}

require_tuskd_core_bin() {
  local bin="${TUSKD_CORE_BIN:-}"

  [ -n "${bin}" ] || fail "TUSKD_CORE_BIN is not set"
  [ -x "${bin}" ] || fail "TUSKD_CORE_BIN is not executable: ${bin}"
  printf '%s\n' "${bin}"
}

exec_tuskd_core() {
  local bin

  bin="$(require_tuskd_core_bin)"
  exec "${bin}" "$@"
}

run_tuskd_core() {
  local bin

  bin="$(require_tuskd_core_bin)"
  "${bin}" "$@"
}

now_iso8601() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

port_is_valid() {
  local port="${1:-}"

  case "${port}" in
    ''|*[!0-9]*)
      return 1
      ;;
  esac

  [ "${port}" -ge 1 ] && [ "${port}" -le 65535 ]
}

resolve_repo_root() {
  local repo_arg="${1:-}"
  tusk_resolve_tracker_root "${repo_arg}"
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

lanes_path() {
  local repo_root="$1"
  printf '%s/lanes.json\n' "$(state_root "${repo_root}")"
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

workspace_root_dir() {
  local repo_root="$1"
  printf '%s/.jj-workspaces\n' "${repo_root}"
}

slugify_fragment() {
  local input="${1:-}"

  printf '%s' "${input}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g'
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

parse_dolt_sql_server_port() {
  local command="${1:-}"
  local port=""

  case "${command}" in
    *dolt*sql-server*)
      ;;
    *)
      return 0
      ;;
  esac

  port="$(
    awk '
      {
        for (i = 1; i <= NF; i++) {
          if ($i == "-P" && i < NF) {
            print $(i + 1)
            exit
          }
          if ($i ~ /^-P[0-9]+$/) {
            print substr($i, 3)
            exit
          }
        }
      }
    ' <<<"${command}"
  )"

  if port_is_valid "${port}"; then
    printf '%s\n' "${port}"
  fi
}

live_server_port_for_pid() {
  local pid="$1"
  local command=""
  local port=""

  if ! is_live_pid "${pid}"; then
    return 0
  fi

  command="$(ps -p "${pid}" -o command= 2>/dev/null || true)"
  port="$(parse_dolt_sql_server_port "${command}")"
  if [ -n "${port}" ] && port_matches_pid "${port}" "${pid}"; then
    printf '%s\n' "${port}"
  fi
}

recorded_backend_port() {
  local repo_root="$1"
  local record_json
  local port=""

  record_json="$(host_service_record "${repo_root}")"
  if [ "${record_json}" = "null" ]; then
    return 0
  fi

  port="$(jq -r '.backend_endpoint.port // empty' <<<"${record_json}" 2>/dev/null || true)"
  if port_is_valid "${port}"; then
    printf '%s\n' "${port}"
  fi
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
  local port=""

  path="$(local_backend_port_path "${repo_root}")"
  if [ -f "${path}" ]; then
    port="$(tr -d '[:space:]' <"${path}")"
    if port_is_valid "${port}"; then
      printf '%s\n' "${port}"
    fi
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

  pid="$(recorded_backend_pid "${repo_root}")"

  if [ -n "${pid}" ]; then
    port="$(live_server_port_for_pid "${pid}")"
  fi
  if [ -n "${port}" ]; then
    printf '%s\n' "${port}"
    return
  fi

  port="$(recorded_backend_port "${repo_root}")"

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

  pid="$(local_backend_pid "${repo_root}")"
  if [ -n "${pid}" ]; then
    port="$(live_server_port_for_pid "${pid}")"
  fi
  if [ -n "${port}" ]; then
    printf '%s\n' "${port}"
    return
  fi

  port="$(local_backend_port "${repo_root}")"

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
  if port_is_valid "${port}"; then
    printf '%s\n' "${port}"
  fi
}

effective_backend_port() {
  local repo_root="$1"
  local port=""

  port="$(reusable_local_backend_port "${repo_root}")"
  if [ -n "${port}" ]; then
    printf '%s\n' "${port}"
    return
  fi

  port="$(reusable_recorded_port "${repo_root}")"
  if [ -n "${port}" ]; then
    printf '%s\n' "${port}"
    return
  fi

  port="$(configured_backend_port "${repo_root}")"
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

  if [ ! -f "$(lanes_path "${repo_root}")" ]; then
    printf '[]\n' >"$(lanes_path "${repo_root}")"
  fi

  touch "$(receipts_path "${repo_root}")"
}

shell_quote() {
  printf '%q' "$1"
}

extract_json_output() {
  local output="$1"
  local candidate=""

  if printf '%s' "${output}" | jq -e . >/dev/null 2>&1; then
    printf '%s' "${output}"
    return 0
  fi

  candidate="$(printf '%s\n' "${output}" | awk 'BEGIN { capture = 0 } /^[[:space:]]*[{[]/ { capture = 1 } capture { print }')"
  if [ -n "${candidate}" ] && printf '%s' "${candidate}" | jq -e . >/dev/null 2>&1; then
    printf '%s' "${candidate}"
    return 0
  fi

  return 1
}

render_command_result() {
  local name="$1"
  local exit_code="$2"
  local output="$3"
  local ok_json
  local parsed_output=""

  ok_json=$([ "${exit_code}" -eq 0 ] && echo true || echo false)

  if parsed_output="$(extract_json_output "${output}")"; then
    jq -cn \
      --arg name "${name}" \
      --argjson ok "${ok_json}" \
      --argjson exit_code "${exit_code}" \
      --argjson output "${parsed_output}" \
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
    tusk_export_runtime_roots "${repo_root}" "${repo_root}"
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
      --arg lanes_path "$(lanes_path "${repo_root}")" \
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
          receipts: $receipts_path,
          lanes: $lanes_path
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

current_service_record() {
  local repo_root="$1"
  local path

  path="$(service_path "${repo_root}")"
  if [ ! -f "${path}" ]; then
    printf 'null\n'
    return
  fi

  cat "${path}"
}

append_receipt() {
  local repo_root="$1"
  local kind="$2"
  local payload_json="$3"

  run_tuskd_core receipt append --repo "${repo_root}" --kind "${kind}" --payload "${payload_json}" >/dev/null
}

append_receipt_capture() {
  local repo_root="$1"
  local kind="$2"
  local payload_json="$3"

  run_tuskd_core receipt append --repo "${repo_root}" --kind "${kind}" --payload "${payload_json}"
}

current_lanes() {
  local repo_root="$1"
  local path

  path="$(lanes_path "${repo_root}")"
  if [ ! -f "${path}" ]; then
    printf '[]\n'
    return
  fi

  cat "${path}"
}

current_lane_for_issue() {
  local repo_root="$1"
  local issue_id="$2"

  jq -c --arg issue_id "${issue_id}" '
    map(select(.issue_id == $issue_id)) | .[0] // null
  ' <<<"$(current_lanes "${repo_root}")"
}

issue_receipt_refs() {
  local repo_root="$1"
  local issue_id="$2"
  local path

  path="$(receipts_path "${repo_root}")"
  if [ -z "${issue_id}" ] || [ ! -f "${path}" ]; then
    printf '[]\n'
    return
  fi

  jq -Rsc --arg issue_id "${issue_id}" '
    split("\n")
    | map(select(length > 0) | (try fromjson catch empty))
    | map(select((.payload.issue_id // "") == $issue_id) | {timestamp, kind})
  ' <"${path}"
}

issue_snapshot_from_result() {
  local result_json="$1"

  jq -c '
    if .ok and
       ((.output | type) == "array") and
       ((.output | length) > 0) and
       ((.output[0] | type) == "object")
    then .output[0]
    else null
    end
  ' <<<"${result_json}"
}

resolve_revision_commit() {
  local repo_root="$1"
  local revision="$2"
  local lookup_output=""
  local lookup_exit=0
  local commit=""

  if lookup_output="$(run_in_repo_capture "${repo_root}" jj --repository "${repo_root}" log -r "${revision}" --no-graph -T 'commit_id ++ "\n"')"; then
    lookup_exit=0
  else
    lookup_exit=$?
  fi

  commit="$(printf '%s' "${lookup_output}" | awk 'NF { print; exit }')"

  jq -cn \
    --arg revision "${revision}" \
    --arg output "${lookup_output}" \
    --arg commit "${commit}" \
    --argjson ok "$([ "${lookup_exit}" -eq 0 ] && [ -n "${commit}" ] && echo true || echo false)" \
    '{
      ok: $ok,
      revision: $revision,
      output: (if ($output | length) > 0 then $output else null end),
      commit: (if ($commit | length) > 0 then $commit else null end)
    }'
}

resolve_git_ref_commit() {
  local repo_root="$1"
  local ref_name="$2"
  local lookup_output=""
  local lookup_exit=0
  local commit=""

  if lookup_output="$(run_in_repo_capture "${repo_root}" git rev-parse --verify "${ref_name}")"; then
    lookup_exit=0
  else
    lookup_exit=$?
  fi

  commit="$(printf '%s' "${lookup_output}" | awk 'NF { print; exit }')"

  jq -cn \
    --arg ref_name "${ref_name}" \
    --arg output "${lookup_output}" \
    --arg commit "${commit}" \
    --argjson ok "$([ "${lookup_exit}" -eq 0 ] && [ -n "${commit}" ] && echo true || echo false)" \
    '{
      ok: $ok,
      ref: $ref_name,
      output: (if ($output | length) > 0 then $output else null end),
      commit: (if ($commit | length) > 0 then $commit else null end)
    }'
}

json_bool() {
  if [ "${1:-false}" = "true" ]; then
    printf 'true\n'
  else
    printf 'false\n'
  fi
}

transition_test_fail_phase() {
  local kind="$1"
  local phase="$2"
  local requested="${TUSKD_TEST_FAIL_PHASE:-}"

  [ -n "${requested}" ] && [ "${requested}" = "${kind}:${phase}" ]
}

new_transition_carrier() {
  local repo_root="$1"
  local kind="$2"
  local payload_json="${3:-null}"

  jq -cn \
    --arg generated_at "$(now_iso8601)" \
    --arg repo_root "${repo_root}" \
    --arg service_key "$(service_key "${repo_root}")" \
    --arg workspace_root "$(workspace_root_dir "${repo_root}")" \
    --arg request_id "$$-$(date +%s)" \
    --arg kind "${kind}" \
    --argjson payload "${payload_json}" \
    '{
      generated_at: $generated_at,
      repo: {
        root: $repo_root,
        service_key: $service_key,
        workspace_root: $workspace_root,
        request_id: $request_id
      },
      tracker: null,
      service: null,
      issue: null,
      lane: null,
      workspace: null,
      witnesses: [],
      intent: {
        kind: $kind,
        payload: $payload
      },
      admission: null,
      realization: null,
      receipts: {
        prior: [],
        emitted: null
      }
    }'
}

carrier_set_tracker() {
  local carrier_json="$1"
  local tracker_json="$2"
  jq -c --argjson tracker "${tracker_json}" '.tracker = $tracker' <<<"${carrier_json}"
}

carrier_set_service() {
  local carrier_json="$1"
  local service_json="$2"
  jq -c --argjson service "${service_json}" '.service = $service' <<<"${carrier_json}"
}

carrier_set_issue() {
  local carrier_json="$1"
  local issue_json="$2"
  jq -c --argjson issue "${issue_json}" '.issue = $issue' <<<"${carrier_json}"
}

carrier_set_lane() {
  local carrier_json="$1"
  local lane_json="$2"
  jq -c --argjson lane "${lane_json}" '.lane = $lane' <<<"${carrier_json}"
}

carrier_set_workspace() {
  local carrier_json="$1"
  local workspace_json="$2"
  jq -c --argjson workspace "${workspace_json}" '.workspace = $workspace' <<<"${carrier_json}"
}

carrier_set_receipt_refs() {
  local carrier_json="$1"
  local prior_json="$2"
  jq -c --argjson prior "${prior_json}" '.receipts.prior = $prior' <<<"${carrier_json}"
}

carrier_add_witness() {
  local carrier_json="$1"
  local kind="$2"
  local ok_json="$3"
  local message="$4"
  local details_json="${5:-null}"

  jq -c \
    --arg kind "${kind}" \
    --argjson ok "${ok_json}" \
    --arg message "${message}" \
    --argjson details "${details_json}" \
    '.witnesses += [{
      kind: $kind,
      ok: $ok,
      message: (if ($message | length) > 0 then $message else null end),
      details: $details
    }]' \
    <<<"${carrier_json}"
}

carrier_set_admission() {
  local carrier_json="$1"
  local admitted_json="$2"
  local reason="$3"
  local consulted_json="${4:-[]}"

  jq -c \
    --argjson admitted "${admitted_json}" \
    --arg reason "${reason}" \
    --argjson consulted "${consulted_json}" \
    '.admission = {
      admitted: $admitted,
      reason: (if ($reason | length) > 0 then $reason else null end),
      consulted: $consulted
    }' \
    <<<"${carrier_json}"
}

carrier_set_realization() {
  local carrier_json="$1"
  local realization_json="$2"
  jq -c --argjson realization "${realization_json}" '.realization = $realization' <<<"${carrier_json}"
}

carrier_set_emitted_receipt() {
  local carrier_json="$1"
  local receipt_json="$2"
  jq -c --argjson receipt "${receipt_json}" '.receipts.emitted = $receipt' <<<"${carrier_json}"
}

transition_service_snapshot() {
  local repo_root="$1"
  local socket_path="$2"

  jq -cn \
    --arg socket_path "${socket_path}" \
    --argjson record "$(current_service_record "${repo_root}")" \
    --argjson leases "$(current_leases "${repo_root}")" \
    --argjson backend "$(backend_runtime_snapshot "${repo_root}")" \
    '{
      socket_path: $socket_path,
      record: $record,
      leases: $leases,
      backend: $backend
    }'
}

transition_workspace_snapshot() {
  local workspace_name="$1"
  local workspace_path="$2"
  local base_rev="${3:-}"
  local base_commit="${4:-}"
  local revision="${5:-}"
  local exists=false

  if [ -n "${workspace_path}" ] && [ -e "${workspace_path}" ]; then
    exists=true
  fi

  jq -cn \
    --arg workspace_name "${workspace_name}" \
    --arg workspace_path "${workspace_path}" \
    --arg base_rev "${base_rev}" \
    --arg base_commit "${base_commit}" \
    --arg revision "${revision}" \
    --argjson exists "$(json_bool "${exists}")" \
    '{
      name: (if ($workspace_name | length) > 0 then $workspace_name else null end),
      path: (if ($workspace_path | length) > 0 then $workspace_path else null end),
      exists: $exists,
      base_rev: (if ($base_rev | length) > 0 then $base_rev else null end),
      base_commit: (if ($base_commit | length) > 0 then $base_commit else null end),
      revision: (if ($revision | length) > 0 then $revision else null end)
    }'
}

transition_rejected_result() {
  local carrier_json="$1"

  jq -cn \
    --argjson carrier "${carrier_json}" \
    '{
      ok: false,
      error: {
        message: ($carrier.admission.reason // "transition rejected"),
        carrier: $carrier
      }
    }'
}

transition_failure_result() {
  local carrier_json="$1"
  local message="$2"
  local details_json="${3:-null}"

  jq -cn \
    --arg message "${message}" \
    --argjson carrier "${carrier_json}" \
    --argjson details "${details_json}" \
    '{
      ok: false,
      error: {
        message: $message,
        carrier: $carrier,
        details: $details
      }
    }'
}

transition_success_result() {
  local carrier_json="$1"
  local payload_json="$2"

  jq -cn \
    --argjson carrier "${carrier_json}" \
    --argjson payload "${payload_json}" \
    '{ok:true, carrier:$carrier, payload:$payload}'
}

is_action_request_kind() {
  case "${1:-}" in
    claim_issue|close_issue|launch_lane|handoff_lane|finish_lane|archive_lane)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

prepare_transition_action() {
  local repo_root="$1"
  local socket_path="$2"
  local kind="$3"
  local payload_json="$4"

  run_tuskd_core action-prepare \
    --repo "${repo_root}" \
    --socket "${socket_path}" \
    --kind "${kind}" \
    --payload "${payload_json}"
}

realize_transition_delegate() {
  local repo_root="$1"
  local socket_path="$2"
  local kind="$3"
  local carrier_json="$4"
  local realize_fn=""
  local action_result=""

  case "${kind}" in
    claim_issue)
      realize_fn=realize_claim_issue_transition
      ;;
    close_issue)
      realize_fn=realize_close_issue_transition
      ;;
    launch_lane)
      realize_fn=realize_launch_lane_transition
      ;;
    handoff_lane)
      realize_fn=realize_handoff_lane_transition
      ;;
    finish_lane)
      realize_fn=realize_finish_lane_transition
      ;;
    archive_lane)
      realize_fn=realize_archive_lane_transition
      ;;
    *)
      jq -cn --arg kind "${kind}" '{ok:false, error:{message:"unknown transition kind", kind:$kind}}'
      return 0
      ;;
  esac

  if ! action_result="$("${realize_fn}" "${repo_root}" "${socket_path}" "${carrier_json}")"; then
    transition_failure_result "${carrier_json}" "transition realization failed"
    return 0
  fi

  printf '%s\n' "${action_result}"
}

upsert_lane_state() {
  local repo_root="$1"
  local lane_json="$2"

  run_tuskd_core lane-state upsert --repo "${repo_root}" --lane-json "${lane_json}" >/dev/null
}

remove_lane_state() {
  local repo_root="$1"
  local issue_id="$2"

  run_tuskd_core lane-state remove --repo "${repo_root}" --issue-id "${issue_id}" >/dev/null
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

lane_state_projection() {
  local repo_root="$1"
  local lanes_json="[]"
  local projected_json="[]"
  local lane_json=""
  local workspace_path=""
  local workspace_exists=false
  local stored_status=""
  local observed_status=""

  ensure_state_files "${repo_root}"
  lanes_json="$(current_lanes "${repo_root}")"

  while IFS= read -r lane_json; do
    [ -n "${lane_json}" ] || continue
    workspace_path="$(jq -r '.workspace_path // ""' <<<"${lane_json}")"
    workspace_exists=false
    if [ -n "${workspace_path}" ] && [ -d "${workspace_path}" ]; then
      workspace_exists=true
    fi

    stored_status="$(jq -r '.status // "launched"' <<<"${lane_json}")"
    if [ "${workspace_exists}" = true ]; then
      observed_status="${stored_status}"
    elif [ "${stored_status}" = "finished" ]; then
      observed_status="${stored_status}"
    else
      observed_status="stale"
    fi

    lane_json="$(
      jq -c \
        --argjson workspace_exists "$([ "${workspace_exists}" = true ] && echo true || echo false)" \
        --arg observed_status "${observed_status}" \
        '. + {workspace_exists:$workspace_exists, observed_status:$observed_status}' \
        <<<"${lane_json}"
    )"
    projected_json="$(jq -c --argjson lane "${lane_json}" '. + [$lane]' <<<"${projected_json}")"
  done < <(jq -c '.[]' <<<"${lanes_json}")

  printf '%s\n' "${projected_json}"
}

board_status_projection() {
  local repo_root="$1"
  local status_result
  local ready_result
  local board_issues_result
  local workspaces_result
  local lanes_json

  status_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_status" status)"
  ready_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_ready" ready)"
  board_issues_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_board_issues" issues board)"
  workspaces_result="$(
    run_lines_command_in_repo \
      "${repo_root}" \
      "jj_workspace_list" \
      jj workspace list --ignore-working-copy --color never
  )"
  lanes_json="$(lane_state_projection "${repo_root}")"

  jq -cn \
    --arg repo_root "${repo_root}" \
    --arg generated_at "$(now_iso8601)" \
    --argjson status "${status_result}" \
    --argjson ready "${ready_result}" \
    --argjson board_issues "${board_issues_result}" \
    --argjson workspaces "${workspaces_result}" \
    --argjson lanes "${lanes_json}" \
    '{
      repo_root: $repo_root,
      generated_at: $generated_at,
      summary: (if $status.ok and (($status.output | type) == "object") then ($status.output.summary // null) else null end),
      ready_issues: (if $ready.ok and (($ready.output | type) == "array") then $ready.output else [] end),
      claimed_issues: (
        if $board_issues.ok and (($board_issues.output | type) == "object")
        then (
          ($board_issues.output.claimed_issues // [])
          | map(select(.id as $id | (($lanes | map(.issue_id)) | index($id) | not)))
        )
        else []
        end
      ),
      blocked_issues: (
        if $board_issues.ok and (($board_issues.output | type) == "object")
        then ($board_issues.output.blocked_issues // [])
        else []
        end
      ),
      deferred_issues: (
        if $board_issues.ok and (($board_issues.output | type) == "object")
        then ($board_issues.output.deferred_issues // [])
        else []
        end
      ),
      lanes: $lanes,
      workspaces: (if $workspaces.ok and (($workspaces.output | type) == "array") then $workspaces.output else [] end),
      checks: {
        tracker_status: $status,
        tracker_ready: $ready,
        tracker_board_issues: $board_issues,
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

launch_lane_transition() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local base_rev="$4"
  local slug_arg="${5:-}"
  local issue_result
  local issue_json
  local issue_title
  local slug
  local workspace_name
  local workspace_path
  local base_lookup_output=""
  local base_lookup_exit=0
  local base_commit=""
  local add_output=""
  local add_exit=0
  local describe_output=""
  local describe_exit=0
  local board_json
  local board_summary
  local lanes_json
  local lane_record
  local receipt_payload
  local payload_json

  if [ -z "${issue_id}" ]; then
    jq -cn \
      --arg message "launch_lane requires issue_id" \
      '{ok:false, error:{message:$message}}'
    return 0
  fi

  if [ -z "${base_rev}" ]; then
    jq -cn \
      --arg message "launch_lane requires base_rev" \
      '{ok:false, error:{message:$message}}'
    return 0
  fi

  ensure_state_files "${repo_root}"
  issue_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_issue_show" issue show "${issue_id}")"
  if ! jq -e --arg issue_id "${issue_id}" '
      .ok and
      ((.output | type) == "array") and
      ((.output | length) > 0) and
      ((.output[0] | type) == "object") and
      ((.output[0].id // "") == $issue_id)
    ' >/dev/null <<<"${issue_result}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson tracker "${issue_result}" \
      '{
        ok: false,
        issue_id: $issue_id,
        error: { message: "tracker issue show failed" },
        tracker: $tracker
      }'
    return 0
  fi

  issue_json="$(jq -c '.output[0]' <<<"${issue_result}")"
  if ! jq -e '.status == "in_progress"' >/dev/null <<<"${issue_json}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson issue "${issue_json}" \
      '{
        ok: false,
        issue_id: $issue_id,
        error: { message: "launch_lane requires a claimed in_progress issue" },
        issue: $issue
      }'
    return 0
  fi

  issue_title="$(jq -r '.title // ""' <<<"${issue_json}")"
  slug="${slug_arg}"
  if [ -z "${slug}" ]; then
    slug="$(slugify_fragment "${issue_title}")"
  fi
  if [ -z "${slug}" ]; then
    slug="lane"
  fi

  workspace_name="${issue_id}-${slug}"
  workspace_path="$(workspace_root_dir "${repo_root}")/${workspace_name}"

  if [ -e "${workspace_path}" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg workspace_name "${workspace_name}" \
      --arg workspace_path "${workspace_path}" \
      '{
        ok: false,
        issue_id: $issue_id,
        error: { message: "workspace path already exists" },
        workspace_name: $workspace_name,
        workspace_path: $workspace_path
      }'
    return 0
  fi

  if base_lookup_output="$(run_in_repo_capture "${repo_root}" jj --repository "${repo_root}" log -r "${base_rev}" --no-graph -T 'commit_id ++ "\n"')"; then
    base_lookup_exit=0
  else
    base_lookup_exit=$?
  fi
  base_commit="$(printf '%s' "${base_lookup_output}" | awk 'NF { print; exit }')"
  if [ "${base_lookup_exit}" -ne 0 ] || [ -z "${base_commit}" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg base_rev "${base_rev}" \
      --arg output "${base_lookup_output}" \
      '{
        ok: false,
        issue_id: $issue_id,
        base_rev: $base_rev,
        error: { message: "base_rev did not resolve to a commit" },
        output: $output
      }'
    return 0
  fi

  mkdir -p "$(workspace_root_dir "${repo_root}")"
  if add_output="$(run_in_repo_capture "${repo_root}" jj --repository "${repo_root}" workspace add "${workspace_path}" --name "${workspace_name}" -r "${base_rev}")"; then
    add_exit=0
  else
    add_exit=$?
  fi
  if [ "${add_exit}" -ne 0 ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg workspace_name "${workspace_name}" \
      --arg workspace_path "${workspace_path}" \
      --arg base_rev "${base_rev}" \
      --arg output "${add_output}" \
      '{
        ok: false,
        issue_id: $issue_id,
        error: { message: "jj workspace add failed" },
        workspace_name: $workspace_name,
        workspace_path: $workspace_path,
        base_rev: $base_rev,
        output: $output
      }'
    return 0
  fi

  if describe_output="$(run_in_repo_capture "${repo_root}" jj --repository "${workspace_path}" describe -m "${issue_id}: wip")"; then
    describe_exit=0
  else
    describe_exit=$?
  fi
  if [ "${describe_exit}" -ne 0 ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg workspace_name "${workspace_name}" \
      --arg workspace_path "${workspace_path}" \
      --arg output "${describe_output}" \
      '{
        ok: false,
        issue_id: $issue_id,
        error: { message: "jj describe failed after workspace creation" },
        workspace_name: $workspace_name,
        workspace_path: $workspace_path,
        output: $output
      }'
    return 0
  fi

  lane_record="$(
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg issue_title "${issue_title}" \
      --arg workspace_name "${workspace_name}" \
      --arg workspace_path "${workspace_path}" \
      --arg base_rev "${base_rev}" \
      --arg base_commit "${base_commit}" \
      --arg launched_at "$(now_iso8601)" \
      '{
        issue_id: $issue_id,
        issue_title: $issue_title,
        status: "launched",
        workspace_name: $workspace_name,
        workspace_path: $workspace_path,
        base_rev: $base_rev,
        base_commit: $base_commit,
        launched_at: $launched_at
      }'
  )"
  upsert_lane_state "${repo_root}" "${lane_record}"

  tracker_status_projection "${repo_root}" "${socket_path}" >/dev/null
  board_json="$(board_status_projection "${repo_root}")"
  board_summary="$(jq -c '.summary // null' <<<"${board_json}")"
  lanes_json="$(jq -c '.lanes // []' <<<"${board_json}")"
  receipt_payload="$(
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg issue_title "${issue_title}" \
      --arg workspace_name "${workspace_name}" \
      --arg workspace_path "${workspace_path}" \
      --arg base_rev "${base_rev}" \
      --arg base_commit "${base_commit}" \
      --argjson issue "${issue_json}" \
      --argjson board_summary "${board_summary}" \
      '{
        issue_id: $issue_id,
        issue_title: $issue_title,
        workspace_name: $workspace_name,
        workspace_path: $workspace_path,
        base_rev: $base_rev,
        base_commit: $base_commit,
        issue: $issue,
        board_summary: $board_summary
      }'
  )"
  append_receipt "${repo_root}" "lane.launch" "${receipt_payload}"

  payload_json="$(
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg issue_id "${issue_id}" \
      --arg issue_title "${issue_title}" \
      --arg workspace_name "${workspace_name}" \
      --arg workspace_path "${workspace_path}" \
      --arg base_rev "${base_rev}" \
      --arg base_commit "${base_commit}" \
      --argjson issue "${issue_json}" \
      --argjson lanes "${lanes_json}" \
      --argjson board_summary "${board_summary}" \
      '{
        repo_root: $repo_root,
        issue_id: $issue_id,
        issue_title: $issue_title,
        issue: $issue,
        workspace_name: $workspace_name,
        workspace_path: $workspace_path,
        base_rev: $base_rev,
        base_commit: $base_commit,
        lanes: $lanes,
        board_summary: $board_summary
      }'
  )"

  jq -cn --argjson payload "${payload_json}" '{ok:true, payload:$payload}'
}

handoff_lane_transition() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local revision="$4"
  local note="${5:-}"
  local lane_json
  local revision_lookup_output=""
  local revision_lookup_exit=0
  local resolved_revision=""
  local updated_lane_json
  local board_json
  local board_summary
  local lanes_json
  local receipt_payload
  local payload_json

  if [ -z "${issue_id}" ]; then
    jq -cn \
      --arg message "handoff_lane requires issue_id" \
      '{ok:false, error:{message:$message}}'
    return 0
  fi

  if [ -z "${revision}" ]; then
    jq -cn \
      --arg message "handoff_lane requires revision" \
      '{ok:false, error:{message:$message}}'
    return 0
  fi

  ensure_state_files "${repo_root}"
  lane_json="$(current_lane_for_issue "${repo_root}" "${issue_id}")"
  if [ "${lane_json}" = "null" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      '{
        ok: false,
        issue_id: $issue_id,
        error: { message: "handoff_lane requires an existing lane record" }
      }'
    return 0
  fi

  if revision_lookup_output="$(run_in_repo_capture "${repo_root}" jj --repository "${repo_root}" log -r "${revision}" --no-graph -T 'commit_id ++ "\n"')"; then
    revision_lookup_exit=0
  else
    revision_lookup_exit=$?
  fi
  resolved_revision="$(printf '%s' "${revision_lookup_output}" | awk 'NF { print; exit }')"
  if [ "${revision_lookup_exit}" -ne 0 ] || [ -z "${resolved_revision}" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg revision "${revision}" \
      --arg output "${revision_lookup_output}" \
      '{
        ok: false,
        issue_id: $issue_id,
        revision: $revision,
        error: { message: "revision did not resolve to a commit" },
        output: $output
      }'
    return 0
  fi

  updated_lane_json="$(
    jq -c \
      --arg status "handoff" \
      --arg handoff_revision "${resolved_revision}" \
      --arg handed_off_at "$(now_iso8601)" \
      --arg handoff_note "${note}" \
      '(. + {
        status: $status,
        handoff_revision: $handoff_revision,
        handed_off_at: $handed_off_at
      }) | if ($handoff_note | length) > 0 then . + {handoff_note:$handoff_note} else del(.handoff_note) end' \
      <<<"${lane_json}"
  )"
  upsert_lane_state "${repo_root}" "${updated_lane_json}"

  tracker_status_projection "${repo_root}" "${socket_path}" >/dev/null
  board_json="$(board_status_projection "${repo_root}")"
  board_summary="$(jq -c '.summary // null' <<<"${board_json}")"
  lanes_json="$(jq -c '.lanes // []' <<<"${board_json}")"
  receipt_payload="$(
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg revision "${resolved_revision}" \
      --arg note "${note}" \
      --argjson lane "${updated_lane_json}" \
      --argjson board_summary "${board_summary}" \
      '{
        issue_id: $issue_id,
        revision: $revision,
        note: $note,
        lane: $lane,
        board_summary: $board_summary
      }'
  )"
  append_receipt "${repo_root}" "lane.handoff" "${receipt_payload}"

  payload_json="$(
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg issue_id "${issue_id}" \
      --arg revision "${resolved_revision}" \
      --arg note "${note}" \
      --argjson lane "${updated_lane_json}" \
      --argjson lanes "${lanes_json}" \
      --argjson board_summary "${board_summary}" \
      '{
        repo_root: $repo_root,
        issue_id: $issue_id,
        revision: $revision,
        note: $note,
        lane: $lane,
        lanes: $lanes,
        board_summary: $board_summary
      }'
  )"

  jq -cn --argjson payload "${payload_json}" '{ok:true, payload:$payload}'
}

finish_lane_transition() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local outcome="$4"
  local note="${5:-}"
  local lane_json
  local updated_lane_json
  local board_json
  local board_summary
  local lanes_json
  local receipt_payload
  local payload_json

  if [ -z "${issue_id}" ]; then
    jq -cn \
      --arg message "finish_lane requires issue_id" \
      '{ok:false, error:{message:$message}}'
    return 0
  fi

  if [ -z "${outcome}" ]; then
    jq -cn \
      --arg message "finish_lane requires outcome" \
      '{ok:false, error:{message:$message}}'
    return 0
  fi

  ensure_state_files "${repo_root}"
  lane_json="$(current_lane_for_issue "${repo_root}" "${issue_id}")"
  if [ "${lane_json}" = "null" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      '{
        ok: false,
        issue_id: $issue_id,
        error: { message: "finish_lane requires an existing lane record" }
      }'
    return 0
  fi

  updated_lane_json="$(
    jq -c \
      --arg status "finished" \
      --arg outcome "${outcome}" \
      --arg finished_at "$(now_iso8601)" \
      --arg finish_note "${note}" \
      '(. + {
        status: $status,
        outcome: $outcome,
        finished_at: $finished_at
      }) | if ($finish_note | length) > 0 then . + {finish_note:$finish_note} else del(.finish_note) end' \
      <<<"${lane_json}"
  )"
  upsert_lane_state "${repo_root}" "${updated_lane_json}"

  tracker_status_projection "${repo_root}" "${socket_path}" >/dev/null
  board_json="$(board_status_projection "${repo_root}")"
  board_summary="$(jq -c '.summary // null' <<<"${board_json}")"
  lanes_json="$(jq -c '.lanes // []' <<<"${board_json}")"
  receipt_payload="$(
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg outcome "${outcome}" \
      --arg note "${note}" \
      --argjson lane "${updated_lane_json}" \
      --argjson board_summary "${board_summary}" \
      '{
        issue_id: $issue_id,
        outcome: $outcome,
        note: $note,
        lane: $lane,
        board_summary: $board_summary
      }'
  )"
  append_receipt "${repo_root}" "lane.finish" "${receipt_payload}"

  payload_json="$(
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg issue_id "${issue_id}" \
      --arg outcome "${outcome}" \
      --arg note "${note}" \
      --argjson lane "${updated_lane_json}" \
      --argjson lanes "${lanes_json}" \
      --argjson board_summary "${board_summary}" \
      '{
        repo_root: $repo_root,
        issue_id: $issue_id,
        outcome: $outcome,
        note: $note,
        lane: $lane,
        lanes: $lanes,
        board_summary: $board_summary
      }'
  )"

  jq -cn --argjson payload "${payload_json}" '{ok:true, payload:$payload}'
}

archive_lane_transition() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local note="${4:-}"
  local lane_json
  local workspace_path=""
  local stored_status=""
  local board_json
  local board_summary
  local lanes_json
  local receipt_payload
  local payload_json

  if [ -z "${issue_id}" ]; then
    jq -cn \
      --arg message "archive_lane requires issue_id" \
      '{ok:false, error:{message:$message}}'
    return 0
  fi

  ensure_state_files "${repo_root}"
  lane_json="$(current_lane_for_issue "${repo_root}" "${issue_id}")"
  if [ "${lane_json}" = "null" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      '{
        ok: false,
        issue_id: $issue_id,
        error: { message: "archive_lane requires an existing lane record" }
      }'
    return 0
  fi

  stored_status="$(jq -r '.status // ""' <<<"${lane_json}")"
  if [ "${stored_status}" != "finished" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg status "${stored_status}" \
      '{
        ok: false,
        issue_id: $issue_id,
        status: $status,
        error: { message: "archive_lane requires a finished lane" }
      }'
    return 0
  fi

  workspace_path="$(jq -r '.workspace_path // ""' <<<"${lane_json}")"
  if [ -n "${workspace_path}" ] && [ -d "${workspace_path}" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg workspace_path "${workspace_path}" \
      '{
        ok: false,
        issue_id: $issue_id,
        workspace_path: $workspace_path,
        error: { message: "archive_lane requires the lane workspace to be removed first" }
      }'
    return 0
  fi

  remove_lane_state "${repo_root}" "${issue_id}"

  tracker_status_projection "${repo_root}" "${socket_path}" >/dev/null
  board_json="$(board_status_projection "${repo_root}")"
  board_summary="$(jq -c '.summary // null' <<<"${board_json}")"
  lanes_json="$(jq -c '.lanes // []' <<<"${board_json}")"
  receipt_payload="$(
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg note "${note}" \
      --argjson lane "${lane_json}" \
      --argjson board_summary "${board_summary}" \
      '{
        issue_id: $issue_id,
        note: $note,
        lane: $lane,
        board_summary: $board_summary
      }'
  )"
  append_receipt "${repo_root}" "lane.archive" "${receipt_payload}"

  payload_json="$(
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg issue_id "${issue_id}" \
      --arg note "${note}" \
      --argjson archived_lane "${lane_json}" \
      --argjson lanes "${lanes_json}" \
      --argjson board_summary "${board_summary}" \
      '{
        repo_root: $repo_root,
        issue_id: $issue_id,
        note: $note,
        archived_lane: $archived_lane,
        lanes: $lanes,
        board_summary: $board_summary
      }'
  )"

  jq -cn --argjson payload "${payload_json}" '{ok:true, payload:$payload}'
}

refresh_transition_board() {
  local repo_root="$1"
  local socket_path="$2"

  tracker_status_projection "${repo_root}" "${socket_path}" >/dev/null
  board_status_projection "${repo_root}"
}

restore_lane_state_snapshot() {
  local repo_root="$1"
  local lane_json="$2"

  if [ -z "${lane_json}" ] || [ "${lane_json}" = "null" ]; then
    return 0
  fi

  upsert_lane_state "${repo_root}" "${lane_json}"
}

rollback_launch_artifacts() {
  local repo_root="$1"
  local issue_id="$2"
  local workspace_name="$3"
  local workspace_path="$4"
  local remove_lane_exit=0
  local forget_output=""
  local forget_exit=0
  local remove_output=""
  local remove_exit=0

  if [ -n "${issue_id}" ]; then
    remove_lane_state "${repo_root}" "${issue_id}" >/dev/null 2>&1 || remove_lane_exit=$?
  fi

  if [ -n "${workspace_name}" ]; then
    if forget_output="$(run_in_repo_capture "${repo_root}" jj --repository "${repo_root}" workspace forget "${workspace_name}")"; then
      forget_exit=0
    else
      forget_exit=$?
    fi
  fi

  if [ -n "${workspace_path}" ] && [ -e "${workspace_path}" ]; then
    if remove_output="$(run_in_repo_capture "${repo_root}" rm -rf -- "${workspace_path}")"; then
      remove_exit=0
    else
      remove_exit=$?
    fi
  fi

  jq -cn \
    --arg issue_id "${issue_id}" \
    --arg workspace_name "${workspace_name}" \
    --arg workspace_path "${workspace_path}" \
    --argjson remove_lane_exit "${remove_lane_exit}" \
    --argjson forget_exit "${forget_exit}" \
    --arg forget_output "${forget_output}" \
    --argjson remove_exit "${remove_exit}" \
    --arg remove_output "${remove_output}" \
    '{
      issue_id: $issue_id,
      workspace_name: $workspace_name,
      workspace_path: $workspace_path,
      remove_lane_exit: $remove_lane_exit,
      forget_workspace: {
        exit_code: $forget_exit,
        output: (if ($forget_output | length) > 0 then $forget_output else null end)
      },
      remove_workspace: {
        exit_code: $remove_exit,
        output: (if ($remove_output | length) > 0 then $remove_output else null end)
      }
    }'
}

workspace_registration_present() {
  local repo_root="$1"
  local workspace_name="$2"
  local list_output=""

  [ -n "${workspace_name}" ] || return 1
  if ! list_output="$(run_in_repo_capture "${repo_root}" jj --repository "${repo_root}" workspace list --ignore-working-copy --color never)"; then
    return 1
  fi

  printf '%s\n' "${list_output}" | grep -F "${workspace_name}" >/dev/null 2>&1
}

workspace_quarantine_path() {
  local repo_root="$1"
  local workspace_name="$2"
  local suffix

  suffix="$(date -u +"%Y%m%dT%H%M%SZ")"
  printf '%s/.quarantine-%s-%s\n' "$(workspace_root_dir "${repo_root}")" "${workspace_name:-workspace}" "${suffix}"
}

compact_lane_workspace() {
  local repo_root="$1"
  local issue_id="$2"
  local workspace_name="$3"
  local workspace_path="$4"
  local quarantine_requested="${5:-false}"
  local workspace_root=""
  local requested_mode="remove"
  local effective_mode="none"
  local quarantine_path=""
  local registration_present=false
  local path_present=false
  local forget_output=""
  local forget_exit=0
  local cleanup_output=""
  local cleanup_exit=0

  workspace_root="$(workspace_root_dir "${repo_root}")"
  if [ "${quarantine_requested}" = true ]; then
    requested_mode="quarantine"
  fi

  if [ -n "${workspace_path}" ]; then
    case "${workspace_path}" in
      "${workspace_root}/"*)
        ;;
      *)
        jq -cn \
          --arg issue_id "${issue_id}" \
          --arg workspace_name "${workspace_name}" \
          --arg workspace_path "${workspace_path}" \
          --arg workspace_root "${workspace_root}" \
          '{
            ok: false,
            issue_id: $issue_id,
            error: {
              message: "compact_lane refuses to mutate a workspace outside the repo workspace root"
            },
            workspace_name: $workspace_name,
            workspace_path: $workspace_path,
            workspace_root: $workspace_root
          }'
        return 0
        ;;
    esac
  fi

  if workspace_registration_present "${repo_root}" "${workspace_name}"; then
    registration_present=true
  fi
  if [ -n "${workspace_path}" ] && [ -e "${workspace_path}" ]; then
    path_present=true
  fi

  if [ "${registration_present}" = true ]; then
    if forget_output="$(run_in_repo_capture "${repo_root}" jj --repository "${repo_root}" workspace forget "${workspace_name}")"; then
      forget_exit=0
    else
      forget_exit=$?
    fi
  fi

  if [ "${forget_exit}" -ne 0 ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg workspace_name "${workspace_name}" \
      --arg workspace_path "${workspace_path}" \
      --argjson registration_present "$(json_bool "${registration_present}")" \
      --argjson forget_exit "${forget_exit}" \
      --arg forget_output "${forget_output}" \
      '{
        ok: false,
        issue_id: $issue_id,
        error: {
          message: "compact_lane failed to forget the jj workspace"
        },
        workspace_name: $workspace_name,
        workspace_path: $workspace_path,
        registration_present: $registration_present,
        forget_workspace: {
          exit_code: $forget_exit,
          output: (if ($forget_output | length) > 0 then $forget_output else null end)
        }
      }'
    return 0
  fi

  if [ "${path_present}" = true ]; then
    if [ "${requested_mode}" = "quarantine" ]; then
      quarantine_path="$(workspace_quarantine_path "${repo_root}" "${workspace_name}")"
      mkdir -p "${workspace_root}"
      if cleanup_output="$(run_in_repo_capture "${repo_root}" mv -- "${workspace_path}" "${quarantine_path}")"; then
        cleanup_exit=0
        effective_mode="quarantine"
      else
        cleanup_exit=$?
      fi
    else
      if cleanup_output="$(run_in_repo_capture "${repo_root}" rm -rf -- "${workspace_path}")"; then
        cleanup_exit=0
        effective_mode="remove"
      else
        cleanup_exit=$?
        quarantine_path="$(workspace_quarantine_path "${repo_root}" "${workspace_name}")"
        mkdir -p "${workspace_root}"
        if cleanup_output="$(run_in_repo_capture "${repo_root}" mv -- "${workspace_path}" "${quarantine_path}")"; then
          cleanup_exit=0
          effective_mode="quarantine"
        fi
      fi
    fi
  fi

  if [ "${cleanup_exit}" -ne 0 ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg workspace_name "${workspace_name}" \
      --arg workspace_path "${workspace_path}" \
      --arg requested_mode "${requested_mode}" \
      --arg quarantine_path "${quarantine_path}" \
      --argjson path_present "$(json_bool "${path_present}")" \
      --argjson cleanup_exit "${cleanup_exit}" \
      --arg cleanup_output "${cleanup_output}" \
      '{
        ok: false,
        issue_id: $issue_id,
        error: {
          message: "compact_lane failed to clean the lane workspace"
        },
        workspace_name: $workspace_name,
        workspace_path: $workspace_path,
        path_present: $path_present,
        cleanup: {
          requested_mode: $requested_mode,
          quarantine_path: (if ($quarantine_path | length) > 0 then $quarantine_path else null end),
          exit_code: $cleanup_exit,
          output: (if ($cleanup_output | length) > 0 then $cleanup_output else null end)
        }
      }'
    return 0
  fi

  jq -cn \
    --arg issue_id "${issue_id}" \
    --arg workspace_name "${workspace_name}" \
    --arg workspace_path "${workspace_path}" \
    --arg requested_mode "${requested_mode}" \
    --arg effective_mode "${effective_mode}" \
    --arg quarantine_path "${quarantine_path}" \
    --argjson registration_present "$(json_bool "${registration_present}")" \
    --argjson path_present "$(json_bool "${path_present}")" \
    --argjson workspace_exists_after "$(json_bool "$([ -n "${workspace_path}" ] && [ -e "${workspace_path}" ] && echo true || echo false)")" \
    --argjson quarantine_exists "$(json_bool "$([ -n "${quarantine_path}" ] && [ -e "${quarantine_path}" ] && echo true || echo false)")" \
    '{
      ok: true,
      issue_id: $issue_id,
      workspace_name: $workspace_name,
      workspace_path: $workspace_path,
      registration_present: $registration_present,
      path_present: $path_present,
      requested_mode: $requested_mode,
      effective_mode: $effective_mode,
      workspace_exists_after: $workspace_exists_after,
      quarantine_path: (if ($quarantine_path | length) > 0 then $quarantine_path else null end),
      quarantine_exists: $quarantine_exists
    }'
}

build_claim_issue_carrier() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local carrier
  local issue_show_result="null"
  local ready_result="null"
  local issue_json="null"
  local issue_exists=false
  local issue_status=""
  local ready_claimable=false
  local admission_reason=""

  carrier="$(new_transition_carrier "${repo_root}" "claim_issue" "$(jq -cn --arg issue_id "${issue_id}" '{issue_id:$issue_id}')")"
  carrier="$(carrier_set_service "${carrier}" "$(transition_service_snapshot "${repo_root}" "${socket_path}")")"
  carrier="$(carrier_set_receipt_refs "${carrier}" "$(issue_receipt_refs "${repo_root}" "${issue_id}")")"

  if [ -n "${issue_id}" ]; then
    issue_show_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_issue_show" issue show "${issue_id}")"
    ready_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_ready" ready)"
  fi

  carrier="$(carrier_set_tracker "${carrier}" "$(jq -cn --argjson issue_show "${issue_show_result}" --argjson ready "${ready_result}" '{issue_show:$issue_show, ready:$ready}')")"

  issue_json="$(issue_snapshot_from_result "${issue_show_result}")"
  if [ "${issue_json}" != "null" ]; then
    issue_exists=true
    issue_status="$(jq -r '.status // ""' <<<"${issue_json}")"
    carrier="$(carrier_set_issue "${carrier}" "${issue_json}")"
  fi

  if [ -n "${issue_id}" ] && jq -e --arg issue_id "${issue_id}" '.ok and ((.output | type) == "array") and any(.output[]?; (.id // "") == $issue_id)' >/dev/null <<<"${ready_result}"; then
    ready_claimable=true
  fi

  carrier="$(carrier_add_witness "${carrier}" "issue_id" "$(json_bool "$([ -n "${issue_id}" ] && echo true || echo false)")" "issue_id is required" "$(jq -cn --arg issue_id "${issue_id}" '{issue_id:$issue_id}')")"
  carrier="$(carrier_add_witness "${carrier}" "issue_exists" "$(json_bool "${issue_exists}")" "issue must exist" "$(jq -cn --argjson issue "${issue_json}" '{issue:$issue}')")"
  carrier="$(carrier_add_witness "${carrier}" "issue_status_open" "$(json_bool "$([ "${issue_status}" = "open" ] && echo true || echo false)")" "issue must be open before claim" "$(jq -cn --arg status "${issue_status}" '{status:$status}')")"
  carrier="$(carrier_add_witness "${carrier}" "issue_ready" "$(json_bool "${ready_claimable}")" "issue must be ready to claim" "$(jq -cn --argjson ready "${ready_result}" '{ready:$ready}')")"

  if [ -z "${issue_id}" ]; then
    admission_reason="claim_issue requires issue_id"
  elif [ "${issue_exists}" != true ]; then
    admission_reason="claim_issue requires an existing issue"
  elif [ "${issue_status}" != "open" ]; then
    admission_reason="claim_issue requires an open issue"
  elif [ "${ready_claimable}" != true ]; then
    admission_reason="claim_issue requires a ready issue"
  fi

  carrier="$(carrier_set_admission "${carrier}" "$(json_bool "$([ -z "${admission_reason}" ] && echo true || echo false)")" "${admission_reason}" '["structural","runtime"]')"
  printf '%s\n' "${carrier}"
}

build_close_issue_carrier() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local reason="$4"
  local carrier
  local issue_show_result="null"
  local issue_json="null"
  local issue_exists=false
  local issue_status=""
  local lane_json="null"
  local no_live_lane=true
  local admission_reason=""

  carrier="$(new_transition_carrier "${repo_root}" "close_issue" "$(jq -cn --arg issue_id "${issue_id}" --arg reason "${reason}" '{issue_id:$issue_id, reason:$reason}')")"
  carrier="$(carrier_set_service "${carrier}" "$(transition_service_snapshot "${repo_root}" "${socket_path}")")"
  carrier="$(carrier_set_receipt_refs "${carrier}" "$(issue_receipt_refs "${repo_root}" "${issue_id}")")"

  if [ -n "${issue_id}" ]; then
    issue_show_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_issue_show" issue show "${issue_id}")"
    lane_json="$(current_lane_for_issue "${repo_root}" "${issue_id}")"
  fi

  carrier="$(carrier_set_tracker "${carrier}" "$(jq -cn --argjson issue_show "${issue_show_result}" '{issue_show:$issue_show}')")"

  issue_json="$(issue_snapshot_from_result "${issue_show_result}")"
  if [ "${issue_json}" != "null" ]; then
    issue_exists=true
    issue_status="$(jq -r '.status // ""' <<<"${issue_json}")"
    carrier="$(carrier_set_issue "${carrier}" "${issue_json}")"
  fi

  if [ "${lane_json}" != "null" ]; then
    no_live_lane=false
    carrier="$(carrier_set_lane "${carrier}" "${lane_json}")"
  fi

  carrier="$(carrier_add_witness "${carrier}" "issue_id" "$(json_bool "$([ -n "${issue_id}" ] && echo true || echo false)")" "issue_id is required" "$(jq -cn --arg issue_id "${issue_id}" '{issue_id:$issue_id}')")"
  carrier="$(carrier_add_witness "${carrier}" "close_reason" "$(json_bool "$([ -n "${reason}" ] && echo true || echo false)")" "close reason is required" "$(jq -cn --arg reason "${reason}" '{reason:$reason}')")"
  carrier="$(carrier_add_witness "${carrier}" "issue_exists" "$(json_bool "${issue_exists}")" "issue must exist" "$(jq -cn --argjson issue "${issue_json}" '{issue:$issue}')")"
  carrier="$(carrier_add_witness "${carrier}" "issue_not_closed" "$(json_bool "$([ "${issue_status}" != "closed" ] && echo true || echo false)")" "issue must not already be closed" "$(jq -cn --arg status "${issue_status}" '{status:$status}')")"
  carrier="$(carrier_add_witness "${carrier}" "no_live_lane" "$(json_bool "${no_live_lane}")" "close_issue requires the live lane to be archived first" "$(jq -cn --argjson lane "${lane_json}" '{lane:$lane}')")"

  if [ -z "${issue_id}" ]; then
    admission_reason="close_issue requires issue_id"
  elif [ -z "${reason}" ]; then
    admission_reason="close_issue requires reason"
  elif [ "${issue_exists}" != true ]; then
    admission_reason="close_issue requires an existing issue"
  elif [ "${issue_status}" = "closed" ]; then
    admission_reason="close_issue requires an open or in-progress issue"
  elif [ "${no_live_lane}" != true ]; then
    admission_reason="close_issue requires the live lane to be archived first"
  fi

  carrier="$(carrier_set_admission "${carrier}" "$(json_bool "$([ -z "${admission_reason}" ] && echo true || echo false)")" "${admission_reason}" '["structural","authority"]')"
  printf '%s\n' "${carrier}"
}

build_launch_lane_carrier() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local base_rev="$4"
  local slug_arg="${5:-}"
  local carrier
  local issue_show_result="null"
  local issue_json="null"
  local issue_exists=false
  local issue_status=""
  local issue_title=""
  local lane_json="null"
  local no_live_lane=true
  local slug=""
  local workspace_name=""
  local workspace_path=""
  local workspace_absent=true
  local base_lookup_json="null"
  local base_commit=""
  local admission_reason=""

  carrier="$(new_transition_carrier "${repo_root}" "launch_lane" "$(jq -cn --arg issue_id "${issue_id}" --arg base_rev "${base_rev}" --arg slug "${slug_arg}" '{issue_id:$issue_id, base_rev:$base_rev, slug:$slug}')")"
  carrier="$(carrier_set_service "${carrier}" "$(transition_service_snapshot "${repo_root}" "${socket_path}")")"
  carrier="$(carrier_set_receipt_refs "${carrier}" "$(issue_receipt_refs "${repo_root}" "${issue_id}")")"

  if [ -n "${issue_id}" ]; then
    issue_show_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_issue_show" issue show "${issue_id}")"
    lane_json="$(current_lane_for_issue "${repo_root}" "${issue_id}")"
  fi

  issue_json="$(issue_snapshot_from_result "${issue_show_result}")"
  if [ "${issue_json}" != "null" ]; then
    issue_exists=true
    issue_status="$(jq -r '.status // ""' <<<"${issue_json}")"
    issue_title="$(jq -r '.title // ""' <<<"${issue_json}")"
    carrier="$(carrier_set_issue "${carrier}" "${issue_json}")"
  fi

  if [ "${lane_json}" != "null" ]; then
    no_live_lane=false
    carrier="$(carrier_set_lane "${carrier}" "${lane_json}")"
  fi

  slug="${slug_arg}"
  if [ -z "${slug}" ]; then
    slug="$(slugify_fragment "${issue_title}")"
  fi
  if [ -z "${slug}" ]; then
    slug="lane"
  fi

  workspace_name="${issue_id}-${slug}"
  workspace_path="$(workspace_root_dir "${repo_root}")/${workspace_name}"
  if [ -e "${workspace_path}" ]; then
    workspace_absent=false
  fi

  if [ -n "${base_rev}" ]; then
    base_lookup_json="$(resolve_revision_commit "${repo_root}" "${base_rev}")"
    base_commit="$(jq -r '.commit // ""' <<<"${base_lookup_json}")"
  fi

  carrier="$(carrier_set_tracker "${carrier}" "$(jq -cn --argjson issue_show "${issue_show_result}" '{issue_show:$issue_show}')")"
  carrier="$(carrier_set_workspace "${carrier}" "$(transition_workspace_snapshot "${workspace_name}" "${workspace_path}" "${base_rev}" "${base_commit}")")"

  carrier="$(carrier_add_witness "${carrier}" "issue_id" "$(json_bool "$([ -n "${issue_id}" ] && echo true || echo false)")" "issue_id is required" "$(jq -cn --arg issue_id "${issue_id}" '{issue_id:$issue_id}')")"
  carrier="$(carrier_add_witness "${carrier}" "base_rev" "$(json_bool "$([ -n "${base_rev}" ] && echo true || echo false)")" "base_rev is required" "$(jq -cn --arg base_rev "${base_rev}" '{base_rev:$base_rev}')")"
  carrier="$(carrier_add_witness "${carrier}" "issue_exists" "$(json_bool "${issue_exists}")" "issue must exist" "$(jq -cn --argjson issue "${issue_json}" '{issue:$issue}')")"
  carrier="$(carrier_add_witness "${carrier}" "issue_in_progress" "$(json_bool "$([ "${issue_status}" = "in_progress" ] && echo true || echo false)")" "launch_lane requires a claimed in_progress issue" "$(jq -cn --arg status "${issue_status}" '{status:$status}')")"
  carrier="$(carrier_add_witness "${carrier}" "no_live_lane" "$(json_bool "${no_live_lane}")" "launch_lane requires no existing live lane" "$(jq -cn --argjson lane "${lane_json}" '{lane:$lane}')")"
  carrier="$(carrier_add_witness "${carrier}" "base_rev_resolves" "$(jq -r '.ok // false' <<<"${base_lookup_json}")" "base_rev must resolve to a commit" "$(jq -cn --argjson base_lookup "${base_lookup_json}" '{base_lookup:$base_lookup}')")"
  carrier="$(carrier_add_witness "${carrier}" "workspace_absent" "$(json_bool "${workspace_absent}")" "workspace path must be absent before launch" "$(jq -cn --arg workspace_name "${workspace_name}" --arg workspace_path "${workspace_path}" '{workspace_name:$workspace_name, workspace_path:$workspace_path}')")"

  if [ -z "${issue_id}" ]; then
    admission_reason="launch_lane requires issue_id"
  elif [ -z "${base_rev}" ]; then
    admission_reason="launch_lane requires base_rev"
  elif [ "${issue_exists}" != true ]; then
    admission_reason="launch_lane requires an existing issue"
  elif [ "${issue_status}" != "in_progress" ]; then
    admission_reason="launch_lane requires a claimed in_progress issue"
  elif [ "${no_live_lane}" != true ]; then
    admission_reason="launch_lane requires no existing live lane"
  elif ! jq -e '.ok == true' >/dev/null <<<"${base_lookup_json}"; then
    admission_reason="base_rev did not resolve to a commit"
  elif [ "${workspace_absent}" != true ]; then
    admission_reason="workspace path already exists"
  fi

  carrier="$(carrier_set_admission "${carrier}" "$(json_bool "$([ -z "${admission_reason}" ] && echo true || echo false)")" "${admission_reason}" '["structural","runtime"]')"
  printf '%s\n' "${carrier}"
}

build_handoff_lane_carrier() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local revision="$4"
  local note="${5:-}"
  local carrier
  local lane_json="null"
  local lane_exists=false
  local stored_status=""
  local revision_lookup_json="null"
  local admission_reason=""

  carrier="$(new_transition_carrier "${repo_root}" "handoff_lane" "$(jq -cn --arg issue_id "${issue_id}" --arg revision "${revision}" --arg note "${note}" '{issue_id:$issue_id, revision:$revision, note:$note}')")"
  carrier="$(carrier_set_service "${carrier}" "$(transition_service_snapshot "${repo_root}" "${socket_path}")")"
  carrier="$(carrier_set_receipt_refs "${carrier}" "$(issue_receipt_refs "${repo_root}" "${issue_id}")")"

  if [ -n "${issue_id}" ]; then
    lane_json="$(current_lane_for_issue "${repo_root}" "${issue_id}")"
  fi
  if [ "${lane_json}" != "null" ]; then
    lane_exists=true
    stored_status="$(jq -r '.status // ""' <<<"${lane_json}")"
    carrier="$(carrier_set_lane "${carrier}" "${lane_json}")"
  fi

  if [ -n "${revision}" ]; then
    revision_lookup_json="$(resolve_revision_commit "${repo_root}" "${revision}")"
  fi

  carrier="$(carrier_set_workspace "${carrier}" "$(transition_workspace_snapshot "" "$(jq -r '.workspace_path // ""' <<<"${lane_json}")" "" "" "$(jq -r '.commit // ""' <<<"${revision_lookup_json}")")")"
  carrier="$(carrier_add_witness "${carrier}" "issue_id" "$(json_bool "$([ -n "${issue_id}" ] && echo true || echo false)")" "issue_id is required" "$(jq -cn --arg issue_id "${issue_id}" '{issue_id:$issue_id}')")"
  carrier="$(carrier_add_witness "${carrier}" "revision" "$(json_bool "$([ -n "${revision}" ] && echo true || echo false)")" "revision is required" "$(jq -cn --arg revision "${revision}" '{revision:$revision}')")"
  carrier="$(carrier_add_witness "${carrier}" "lane_exists" "$(json_bool "${lane_exists}")" "handoff_lane requires an existing lane record" "$(jq -cn --argjson lane "${lane_json}" '{lane:$lane}')")"
  carrier="$(carrier_add_witness "${carrier}" "lane_handoffable" "$(json_bool "$([ "${stored_status}" != "finished" ] && echo true || echo false)")" "handoff_lane requires a non-finished lane" "$(jq -cn --arg status "${stored_status}" '{status:$status}')")"
  carrier="$(carrier_add_witness "${carrier}" "revision_resolves" "$(jq -r '.ok // false' <<<"${revision_lookup_json}")" "revision must resolve to a commit" "$(jq -cn --argjson revision_lookup "${revision_lookup_json}" '{revision_lookup:$revision_lookup}')")"

  if [ -z "${issue_id}" ]; then
    admission_reason="handoff_lane requires issue_id"
  elif [ -z "${revision}" ]; then
    admission_reason="handoff_lane requires revision"
  elif [ "${lane_exists}" != true ]; then
    admission_reason="handoff_lane requires an existing lane record"
  elif [ "${stored_status}" = "finished" ]; then
    admission_reason="handoff_lane requires a non-finished lane"
  elif ! jq -e '.ok == true' >/dev/null <<<"${revision_lookup_json}"; then
    admission_reason="revision did not resolve to a commit"
  fi

  carrier="$(carrier_set_admission "${carrier}" "$(json_bool "$([ -z "${admission_reason}" ] && echo true || echo false)")" "${admission_reason}" '["structural","runtime"]')"
  printf '%s\n' "${carrier}"
}

build_finish_lane_carrier() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local outcome="$4"
  local note="${5:-}"
  local carrier
  local lane_json="null"
  local lane_exists=false
  local stored_status=""
  local finishable=false
  local admission_reason=""

  carrier="$(new_transition_carrier "${repo_root}" "finish_lane" "$(jq -cn --arg issue_id "${issue_id}" --arg outcome "${outcome}" --arg note "${note}" '{issue_id:$issue_id, outcome:$outcome, note:$note}')")"
  carrier="$(carrier_set_service "${carrier}" "$(transition_service_snapshot "${repo_root}" "${socket_path}")")"
  carrier="$(carrier_set_receipt_refs "${carrier}" "$(issue_receipt_refs "${repo_root}" "${issue_id}")")"

  if [ -n "${issue_id}" ]; then
    lane_json="$(current_lane_for_issue "${repo_root}" "${issue_id}")"
  fi
  if [ "${lane_json}" != "null" ]; then
    lane_exists=true
    stored_status="$(jq -r '.status // ""' <<<"${lane_json}")"
    carrier="$(carrier_set_lane "${carrier}" "${lane_json}")"
  fi

  if [ "${stored_status}" = "launched" ] || [ "${stored_status}" = "handoff" ]; then
    finishable=true
  fi

  carrier="$(carrier_add_witness "${carrier}" "issue_id" "$(json_bool "$([ -n "${issue_id}" ] && echo true || echo false)")" "issue_id is required" "$(jq -cn --arg issue_id "${issue_id}" '{issue_id:$issue_id}')")"
  carrier="$(carrier_add_witness "${carrier}" "outcome" "$(json_bool "$([ -n "${outcome}" ] && echo true || echo false)")" "outcome is required" "$(jq -cn --arg outcome "${outcome}" '{outcome:$outcome}')")"
  carrier="$(carrier_add_witness "${carrier}" "lane_exists" "$(json_bool "${lane_exists}")" "finish_lane requires an existing lane record" "$(jq -cn --argjson lane "${lane_json}" '{lane:$lane}')")"
  carrier="$(carrier_add_witness "${carrier}" "lane_finishable" "$(json_bool "${finishable}")" "finish_lane requires a launched or handed-off lane" "$(jq -cn --arg status "${stored_status}" '{status:$status}')")"

  if [ -z "${issue_id}" ]; then
    admission_reason="finish_lane requires issue_id"
  elif [ -z "${outcome}" ]; then
    admission_reason="finish_lane requires outcome"
  elif [ "${lane_exists}" != true ]; then
    admission_reason="finish_lane requires an existing lane record"
  elif [ "${finishable}" != true ]; then
    admission_reason="finish_lane requires a launched or handed-off lane"
  fi

  carrier="$(carrier_set_admission "${carrier}" "$(json_bool "$([ -z "${admission_reason}" ] && echo true || echo false)")" "${admission_reason}" '["structural","runtime"]')"
  printf '%s\n' "${carrier}"
}

build_archive_lane_carrier() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local note="${4:-}"
  local carrier
  local lane_json="null"
  local lane_exists=false
  local stored_status=""
  local workspace_path=""
  local workspace_removed=true
  local admission_reason=""

  carrier="$(new_transition_carrier "${repo_root}" "archive_lane" "$(jq -cn --arg issue_id "${issue_id}" --arg note "${note}" '{issue_id:$issue_id, note:$note}')")"
  carrier="$(carrier_set_service "${carrier}" "$(transition_service_snapshot "${repo_root}" "${socket_path}")")"
  carrier="$(carrier_set_receipt_refs "${carrier}" "$(issue_receipt_refs "${repo_root}" "${issue_id}")")"

  if [ -n "${issue_id}" ]; then
    lane_json="$(current_lane_for_issue "${repo_root}" "${issue_id}")"
  fi
  if [ "${lane_json}" != "null" ]; then
    lane_exists=true
    stored_status="$(jq -r '.status // ""' <<<"${lane_json}")"
    workspace_path="$(jq -r '.workspace_path // ""' <<<"${lane_json}")"
    carrier="$(carrier_set_lane "${carrier}" "${lane_json}")"
  fi

  if [ -n "${workspace_path}" ] && [ -d "${workspace_path}" ]; then
    workspace_removed=false
  fi

  carrier="$(carrier_set_workspace "${carrier}" "$(transition_workspace_snapshot "" "${workspace_path}")")"
  carrier="$(carrier_add_witness "${carrier}" "issue_id" "$(json_bool "$([ -n "${issue_id}" ] && echo true || echo false)")" "issue_id is required" "$(jq -cn --arg issue_id "${issue_id}" '{issue_id:$issue_id}')")"
  carrier="$(carrier_add_witness "${carrier}" "lane_exists" "$(json_bool "${lane_exists}")" "archive_lane requires an existing lane record" "$(jq -cn --argjson lane "${lane_json}" '{lane:$lane}')")"
  carrier="$(carrier_add_witness "${carrier}" "lane_finished" "$(json_bool "$([ "${stored_status}" = "finished" ] && echo true || echo false)")" "archive_lane requires a finished lane" "$(jq -cn --arg status "${stored_status}" '{status:$status}')")"
  carrier="$(carrier_add_witness "${carrier}" "workspace_removed" "$(json_bool "${workspace_removed}")" "archive_lane requires the lane workspace to be removed first" "$(jq -cn --arg workspace_path "${workspace_path}" '{workspace_path:$workspace_path}')")"

  if [ -z "${issue_id}" ]; then
    admission_reason="archive_lane requires issue_id"
  elif [ "${lane_exists}" != true ]; then
    admission_reason="archive_lane requires an existing lane record"
  elif [ "${stored_status}" != "finished" ]; then
    admission_reason="archive_lane requires a finished lane"
  elif [ "${workspace_removed}" != true ]; then
    admission_reason="archive_lane requires the lane workspace to be removed first"
  fi

  carrier="$(carrier_set_admission "${carrier}" "$(json_bool "$([ -z "${admission_reason}" ] && echo true || echo false)")" "${admission_reason}" '["structural","runtime","replay"]')"
  printf '%s\n' "${carrier}"
}

realize_claim_issue_transition() {
  local repo_root="$1"
  local socket_path="$2"
  local carrier_json="$3"
  local issue_id
  local claim_result
  local issue_json
  local realization_json
  local board_json
  local board_summary
  local receipt_payload
  local receipt_json
  local payload_json

  issue_id="$(jq -r '.intent.payload.issue_id // ""' <<<"${carrier_json}")"
  claim_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_issue_claim" issue claim "${issue_id}")"
  if ! jq -e --arg issue_id "${issue_id}" '
      .ok and
      ((.output | type) == "array") and
      ((.output | length) > 0) and
      ((.output[0] | type) == "object") and
      ((.output[0].id // "") == $issue_id)
    ' >/dev/null <<<"${claim_result}"; then
    realization_json="$(jq -cn --argjson tracker "${claim_result}" '{kind:"tracker_issue_claim", tracker:$tracker}')"
    carrier_json="$(carrier_set_realization "${carrier_json}" "${realization_json}")"
    transition_failure_result "${carrier_json}" "tracker issue claim failed" "$(jq -cn --argjson tracker "${claim_result}" '{tracker:$tracker}')"
    return 0
  fi

  issue_json="$(jq -c '.output[0]' <<<"${claim_result}")"
  carrier_json="$(carrier_set_issue "${carrier_json}" "${issue_json}")"
  realization_json="$(jq -cn --argjson tracker "${claim_result}" '{kind:"tracker_issue_claim", tracker:$tracker}')"
  carrier_json="$(carrier_set_realization "${carrier_json}" "${realization_json}")"

  board_json="$(refresh_transition_board "${repo_root}" "${socket_path}")"
  board_summary="$(jq -c '.summary // null' <<<"${board_json}")"
  receipt_payload="$(jq -cn --arg issue_id "${issue_id}" --argjson issue "${issue_json}" --argjson board_summary "${board_summary}" '{issue_id:$issue_id, issue:$issue, board_summary:$board_summary}')"
  receipt_json="$(append_receipt_capture "${repo_root}" "issue.claim" "${receipt_payload}")"
  carrier_json="$(carrier_set_emitted_receipt "${carrier_json}" "${receipt_json}")"

  payload_json="$(jq -cn --arg repo_root "${repo_root}" --arg issue_id "${issue_id}" --argjson issue "${issue_json}" --argjson board_summary "${board_summary}" '{repo_root:$repo_root, issue_id:$issue_id, issue:$issue, board_summary:$board_summary}')"
  transition_success_result "${carrier_json}" "${payload_json}"
}

realize_close_issue_transition() {
  local repo_root="$1"
  local socket_path="$2"
  local carrier_json="$3"
  local issue_id
  local reason
  local close_result
  local issue_json
  local realization_json
  local board_json
  local board_summary
  local receipt_payload
  local receipt_json
  local payload_json

  issue_id="$(jq -r '.intent.payload.issue_id // ""' <<<"${carrier_json}")"
  reason="$(jq -r '.intent.payload.reason // ""' <<<"${carrier_json}")"

  close_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_issue_close" issue close "${issue_id}" --reason "${reason}")"
  if ! jq -e --arg issue_id "${issue_id}" '
      .ok and
      ((.output | type) == "array") and
      ((.output | length) > 0) and
      ((.output[0] | type) == "object") and
      ((.output[0].id // "") == $issue_id) and
      ((.output[0].status // "") == "closed")
    ' >/dev/null <<<"${close_result}"; then
    realization_json="$(jq -cn --argjson tracker "${close_result}" '{kind:"tracker_issue_close", tracker:$tracker}')"
    carrier_json="$(carrier_set_realization "${carrier_json}" "${realization_json}")"
    transition_failure_result "${carrier_json}" "tracker issue close failed" "$(jq -cn --argjson tracker "${close_result}" '{tracker:$tracker}')"
    return 0
  fi

  issue_json="$(jq -c '.output[0]' <<<"${close_result}")"
  carrier_json="$(carrier_set_issue "${carrier_json}" "${issue_json}")"
  realization_json="$(jq -cn --argjson tracker "${close_result}" '{kind:"tracker_issue_close", tracker:$tracker}')"
  carrier_json="$(carrier_set_realization "${carrier_json}" "${realization_json}")"

  board_json="$(refresh_transition_board "${repo_root}" "${socket_path}")"
  board_summary="$(jq -c '.summary // null' <<<"${board_json}")"
  receipt_payload="$(jq -cn --arg issue_id "${issue_id}" --arg reason "${reason}" --argjson issue "${issue_json}" --argjson board_summary "${board_summary}" '{issue_id:$issue_id, reason:$reason, issue:$issue, board_summary:$board_summary}')"
  receipt_json="$(append_receipt_capture "${repo_root}" "issue.close" "${receipt_payload}")"
  carrier_json="$(carrier_set_emitted_receipt "${carrier_json}" "${receipt_json}")"

  payload_json="$(jq -cn --arg repo_root "${repo_root}" --arg issue_id "${issue_id}" --arg reason "${reason}" --argjson issue "${issue_json}" --argjson board_summary "${board_summary}" '{repo_root:$repo_root, issue_id:$issue_id, reason:$reason, issue:$issue, board_summary:$board_summary}')"
  transition_success_result "${carrier_json}" "${payload_json}"
}

realize_launch_lane_transition() {
  local repo_root="$1"
  local socket_path="$2"
  local carrier_json="$3"
  local issue_id
  local issue_title
  local issue_json
  local workspace_name
  local workspace_path
  local base_rev
  local base_commit
  local add_output=""
  local add_exit=0
  local describe_output=""
  local describe_exit=0
  local rollback_json="null"
  local lane_record
  local realization_json
  local board_json
  local board_summary
  local lanes_json
  local receipt_payload
  local receipt_json=""
  local payload_json

  issue_id="$(jq -r '.intent.payload.issue_id // ""' <<<"${carrier_json}")"
  base_rev="$(jq -r '.intent.payload.base_rev // ""' <<<"${carrier_json}")"
  issue_json="$(jq -c '.issue // null' <<<"${carrier_json}")"
  issue_title="$(jq -r '.issue.title // ""' <<<"${carrier_json}")"
  workspace_name="$(jq -r '.workspace.name // ""' <<<"${carrier_json}")"
  workspace_path="$(jq -r '.workspace.path // ""' <<<"${carrier_json}")"
  base_commit="$(jq -r '.workspace.base_commit // ""' <<<"${carrier_json}")"

  mkdir -p "$(workspace_root_dir "${repo_root}")"
  if add_output="$(run_in_repo_capture "${repo_root}" jj --repository "${repo_root}" workspace add "${workspace_path}" --name "${workspace_name}" -r "${base_rev}")"; then
    add_exit=0
  else
    add_exit=$?
  fi
  if [ "${add_exit}" -ne 0 ]; then
    realization_json="$(jq -cn --arg workspace_name "${workspace_name}" --arg workspace_path "${workspace_path}" --arg base_rev "${base_rev}" --arg output "${add_output}" '{kind:"jj_workspace_add", workspace_name:$workspace_name, workspace_path:$workspace_path, base_rev:$base_rev, output:$output}')"
    carrier_json="$(carrier_set_realization "${carrier_json}" "${realization_json}")"
    transition_failure_result "${carrier_json}" "jj workspace add failed" "$(jq -cn --arg workspace_name "${workspace_name}" --arg workspace_path "${workspace_path}" --arg base_rev "${base_rev}" --arg output "${add_output}" '{workspace_name:$workspace_name, workspace_path:$workspace_path, base_rev:$base_rev, output:$output}')"
    return 0
  fi

  if transition_test_fail_phase "launch_lane" "after_workspace_add"; then
    rollback_json="$(rollback_launch_artifacts "${repo_root}" "${issue_id}" "${workspace_name}" "${workspace_path}")"
    realization_json="$(jq -cn --arg workspace_name "${workspace_name}" --arg workspace_path "${workspace_path}" --arg base_rev "${base_rev}" --arg add_output "${add_output}" --argjson rollback "${rollback_json}" '{kind:"launch_lane", workspace_name:$workspace_name, workspace_path:$workspace_path, base_rev:$base_rev, add_output:$add_output, rollback:$rollback, injected_failure_phase:"after_workspace_add"}')"
    carrier_json="$(carrier_set_realization "${carrier_json}" "${realization_json}")"
    transition_failure_result "${carrier_json}" "injected transition failure after workspace add" "$(jq -cn --arg workspace_name "${workspace_name}" --arg workspace_path "${workspace_path}" --argjson rollback "${rollback_json}" '{workspace_name:$workspace_name, workspace_path:$workspace_path, rollback:$rollback}')"
    return 0
  fi

  if describe_output="$(run_in_repo_capture "${repo_root}" jj --repository "${workspace_path}" describe -m "${issue_id}: wip")"; then
    describe_exit=0
  else
    describe_exit=$?
  fi
  if [ "${describe_exit}" -ne 0 ]; then
    rollback_json="$(rollback_launch_artifacts "${repo_root}" "${issue_id}" "${workspace_name}" "${workspace_path}")"
    realization_json="$(jq -cn --arg workspace_name "${workspace_name}" --arg workspace_path "${workspace_path}" --arg base_rev "${base_rev}" --arg add_output "${add_output}" --arg describe_output "${describe_output}" --argjson rollback "${rollback_json}" '{kind:"launch_lane", workspace_name:$workspace_name, workspace_path:$workspace_path, base_rev:$base_rev, add_output:$add_output, describe_output:$describe_output, rollback:$rollback}')"
    carrier_json="$(carrier_set_realization "${carrier_json}" "${realization_json}")"
    transition_failure_result "${carrier_json}" "jj describe failed after workspace creation" "$(jq -cn --arg workspace_name "${workspace_name}" --arg workspace_path "${workspace_path}" --arg output "${describe_output}" --argjson rollback "${rollback_json}" '{workspace_name:$workspace_name, workspace_path:$workspace_path, output:$output, rollback:$rollback}')"
    return 0
  fi

  lane_record="$(jq -cn --arg issue_id "${issue_id}" --arg issue_title "${issue_title}" --arg workspace_name "${workspace_name}" --arg workspace_path "${workspace_path}" --arg base_rev "${base_rev}" --arg base_commit "${base_commit}" --arg launched_at "$(now_iso8601)" '{issue_id:$issue_id, issue_title:$issue_title, status:"launched", workspace_name:$workspace_name, workspace_path:$workspace_path, base_rev:$base_rev, base_commit:$base_commit, launched_at:$launched_at}')"
  if ! upsert_lane_state "${repo_root}" "${lane_record}"; then
    rollback_json="$(rollback_launch_artifacts "${repo_root}" "${issue_id}" "${workspace_name}" "${workspace_path}")"
    realization_json="$(jq -cn --argjson lane "${lane_record}" --argjson rollback "${rollback_json}" '{kind:"launch_lane", lane:$lane, rollback:$rollback}')"
    carrier_json="$(carrier_set_realization "${carrier_json}" "${realization_json}")"
    transition_failure_result "${carrier_json}" "failed to persist lane state" "$(jq -cn --argjson lane "${lane_record}" --argjson rollback "${rollback_json}" '{lane:$lane, rollback:$rollback}')"
    return 0
  fi

  board_json="$(refresh_transition_board "${repo_root}" "${socket_path}")"
  board_summary="$(jq -c '.summary // null' <<<"${board_json}")"
  lanes_json="$(jq -c '.lanes // []' <<<"${board_json}")"
  receipt_payload="$(jq -cn --arg issue_id "${issue_id}" --arg issue_title "${issue_title}" --arg workspace_name "${workspace_name}" --arg workspace_path "${workspace_path}" --arg base_rev "${base_rev}" --arg base_commit "${base_commit}" --argjson issue "${issue_json}" --argjson board_summary "${board_summary}" '{issue_id:$issue_id, issue_title:$issue_title, workspace_name:$workspace_name, workspace_path:$workspace_path, base_rev:$base_rev, base_commit:$base_commit, issue:$issue, board_summary:$board_summary}')"

  if ! receipt_json="$(append_receipt_capture "${repo_root}" "lane.launch" "${receipt_payload}")"; then
    rollback_json="$(rollback_launch_artifacts "${repo_root}" "${issue_id}" "${workspace_name}" "${workspace_path}")"
    realization_json="$(jq -cn --argjson lane "${lane_record}" --argjson rollback "${rollback_json}" '{kind:"launch_lane", lane:$lane, rollback:$rollback}')"
    carrier_json="$(carrier_set_realization "${carrier_json}" "${realization_json}")"
    transition_failure_result "${carrier_json}" "failed to append lane.launch receipt" "$(jq -cn --argjson rollback "${rollback_json}" '{rollback:$rollback}')"
    return 0
  fi

  carrier_json="$(carrier_set_lane "${carrier_json}" "${lane_record}")"
  carrier_json="$(carrier_set_realization "${carrier_json}" "$(jq -cn --arg workspace_name "${workspace_name}" --arg workspace_path "${workspace_path}" --arg base_rev "${base_rev}" --arg base_commit "${base_commit}" --arg add_output "${add_output}" --arg describe_output "${describe_output}" '{kind:"launch_lane", workspace_name:$workspace_name, workspace_path:$workspace_path, base_rev:$base_rev, base_commit:$base_commit, add_output:$add_output, describe_output:$describe_output}')")"
  carrier_json="$(carrier_set_emitted_receipt "${carrier_json}" "${receipt_json}")"

  payload_json="$(jq -cn --arg repo_root "${repo_root}" --arg issue_id "${issue_id}" --arg issue_title "${issue_title}" --arg workspace_name "${workspace_name}" --arg workspace_path "${workspace_path}" --arg base_rev "${base_rev}" --arg base_commit "${base_commit}" --argjson issue "${issue_json}" --argjson lanes "${lanes_json}" --argjson board_summary "${board_summary}" '{repo_root:$repo_root, issue_id:$issue_id, issue_title:$issue_title, issue:$issue, workspace_name:$workspace_name, workspace_path:$workspace_path, base_rev:$base_rev, base_commit:$base_commit, lanes:$lanes, board_summary:$board_summary}')"
  transition_success_result "${carrier_json}" "${payload_json}"
}

realize_handoff_lane_transition() {
  local repo_root="$1"
  local socket_path="$2"
  local carrier_json="$3"
  local issue_id
  local note
  local previous_lane_json
  local resolved_revision
  local updated_lane_json
  local realization_json
  local board_json
  local board_summary
  local lanes_json
  local receipt_payload
  local receipt_json=""
  local payload_json

  issue_id="$(jq -r '.intent.payload.issue_id // ""' <<<"${carrier_json}")"
  note="$(jq -r '.intent.payload.note // ""' <<<"${carrier_json}")"
  previous_lane_json="$(jq -c '.lane // null' <<<"${carrier_json}")"
  resolved_revision="$(jq -r '.workspace.revision // ""' <<<"${carrier_json}")"

  updated_lane_json="$(jq -c --arg status "handoff" --arg handoff_revision "${resolved_revision}" --arg handed_off_at "$(now_iso8601)" --arg handoff_note "${note}" '(. + {status:$status, handoff_revision:$handoff_revision, handed_off_at:$handed_off_at}) | if ($handoff_note | length) > 0 then . + {handoff_note:$handoff_note} else del(.handoff_note) end' <<<"${previous_lane_json}")"
  if ! upsert_lane_state "${repo_root}" "${updated_lane_json}"; then
    realization_json="$(jq -cn --argjson lane "${updated_lane_json}" '{kind:"handoff_lane", lane:$lane}')"
    carrier_json="$(carrier_set_realization "${carrier_json}" "${realization_json}")"
    transition_failure_result "${carrier_json}" "failed to persist handed-off lane state" "$(jq -cn --argjson lane "${updated_lane_json}" '{lane:$lane}')"
    return 0
  fi

  board_json="$(refresh_transition_board "${repo_root}" "${socket_path}")"
  board_summary="$(jq -c '.summary // null' <<<"${board_json}")"
  lanes_json="$(jq -c '.lanes // []' <<<"${board_json}")"
  receipt_payload="$(jq -cn --arg issue_id "${issue_id}" --arg revision "${resolved_revision}" --arg note "${note}" --argjson lane "${updated_lane_json}" --argjson board_summary "${board_summary}" '{issue_id:$issue_id, revision:$revision, note:$note, lane:$lane, board_summary:$board_summary}')"

  if ! receipt_json="$(append_receipt_capture "${repo_root}" "lane.handoff" "${receipt_payload}")"; then
    restore_lane_state_snapshot "${repo_root}" "${previous_lane_json}" >/dev/null 2>&1 || true
    realization_json="$(jq -cn --argjson lane "${updated_lane_json}" --argjson restored_lane "${previous_lane_json}" '{kind:"handoff_lane", lane:$lane, restored_lane:$restored_lane}')"
    carrier_json="$(carrier_set_realization "${carrier_json}" "${realization_json}")"
    transition_failure_result "${carrier_json}" "failed to append lane.handoff receipt" "$(jq -cn --argjson restored_lane "${previous_lane_json}" '{restored_lane:$restored_lane}')"
    return 0
  fi

  carrier_json="$(carrier_set_lane "${carrier_json}" "${updated_lane_json}")"
  carrier_json="$(carrier_set_realization "${carrier_json}" "$(jq -cn --arg revision "${resolved_revision}" --arg note "${note}" '{kind:"handoff_lane", revision:$revision, note:$note}')")"
  carrier_json="$(carrier_set_emitted_receipt "${carrier_json}" "${receipt_json}")"

  payload_json="$(jq -cn --arg repo_root "${repo_root}" --arg issue_id "${issue_id}" --arg revision "${resolved_revision}" --arg note "${note}" --argjson lane "${updated_lane_json}" --argjson lanes "${lanes_json}" --argjson board_summary "${board_summary}" '{repo_root:$repo_root, issue_id:$issue_id, revision:$revision, note:$note, lane:$lane, lanes:$lanes, board_summary:$board_summary}')"
  transition_success_result "${carrier_json}" "${payload_json}"
}

realize_finish_lane_transition() {
  local repo_root="$1"
  local socket_path="$2"
  local carrier_json="$3"
  local issue_id
  local outcome
  local note
  local previous_lane_json
  local updated_lane_json
  local realization_json
  local board_json
  local board_summary
  local lanes_json
  local receipt_payload
  local receipt_json=""
  local payload_json

  issue_id="$(jq -r '.intent.payload.issue_id // ""' <<<"${carrier_json}")"
  outcome="$(jq -r '.intent.payload.outcome // ""' <<<"${carrier_json}")"
  note="$(jq -r '.intent.payload.note // ""' <<<"${carrier_json}")"
  previous_lane_json="$(jq -c '.lane // null' <<<"${carrier_json}")"

  updated_lane_json="$(jq -c --arg status "finished" --arg outcome "${outcome}" --arg finished_at "$(now_iso8601)" --arg finish_note "${note}" '(. + {status:$status, outcome:$outcome, finished_at:$finished_at}) | if ($finish_note | length) > 0 then . + {finish_note:$finish_note} else del(.finish_note) end' <<<"${previous_lane_json}")"
  if ! upsert_lane_state "${repo_root}" "${updated_lane_json}"; then
    realization_json="$(jq -cn --argjson lane "${updated_lane_json}" '{kind:"finish_lane", lane:$lane}')"
    carrier_json="$(carrier_set_realization "${carrier_json}" "${realization_json}")"
    transition_failure_result "${carrier_json}" "failed to persist finished lane state" "$(jq -cn --argjson lane "${updated_lane_json}" '{lane:$lane}')"
    return 0
  fi

  board_json="$(refresh_transition_board "${repo_root}" "${socket_path}")"
  board_summary="$(jq -c '.summary // null' <<<"${board_json}")"
  lanes_json="$(jq -c '.lanes // []' <<<"${board_json}")"
  receipt_payload="$(jq -cn --arg issue_id "${issue_id}" --arg outcome "${outcome}" --arg note "${note}" --argjson lane "${updated_lane_json}" --argjson board_summary "${board_summary}" '{issue_id:$issue_id, outcome:$outcome, note:$note, lane:$lane, board_summary:$board_summary}')"

  if ! receipt_json="$(append_receipt_capture "${repo_root}" "lane.finish" "${receipt_payload}")"; then
    restore_lane_state_snapshot "${repo_root}" "${previous_lane_json}" >/dev/null 2>&1 || true
    realization_json="$(jq -cn --argjson lane "${updated_lane_json}" --argjson restored_lane "${previous_lane_json}" '{kind:"finish_lane", lane:$lane, restored_lane:$restored_lane}')"
    carrier_json="$(carrier_set_realization "${carrier_json}" "${realization_json}")"
    transition_failure_result "${carrier_json}" "failed to append lane.finish receipt" "$(jq -cn --argjson restored_lane "${previous_lane_json}" '{restored_lane:$restored_lane}')"
    return 0
  fi

  carrier_json="$(carrier_set_lane "${carrier_json}" "${updated_lane_json}")"
  carrier_json="$(carrier_set_realization "${carrier_json}" "$(jq -cn --arg outcome "${outcome}" --arg note "${note}" '{kind:"finish_lane", outcome:$outcome, note:$note}')")"
  carrier_json="$(carrier_set_emitted_receipt "${carrier_json}" "${receipt_json}")"

  payload_json="$(jq -cn --arg repo_root "${repo_root}" --arg issue_id "${issue_id}" --arg outcome "${outcome}" --arg note "${note}" --argjson lane "${updated_lane_json}" --argjson lanes "${lanes_json}" --argjson board_summary "${board_summary}" '{repo_root:$repo_root, issue_id:$issue_id, outcome:$outcome, note:$note, lane:$lane, lanes:$lanes, board_summary:$board_summary}')"
  transition_success_result "${carrier_json}" "${payload_json}"
}

realize_archive_lane_transition() {
  local repo_root="$1"
  local socket_path="$2"
  local carrier_json="$3"
  local issue_id
  local note
  local archived_lane_json
  local realization_json
  local board_json
  local board_summary
  local lanes_json
  local receipt_payload
  local receipt_json=""
  local payload_json

  issue_id="$(jq -r '.intent.payload.issue_id // ""' <<<"${carrier_json}")"
  note="$(jq -r '.intent.payload.note // ""' <<<"${carrier_json}")"
  archived_lane_json="$(jq -c '.lane // null' <<<"${carrier_json}")"

  if ! remove_lane_state "${repo_root}" "${issue_id}"; then
    realization_json="$(jq -cn --arg issue_id "${issue_id}" '{kind:"archive_lane", issue_id:$issue_id}')"
    carrier_json="$(carrier_set_realization "${carrier_json}" "${realization_json}")"
    transition_failure_result "${carrier_json}" "failed to remove live lane state" "$(jq -cn --arg issue_id "${issue_id}" '{issue_id:$issue_id}')"
    return 0
  fi

  board_json="$(refresh_transition_board "${repo_root}" "${socket_path}")"
  board_summary="$(jq -c '.summary // null' <<<"${board_json}")"
  lanes_json="$(jq -c '.lanes // []' <<<"${board_json}")"
  receipt_payload="$(jq -cn --arg issue_id "${issue_id}" --arg note "${note}" --argjson lane "${archived_lane_json}" --argjson board_summary "${board_summary}" '{issue_id:$issue_id, note:$note, lane:$lane, board_summary:$board_summary}')"

  if ! receipt_json="$(append_receipt_capture "${repo_root}" "lane.archive" "${receipt_payload}")"; then
    restore_lane_state_snapshot "${repo_root}" "${archived_lane_json}" >/dev/null 2>&1 || true
    realization_json="$(jq -cn --arg issue_id "${issue_id}" --argjson restored_lane "${archived_lane_json}" '{kind:"archive_lane", issue_id:$issue_id, restored_lane:$restored_lane}')"
    carrier_json="$(carrier_set_realization "${carrier_json}" "${realization_json}")"
    transition_failure_result "${carrier_json}" "failed to append lane.archive receipt" "$(jq -cn --argjson restored_lane "${archived_lane_json}" '{restored_lane:$restored_lane}')"
    return 0
  fi

  carrier_json="$(carrier_set_realization "${carrier_json}" "$(jq -cn --arg issue_id "${issue_id}" --arg note "${note}" '{kind:"archive_lane", issue_id:$issue_id, note:$note}')")"
  carrier_json="$(carrier_set_emitted_receipt "${carrier_json}" "${receipt_json}")"

  payload_json="$(jq -cn --arg repo_root "${repo_root}" --arg issue_id "${issue_id}" --arg note "${note}" --argjson archived_lane "${archived_lane_json}" --argjson lanes "${lanes_json}" --argjson board_summary "${board_summary}" '{repo_root:$repo_root, issue_id:$issue_id, note:$note, archived_lane:$archived_lane, lanes:$lanes, board_summary:$board_summary}')"
  transition_success_result "${carrier_json}" "${payload_json}"
}

run_transition_action() {
  local repo_root="$1"
  local socket_path="$2"
  local kind="$3"
  local payload_json="$4"

  if ! is_action_request_kind "${kind}"; then
    jq -cn --arg kind "${kind}" '{ok:false, error:{message:"unknown transition kind", kind:$kind}}'
    return 0
  fi

  if run_tuskd_core action-run \
    --repo "${repo_root}" \
    --socket "${socket_path}" \
    --kind "${kind}" \
    --payload "${payload_json}"; then
    return 0
  fi

  jq -cn --arg kind "${kind}" '{ok:false, error:{message:"failed to run transition action", kind:$kind}}'
}

cmd_transition_action() {
  local repo_root="$1"
  local socket_path="$2"
  local kind="$3"
  local payload_json="$4"
  local action_result

  action_result="$(run_transition_action "${repo_root}" "${socket_path}" "${kind}" "${payload_json}")"
  if jq -e '.ok == true' >/dev/null <<<"${action_result}"; then
    jq -c '.payload' <<<"${action_result}"
    return 0
  fi

  render_actionable_summary \
    "${kind//_/-}" \
    "$(jq -r '.error.message // "request failed"' <<<"${action_result}")" \
    "${action_result}" \
    >&2 || true
  jq -c '.' <<<"${action_result}"
  return 1
}

render_transition_request_response() {
  local request_id="$1"
  local kind="$2"
  local action_result="$3"
  local message=""
  local payload="null"

  if jq -e '.ok == true' >/dev/null <<<"${action_result}"; then
    payload="$(jq -c '.payload' <<<"${action_result}")"
    jq -cn \
      --arg request_id "${request_id}" \
      --arg kind "${kind}" \
      --argjson payload "${payload}" \
      '{request_id:$request_id, ok:true, kind:$kind, payload:$payload}'
    return 0
  fi

  message="$(jq -r '.error.message // "request failed"' <<<"${action_result}")"
  jq -cn \
    --arg request_id "${request_id}" \
    --arg kind "${kind}" \
    --arg message "${message}" \
    --argjson details "${action_result}" \
    '{request_id:$request_id, ok:false, kind:$kind, error:{message:$message, details:$details}}'
}

respond_once() {
  local repo_root="$1"
  local socket_path="$2"
  local request_body=""
  local request_id=""
  local kind=""
  local payload=""
  local core_exit=0

  if ! request_body="$(cat)"; then
    jq -cn \
      --arg request_id "" \
      --arg kind "" \
      --arg message "failed to read request body" \
      '{request_id:$request_id, ok:false, kind:$kind, error:{message:$message}}'
    return 0
  fi

  if [ -z "$(printf '%s' "${request_body}" | tr -d '[:space:]')" ]; then
    jq -cn \
      --arg request_id "" \
      --arg kind "" \
      --arg message "missing request body" \
      '{request_id:$request_id, ok:false, kind:$kind, error:{message:$message}}'
    return 0
  fi

  if ! printf '%s' "${request_body}" | jq -e . >/dev/null 2>&1; then
    jq -cn \
      --arg request_id "" \
      --arg kind "" \
      --arg message "request was not valid JSON" \
      '{request_id:$request_id, ok:false, kind:$kind, error:{message:$message}}'
    return 0
  fi

  if payload="$(printf '%s' "${request_body}" | run_tuskd_core respond --repo "${repo_root}" --socket "${socket_path}" 2>/dev/null)"; then
    printf '%s\n' "${payload}"
    return 0
  fi

  request_id="$(printf '%s' "${request_body}" | jq -r '.request_id // ""')"
  kind="$(printf '%s' "${request_body}" | jq -r '.kind // ""')"

  payload="$(printf '%s' "${request_body}" | run_tuskd_core respond --repo "${repo_root}" --socket "${socket_path}" 2>/dev/null)"
  core_exit=$?
  if [ "${core_exit}" -eq 0 ]; then
    printf '%s\n' "${payload}"
    return 0
  fi

  if [ "${core_exit}" -eq 64 ]; then
    jq -cn \
      --arg request_id "${request_id}" \
      --arg kind "${kind}" \
      --arg message "unknown request kind" \
      '{request_id:$request_id, ok:false, kind:$kind, error:{message:$message}}'
    return 0
  fi
  jq -cn \
    --arg request_id "${request_id}" \
    --arg kind "${kind}" \
    --arg message "request handling failed" \
    '{request_id:$request_id, ok:false, kind:$kind, error:{message:$message}}'
}

cmd_ensure() {
  local repo_root="$1"
  local socket_path="$2"

  exec_tuskd_core ensure --repo "${repo_root}" --socket "${socket_path}"
}

cmd_status() {
  local repo_root="$1"
  local socket_path="$2"

  exec_tuskd_core status --repo "${repo_root}" --socket "${socket_path}"
}

coordinator_status_payload() {
  local repo_root="$1"
  local output=""

  if output="$(run_tuskd_core coordinator-status --repo "${repo_root}" 2>/dev/null)"; then
    printf '%s\n' "${output}"
    return 0
  fi

  printf '%s\n' "${output}"
}

cmd_coordinator_status() {
  local repo_root="$1"

  exec_tuskd_core coordinator-status --repo "${repo_root}"
}

cmd_operator_snapshot() {
  local repo_root="$1"
  local socket_path="$2"

  exec_tuskd_core operator-snapshot --repo "${repo_root}" --socket "${socket_path}"
}

cmd_board_status() {
  local repo_root="$1"
  local socket_path="$2"

  exec_tuskd_core board-status --repo "${repo_root}" --socket "${socket_path}"
}

cmd_receipts_status() {
  local repo_root="$1"
  local socket_path="$2"

  exec_tuskd_core receipts-status --repo "${repo_root}" --socket "${socket_path}"
}

cmd_self_host_run() {
  local repo_root="$1"
  local checkout_root="${2:-}"
  local realization_id="${3:-self.trace-core-health.local}"
  local note="${4:-}"
  local plan_only="${5:-false}"
  local -a args=()

  args+=(--repo "${repo_root}")
  if [ -n "${checkout_root}" ]; then
    args+=(--checkout "${checkout_root}")
  fi
  if [ -n "${realization_id}" ]; then
    args+=(--realization "${realization_id}")
  fi
  if [ -n "${note}" ]; then
    args+=(--note "${note}")
  fi
  if [ "${plan_only}" = "true" ]; then
    args+=(--plan)
  fi

  exec "${TUSK_SELF_HOST_BIN}" "${args[@]}"
}

cmd_land_main() {
  local repo_root="$1"
  local revision="$2"
  local note="${3:-}"
  local plan_only="${4:-false}"
  local target_lookup=""
  local main_lookup=""
  local git_main_before=""
  local git_main_after=""
  local before_coordinator=""
  local after_coordinator=""
  local target_commit=""
  local main_before_commit=""
  local git_before_commit=""
  local move_output=""
  local move_exit=0
  local export_output=""
  local export_exit=0
  local repair_json='{"ok":true,"payload":null}'
  local repair_status=0
  local needs_repair_after_land=false
  local landed_status=""
  local receipt_payload=""
  local receipt_json=""

  target_lookup="$(resolve_revision_commit "${repo_root}" "${revision}")"
  if ! jq -e '.ok == true' >/dev/null <<<"${target_lookup}"; then
    jq -cn \
      --arg revision "${revision}" \
      --argjson target "${target_lookup}" \
      '{
        ok: false,
        error: {
          message: "land-main requires --revision to resolve to a commit"
        },
        payload: {
          revision: $revision,
          target: $target
        }
      }'
    return 1
  fi

  main_lookup="$(resolve_revision_commit "${repo_root}" "main")"
  git_main_before="$(resolve_git_ref_commit "${repo_root}" "refs/heads/main")"
  before_coordinator="$(coordinator_status_payload "${repo_root}")"
  target_commit="$(jq -r '.commit // ""' <<<"${target_lookup}")"
  main_before_commit="$(jq -r '.commit // ""' <<<"${main_lookup}")"
  git_before_commit="$(jq -r '.commit // ""' <<<"${git_main_before}")"

  if jq -e --arg commit "${target_commit}" '.parent_commits | index($commit) != null' >/dev/null <<<"${before_coordinator}"; then
    needs_repair_after_land=false
  else
    needs_repair_after_land=true
  fi

  if [ "${plan_only}" = "true" ]; then
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg revision "${revision}" \
      --arg target_commit "${target_commit}" \
      --arg main_before_commit "${main_before_commit}" \
      --arg note "${note}" \
      --argjson before_coordinator "${before_coordinator}" \
      --argjson git_main_before "${git_main_before}" \
      --argjson needs_repair_after_land "$(json_bool "${needs_repair_after_land}")" \
      '{
        ok: true,
        payload: {
          repo_root: $repo_root,
          revision: $revision,
          target_commit: $target_commit,
          main_before_commit: (if ($main_before_commit | length) > 0 then $main_before_commit else null end),
          note: (if ($note | length) > 0 then $note else null end),
          status: "plan",
          before: {
            coordinator: $before_coordinator,
            git_main: $git_main_before
          },
          needs_repair_after_land: $needs_repair_after_land,
          commands: [
            ("jj --repository " + $repo_root + " bookmark move main --to " + $revision),
            ("jj --repository " + $repo_root + " git export")
          ] + (if $needs_repair_after_land then [
            ("tuskd repair-coordinator --repo " + $repo_root + " --target-rev main")
          ] else [] end)
        }
      }'
    return 0
  fi

  if [ "${target_commit}" = "${main_before_commit}" ] \
    && [ "${target_commit}" = "${git_before_commit}" ] \
    && jq -e '.needs_repair != true' >/dev/null <<<"${before_coordinator}"; then
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg revision "${revision}" \
      --arg target_commit "${target_commit}" \
      --arg note "${note}" \
      --argjson before_coordinator "${before_coordinator}" \
      --argjson git_main_before "${git_main_before}" \
      '{
        ok: true,
        payload: {
          repo_root: $repo_root,
          revision: $revision,
          target_commit: $target_commit,
          note: (if ($note | length) > 0 then $note else null end),
          status: "noop",
          before: {
            coordinator: $before_coordinator,
            git_main: $git_main_before
          },
          after: {
            coordinator: $before_coordinator,
            git_main: $git_main_before
          },
          repair: null
        }
      }'
    return 0
  fi

  if move_output="$(run_in_repo_capture "${repo_root}" jj --repository "${repo_root}" bookmark move main --to "${revision}")"; then
    move_exit=0
  else
    move_exit=$?
  fi
  if [ "${move_exit}" -ne 0 ]; then
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg revision "${revision}" \
      --arg output "${move_output}" \
      --argjson before_coordinator "${before_coordinator}" \
      --argjson git_main_before "${git_main_before}" \
      '{
        ok: false,
        error: {
          message: "land-main failed to move the main bookmark"
        },
        payload: {
          repo_root: $repo_root,
          revision: $revision,
          before: {
            coordinator: $before_coordinator,
            git_main: $git_main_before
          },
          bookmark_move: {
            exit_code: 1,
            output: (if ($output | length) > 0 then $output else null end)
          }
        }
      }'
    return 1
  fi

  if export_output="$(run_in_repo_capture "${repo_root}" jj --repository "${repo_root}" git export)"; then
    export_exit=0
  else
    export_exit=$?
  fi
  git_main_after="$(resolve_git_ref_commit "${repo_root}" "refs/heads/main")"

  if [ "${export_exit}" -ne 0 ] || ! jq -e --arg commit "${target_commit}" '.commit == $commit' >/dev/null <<<"${git_main_after}"; then
    after_coordinator="$(coordinator_status_payload "${repo_root}")"
    landed_status="export_failed"
    receipt_payload="$(jq -cn \
      --arg repo_root "${repo_root}" \
      --arg revision "${revision}" \
      --arg target_commit "${target_commit}" \
      --arg note "${note}" \
      --arg status "${landed_status}" \
      --arg move_output "${move_output}" \
      --arg export_output "${export_output}" \
      --argjson export_exit "${export_exit}" \
      --argjson before_coordinator "${before_coordinator}" \
      --argjson after_coordinator "${after_coordinator}" \
      --argjson git_main_before "${git_main_before}" \
      --argjson git_main_after "${git_main_after}" \
      '{
        repo_root: $repo_root,
        revision: $revision,
        target_commit: $target_commit,
        note: (if ($note | length) > 0 then $note else null end),
        status: $status,
        bookmark_move: {
          exit_code: 0,
          output: (if ($move_output | length) > 0 then $move_output else null end)
        },
        git_export: {
          exit_code: $export_exit,
          output: (if ($export_output | length) > 0 then $export_output else null end)
        },
        before: {
          coordinator: $before_coordinator,
          git_main: $git_main_before
        },
        after: {
          coordinator: $after_coordinator,
          git_main: $git_main_after
        },
        repair: null
      }')"
    receipt_json="$(append_receipt_capture "${repo_root}" "land.main" "${receipt_payload}")" || true
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg revision "${revision}" \
      --arg status "${landed_status}" \
      --argjson before_coordinator "${before_coordinator}" \
      --argjson after_coordinator "${after_coordinator}" \
      --argjson git_main_before "${git_main_before}" \
      --argjson git_main_after "${git_main_after}" \
      --arg move_output "${move_output}" \
      --arg export_output "${export_output}" \
      --argjson export_exit "${export_exit}" \
      --argjson receipt "$(if [ -n "${receipt_json}" ]; then printf '%s' "${receipt_json}"; else printf 'null'; fi)" \
      '{
        ok: false,
        error: {
          message: "land-main failed to export the colocated Git main ref"
        },
        payload: {
          repo_root: $repo_root,
          revision: $revision,
          status: $status,
          bookmark_move: {
            exit_code: 0,
            output: (if ($move_output | length) > 0 then $move_output else null end)
          },
          git_export: {
            exit_code: $export_exit,
            output: (if ($export_output | length) > 0 then $export_output else null end)
          },
          before: {
            coordinator: $before_coordinator,
            git_main: $git_main_before
          },
          after: {
            coordinator: $after_coordinator,
            git_main: $git_main_after
          },
          receipt: $receipt
        }
      }'
    return 1
  fi

  repair_json='{"ok":true,"payload":null}'
  repair_status=0
  if [ "${needs_repair_after_land}" = true ]; then
    if repair_json="$(cmd_repair_coordinator "${repo_root}" "main" "${note}" "false")"; then
      repair_status=0
    else
      repair_status=$?
    fi
  fi

  after_coordinator="$(coordinator_status_payload "${repo_root}")"
  if [ "${repair_status}" -ne 0 ]; then
    landed_status="landed_repair_failed"
  elif [ "${needs_repair_after_land}" = true ]; then
    landed_status="landed_repaired"
  else
    landed_status="landed"
  fi

  receipt_payload="$(jq -cn \
    --arg repo_root "${repo_root}" \
    --arg revision "${revision}" \
    --arg target_commit "${target_commit}" \
    --arg note "${note}" \
    --arg status "${landed_status}" \
    --arg move_output "${move_output}" \
    --arg export_output "${export_output}" \
    --argjson before_coordinator "${before_coordinator}" \
    --argjson after_coordinator "${after_coordinator}" \
    --argjson git_main_before "${git_main_before}" \
    --argjson git_main_after "${git_main_after}" \
    --argjson repair "${repair_json}" \
    '{
      repo_root: $repo_root,
      revision: $revision,
      target_commit: $target_commit,
      note: (if ($note | length) > 0 then $note else null end),
      status: $status,
      bookmark_move: {
        exit_code: 0,
        output: (if ($move_output | length) > 0 then $move_output else null end)
      },
      git_export: {
        exit_code: 0,
        output: (if ($export_output | length) > 0 then $export_output else null end)
      },
      before: {
        coordinator: $before_coordinator,
        git_main: $git_main_before
      },
      after: {
        coordinator: $after_coordinator,
        git_main: $git_main_after
      },
      repair: ($repair.payload // null)
    }')"

  if ! receipt_json="$(append_receipt_capture "${repo_root}" "land.main" "${receipt_payload}")"; then
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg revision "${revision}" \
      --arg status "${landed_status}" \
      --argjson before_coordinator "${before_coordinator}" \
      --argjson after_coordinator "${after_coordinator}" \
      --argjson git_main_before "${git_main_before}" \
      --argjson git_main_after "${git_main_after}" \
      --argjson repair "${repair_json}" \
      '{
        ok: false,
        error: {
          message: "land-main failed to append land.main receipt"
        },
        payload: {
          repo_root: $repo_root,
          revision: $revision,
          status: $status,
          before: {
            coordinator: $before_coordinator,
            git_main: $git_main_before
          },
          after: {
            coordinator: $after_coordinator,
            git_main: $git_main_after
          },
          repair: ($repair.payload // null)
        }
      }'
    return 1
  fi

  jq -cn \
    --arg repo_root "${repo_root}" \
    --arg revision "${revision}" \
    --arg target_commit "${target_commit}" \
    --arg note "${note}" \
    --arg status "${landed_status}" \
    --argjson before_coordinator "${before_coordinator}" \
    --argjson after_coordinator "${after_coordinator}" \
    --argjson git_main_before "${git_main_before}" \
    --argjson git_main_after "${git_main_after}" \
    --argjson repair "${repair_json}" \
    --argjson receipt "${receipt_json}" \
    '{
      ok: ($status == "landed" or $status == "landed_repaired"),
      payload: {
        repo_root: $repo_root,
        revision: $revision,
        target_commit: $target_commit,
        note: (if ($note | length) > 0 then $note else null end),
        status: $status,
        before: {
          coordinator: $before_coordinator,
          git_main: $git_main_before
        },
        after: {
          coordinator: $after_coordinator,
          git_main: $git_main_after
        },
        repair: ($repair.payload // null),
        receipt: $receipt
      }
    }'

  [ "${landed_status}" = "landed" ] || [ "${landed_status}" = "landed_repaired" ]
}

cmd_repair_coordinator() {
  local repo_root="$1"
  local target_rev="${2:-main}"
  local note="${3:-}"
  local plan_only="${4:-false}"
  local before_json
  local after_json
  local rebase_output=""
  local rebase_exit=0
  local status=""
  local receipt_payload=""
  local receipt_json=""

  before_json="$(coordinator_status_payload "${repo_root}")"
  if [ "${plan_only}" = "true" ]; then
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg target_rev "${target_rev}" \
      --arg note "${note}" \
      --argjson before "${before_json}" \
      '{
        ok: true,
        payload: {
          repo_root: $repo_root,
          target_rev: $target_rev,
          note: (if ($note | length) > 0 then $note else null end),
          status: "plan",
          before: $before,
          command: ("jj --repository " + $repo_root + " rebase -s @ -d " + $target_rev)
        }
      }'
    return 0
  fi

  if ! jq -e '.needs_repair == true' >/dev/null <<<"${before_json}"; then
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg target_rev "${target_rev}" \
      --arg note "${note}" \
      --argjson before "${before_json}" \
      '{
        ok: true,
        payload: {
          repo_root: $repo_root,
          target_rev: $target_rev,
          note: (if ($note | length) > 0 then $note else null end),
          status: "noop",
          before: $before,
          after: $before
        }
      }'
    return 0
  fi

  if rebase_output="$(run_in_repo_capture "${repo_root}" jj --repository "${repo_root}" rebase -s @ -d "${target_rev}")"; then
    rebase_exit=0
  else
    rebase_exit=$?
  fi

  after_json="$(coordinator_status_payload "${repo_root}")"
  if [ "${rebase_exit}" -ne 0 ]; then
    status="rebase_failed"
  elif jq -e '.conflicted == true' >/dev/null <<<"${after_json}"; then
    status="conflicted"
  elif jq -e '.drifted == true' >/dev/null <<<"${after_json}"; then
    status="still_drifted"
  else
    status="repaired"
  fi

  receipt_payload="$(jq -cn \
    --arg repo_root "${repo_root}" \
    --arg target_rev "${target_rev}" \
    --arg note "${note}" \
    --arg status "${status}" \
    --arg rebase_output "${rebase_output}" \
    --argjson rebase_exit "${rebase_exit}" \
    --argjson before "${before_json}" \
    --argjson after "${after_json}" \
    '{
      repo_root: $repo_root,
      target_rev: $target_rev,
      note: (if ($note | length) > 0 then $note else null end),
      status: $status,
      rebase: {
        exit_code: $rebase_exit,
        output: (if ($rebase_output | length) > 0 then $rebase_output else null end)
      },
      before: $before,
      after: $after
    }')"

  if ! receipt_json="$(append_receipt_capture "${repo_root}" "coordinator.sync" "${receipt_payload}")"; then
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg target_rev "${target_rev}" \
      --arg status "${status}" \
      --argjson before "${before_json}" \
      --argjson after "${after_json}" \
      --argjson rebase_exit "${rebase_exit}" \
      --arg rebase_output "${rebase_output}" \
      '{
        ok: false,
        error: {
          message: "repair-coordinator failed to append coordinator.sync receipt"
        },
        payload: {
          repo_root: $repo_root,
          target_rev: $target_rev,
          status: $status,
          before: $before,
          after: $after,
          rebase: {
            exit_code: $rebase_exit,
            output: (if ($rebase_output | length) > 0 then $rebase_output else null end)
          }
        }
      }'
    return 1
  fi

  jq -cn \
    --arg repo_root "${repo_root}" \
    --arg target_rev "${target_rev}" \
    --arg note "${note}" \
    --arg status "${status}" \
    --argjson before "${before_json}" \
    --argjson after "${after_json}" \
    --argjson rebase_exit "${rebase_exit}" \
    --arg rebase_output "${rebase_output}" \
    --argjson receipt "${receipt_json}" \
    '{
      ok: ($status == "repaired"),
      payload: {
        repo_root: $repo_root,
        target_rev: $target_rev,
        note: (if ($note | length) > 0 then $note else null end),
        status: $status,
        before: $before,
        after: $after,
        rebase: {
          exit_code: $rebase_exit,
          output: (if ($rebase_output | length) > 0 then $rebase_output else null end)
        },
        receipt: $receipt
      }
    }'

  [ "${status}" = "repaired" ]
}

cmd_claim_issue() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  cmd_transition_action "${repo_root}" "${socket_path}" "claim_issue" "$(jq -cn --arg issue_id "${issue_id}" '{issue_id:$issue_id}')"
}

cmd_close_issue() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local reason="$4"
  cmd_transition_action "${repo_root}" "${socket_path}" "close_issue" "$(jq -cn --arg issue_id "${issue_id}" --arg reason "${reason}" '{issue_id:$issue_id, reason:$reason}')"
}

cmd_launch_lane() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local base_rev="$4"
  local slug="${5:-}"
  cmd_transition_action "${repo_root}" "${socket_path}" "launch_lane" "$(jq -cn --arg issue_id "${issue_id}" --arg base_rev "${base_rev}" --arg slug "${slug}" '{issue_id:$issue_id, base_rev:$base_rev, slug:$slug}')"
}

cmd_handoff_lane() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local revision="$4"
  local note="${5:-}"
  cmd_transition_action "${repo_root}" "${socket_path}" "handoff_lane" "$(jq -cn --arg issue_id "${issue_id}" --arg revision "${revision}" --arg note "${note}" '{issue_id:$issue_id, revision:$revision, note:$note}')"
}

cmd_finish_lane() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local outcome="$4"
  local note="${5:-}"
  cmd_transition_action "${repo_root}" "${socket_path}" "finish_lane" "$(jq -cn --arg issue_id "${issue_id}" --arg outcome "${outcome}" --arg note "${note}" '{issue_id:$issue_id, outcome:$outcome, note:$note}')"
}

cmd_archive_lane() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local note="${4:-}"
  cmd_transition_action "${repo_root}" "${socket_path}" "archive_lane" "$(jq -cn --arg issue_id "${issue_id}" --arg note "${note}" '{issue_id:$issue_id, note:$note}')"
}

compact_lane_action() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local revision="$4"
  local reason="$5"
  local outcome="${6:-completed}"
  local note="${7:-}"
  local quarantine_requested="${8:-false}"
  local lane_json="null"
  local lane_status=""
  local workspace_name=""
  local workspace_path=""
  local handoff_result='{"ok":true,"payload":null}'
  local finish_result='{"ok":true,"payload":null}'
  local cleanup_result='{"ok":true,"payload":null}'
  local archive_result='{"ok":true,"payload":null}'
  local close_result='{"ok":true,"payload":null}'

  if [ -z "${issue_id}" ]; then
    jq -cn '{ok:false, error:{message:"compact_lane requires issue_id"}}'
    return 0
  fi

  if [ -z "${reason}" ]; then
    jq -cn --arg issue_id "${issue_id}" '{ok:false, error:{message:"compact_lane requires reason"}, issue_id:$issue_id}'
    return 0
  fi

  ensure_state_files "${repo_root}"
  lane_json="$(current_lane_for_issue "${repo_root}" "${issue_id}")"
  if [ "${lane_json}" = "null" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      '{ok:false, issue_id:$issue_id, error:{message:"compact_lane requires an existing lane record"}}'
    return 0
  fi

  lane_status="$(jq -r '.status // ""' <<<"${lane_json}")"
  workspace_name="$(jq -r '.workspace_name // ""' <<<"${lane_json}")"
  workspace_path="$(jq -r '.workspace_path // ""' <<<"${lane_json}")"

  case "${lane_status}" in
    launched)
      if [ -z "${revision}" ]; then
        jq -cn \
          --arg issue_id "${issue_id}" \
          --arg status "${lane_status}" \
          '{ok:false, issue_id:$issue_id, status:$status, error:{message:"compact_lane requires --revision before a launched lane can be compacted"}}'
        return 0
      fi
      handoff_result="$(run_transition_action "${repo_root}" "${socket_path}" "handoff_lane" "$(jq -cn --arg issue_id "${issue_id}" --arg revision "${revision}" --arg note "${note}" '{issue_id:$issue_id, revision:$revision, note:$note}')")"
      if ! jq -e '.ok == true' >/dev/null <<<"${handoff_result}"; then
        jq -cn \
          --arg issue_id "${issue_id}" \
          --arg status "${lane_status}" \
          --argjson details "${handoff_result}" \
          '{ok:false, issue_id:$issue_id, status:$status, error:{message:"compact_lane failed during handoff_lane", details:$details}}'
        return 0
      fi
      finish_result="$(run_transition_action "${repo_root}" "${socket_path}" "finish_lane" "$(jq -cn --arg issue_id "${issue_id}" --arg outcome "${outcome}" --arg note "${note}" '{issue_id:$issue_id, outcome:$outcome, note:$note}')")"
      if ! jq -e '.ok == true' >/dev/null <<<"${finish_result}"; then
        jq -cn \
          --arg issue_id "${issue_id}" \
          --arg status "${lane_status}" \
          --argjson details "${finish_result}" \
          '{ok:false, issue_id:$issue_id, status:$status, error:{message:"compact_lane failed during finish_lane", details:$details}}'
        return 0
      fi
      ;;
    handed_off)
      finish_result="$(run_transition_action "${repo_root}" "${socket_path}" "finish_lane" "$(jq -cn --arg issue_id "${issue_id}" --arg outcome "${outcome}" --arg note "${note}" '{issue_id:$issue_id, outcome:$outcome, note:$note}')")"
      if ! jq -e '.ok == true' >/dev/null <<<"${finish_result}"; then
        jq -cn \
          --arg issue_id "${issue_id}" \
          --arg status "${lane_status}" \
          --argjson details "${finish_result}" \
          '{ok:false, issue_id:$issue_id, status:$status, error:{message:"compact_lane failed during finish_lane", details:$details}}'
        return 0
      fi
      ;;
    finished)
      ;;
    *)
      jq -cn \
        --arg issue_id "${issue_id}" \
        --arg status "${lane_status}" \
        '{ok:false, issue_id:$issue_id, status:$status, error:{message:"compact_lane requires a launched, handed_off, or finished lane"}}'
      return 0
      ;;
  esac

  cleanup_result="$(compact_lane_workspace "${repo_root}" "${issue_id}" "${workspace_name}" "${workspace_path}" "${quarantine_requested}")"
  if ! jq -e '.ok == true' >/dev/null <<<"${cleanup_result}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg status "${lane_status}" \
      --argjson details "${cleanup_result}" \
      '{ok:false, issue_id:$issue_id, status:$status, error:{message:"compact_lane failed during workspace cleanup", details:$details}}'
    return 0
  fi

  archive_result="$(run_transition_action "${repo_root}" "${socket_path}" "archive_lane" "$(jq -cn --arg issue_id "${issue_id}" --arg note "${note}" '{issue_id:$issue_id, note:$note}')")"
  if ! jq -e '.ok == true' >/dev/null <<<"${archive_result}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg status "${lane_status}" \
      --argjson details "${archive_result}" \
      '{ok:false, issue_id:$issue_id, status:$status, error:{message:"compact_lane failed during archive_lane", details:$details}}'
    return 0
  fi

  close_result="$(run_transition_action "${repo_root}" "${socket_path}" "close_issue" "$(jq -cn --arg issue_id "${issue_id}" --arg reason "${reason}" '{issue_id:$issue_id, reason:$reason}')")"
  if ! jq -e '.ok == true' >/dev/null <<<"${close_result}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg status "${lane_status}" \
      --argjson details "${close_result}" \
      '{ok:false, issue_id:$issue_id, status:$status, error:{message:"compact_lane failed during close_issue", details:$details}}'
    return 0
  fi

  jq -cn \
    --arg issue_id "${issue_id}" \
    --arg from_status "${lane_status}" \
    --arg reason "${reason}" \
    --arg outcome "${outcome}" \
    --arg revision "${revision}" \
    --arg note "${note}" \
    --argjson handoff "$(jq -c '.payload' <<<"${handoff_result}")" \
    --argjson finish "$(jq -c '.payload' <<<"${finish_result}")" \
    --argjson cleanup "${cleanup_result}" \
    --argjson archive "$(jq -c '.payload' <<<"${archive_result}")" \
    --argjson close "$(jq -c '.payload' <<<"${close_result}")" \
    '{
      ok: true,
      payload: {
        issue_id: $issue_id,
        from_status: $from_status,
        reason: $reason,
        outcome: $outcome,
        revision: (if ($revision | length) > 0 then $revision else null end),
        note: (if ($note | length) > 0 then $note else null end),
        handoff: $handoff,
        finish: $finish,
        cleanup: $cleanup,
        archive: $archive,
        close: $close
      }
    }'
}

cmd_compact_lane() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local revision="$4"
  local reason="$5"
  local outcome="${6:-completed}"
  local note="${7:-}"
  local quarantine_requested="${8:-false}"
  local compact_result=""

  compact_result="$(compact_lane_action "${repo_root}" "${socket_path}" "${issue_id}" "${revision}" "${reason}" "${outcome}" "${note}" "${quarantine_requested}")"
  if jq -e '.ok == true' >/dev/null <<<"${compact_result}"; then
    jq -c '.payload' <<<"${compact_result}"
    return 0
  fi

  jq -c '.' <<<"${compact_result}"
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
  local repo_root="$1"
  local socket_path="$2"
  local kind="$3"
  local request_id="$4"
  local payload_json="$5"
  local request_json

  if ! printf '%s' "${payload_json}" | jq -e 'type' >/dev/null 2>&1; then
    fail "query --payload must be valid JSON"
  fi

  case "${kind}" in
    tracker_status|coordinator_status|operator_snapshot|board_status|receipts_status|self_host_status|issue_inspect|ping)
      exec_tuskd_core query --repo "${repo_root}" --socket "${socket_path}" --kind "${kind}" --request-id "${request_id}" --payload "${payload_json}"
      ;;
  esac

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

if [ "${command}" = "core-seam" ]; then
  exec_tuskd_core seam "$@"
fi

repo_arg=""
socket_arg=""
kind_arg=""
request_id_arg=""
issue_id_arg=""
reason_arg=""
base_rev_arg=""
target_rev_arg=""
slug_arg=""
revision_arg=""
outcome_arg=""
note_arg=""
payload_arg="null"
quarantine_arg=false

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
    --base-rev)
      [ $# -ge 2 ] || fail "--base-rev requires a value"
      base_rev_arg="$2"
      shift 2
      ;;
    --target-rev)
      [ $# -ge 2 ] || fail "--target-rev requires a value"
      target_rev_arg="$2"
      shift 2
      ;;
    --slug)
      [ $# -ge 2 ] || fail "--slug requires a value"
      slug_arg="$2"
      shift 2
      ;;
    --revision)
      [ $# -ge 2 ] || fail "--revision requires a value"
      revision_arg="$2"
      shift 2
      ;;
    --outcome)
      [ $# -ge 2 ] || fail "--outcome requires a value"
      outcome_arg="$2"
      shift 2
      ;;
    --note)
      [ $# -ge 2 ] || fail "--note requires a value"
      note_arg="$2"
      shift 2
      ;;
    --quarantine)
      quarantine_arg=true
      shift
      ;;
    --payload)
      [ $# -ge 2 ] || fail "--payload requires a JSON value"
      payload_arg="$2"
      shift 2
      ;;
    --checkout)
      [ $# -ge 2 ] || fail "--checkout requires a value"
      checkout_arg="$2"
      shift 2
      ;;
    --realization)
      [ $# -ge 2 ] || fail "--realization requires a value"
      realization_arg="$2"
      shift 2
      ;;
    --plan)
      plan_arg=true
      shift
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
  coordinator-status)
    cmd_coordinator_status "${repo_root}"
    ;;
  operator-snapshot)
    cmd_operator_snapshot "${repo_root}" "${socket_path}"
    ;;
  board-status)
    cmd_board_status "${repo_root}" "${socket_path}"
    ;;
  receipts-status)
    cmd_receipts_status "${repo_root}" "${socket_path}"
    ;;
  self-host-run)
    cmd_self_host_run "${repo_root}" "${checkout_arg:-}" "${realization_arg:-self.trace-core-health.local}" "${note_arg}" "${plan_arg:-false}"
    ;;
  land-main)
    [ -n "${revision_arg}" ] || fail "land-main requires --revision"
    cmd_land_main "${repo_root}" "${revision_arg}" "${note_arg}" "${plan_arg:-false}"
    ;;
  repair-coordinator)
    cmd_repair_coordinator "${repo_root}" "${target_rev_arg:-main}" "${note_arg}" "${plan_arg:-false}"
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
  launch-lane)
    [ -n "${issue_id_arg}" ] || fail "launch-lane requires --issue-id"
    [ -n "${base_rev_arg}" ] || fail "launch-lane requires --base-rev"
    cmd_launch_lane "${repo_root}" "${socket_path}" "${issue_id_arg}" "${base_rev_arg}" "${slug_arg}"
    ;;
  handoff-lane)
    [ -n "${issue_id_arg}" ] || fail "handoff-lane requires --issue-id"
    [ -n "${revision_arg}" ] || fail "handoff-lane requires --revision"
    cmd_handoff_lane "${repo_root}" "${socket_path}" "${issue_id_arg}" "${revision_arg}" "${note_arg}"
    ;;
  finish-lane)
    [ -n "${issue_id_arg}" ] || fail "finish-lane requires --issue-id"
    [ -n "${outcome_arg}" ] || fail "finish-lane requires --outcome"
    cmd_finish_lane "${repo_root}" "${socket_path}" "${issue_id_arg}" "${outcome_arg}" "${note_arg}"
    ;;
  archive-lane)
    [ -n "${issue_id_arg}" ] || fail "archive-lane requires --issue-id"
    cmd_archive_lane "${repo_root}" "${socket_path}" "${issue_id_arg}" "${note_arg}"
    ;;
  compact-lane)
    [ -n "${issue_id_arg}" ] || fail "compact-lane requires --issue-id"
    [ -n "${reason_arg}" ] || fail "compact-lane requires --reason"
    cmd_compact_lane "${repo_root}" "${socket_path}" "${issue_id_arg}" "${revision_arg}" "${reason_arg}" "${outcome_arg:-completed}" "${note_arg}" "${quarantine_arg}"
    ;;
  serve)
    cmd_serve "${repo_root}" "${socket_path}"
    ;;
  query)
    [ -n "${kind_arg}" ] || fail "query requires --kind"
    cmd_query "${repo_root}" "${socket_path}" "${kind_arg}" "${request_id_arg:-$(now_iso8601)}" "${payload_arg}"
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
