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
  tuskd doctor [--repo PATH] [--json]
  tuskd operator-snapshot [--repo PATH] [--socket PATH]
  tuskd board-status [--repo PATH]
  tuskd sessions-status [--repo PATH]
  tuskd receipts-status [--repo PATH]
  tuskd self-host-run [--repo PATH] [--checkout PATH] [--realization ID] [--note TEXT] [--plan]
  tuskd land-main [--repo PATH] --revision REV [--note TEXT] [--plan]
  tuskd repair-coordinator [--repo PATH] [--target-rev REV] [--note TEXT] [--plan]
  tuskd create-child-issue [--repo PATH] [--socket PATH] --parent-id ISSUE_ID --title TITLE [--description TEXT] [--type TYPE] [--priority PRIORITY] [--labels CSV]
  tuskd claim-issue [--repo PATH] [--socket PATH] --issue-id ISSUE_ID
  tuskd close-issue [--repo PATH] [--socket PATH] --issue-id ISSUE_ID --reason REASON
  tuskd launch-lane [--repo PATH] [--socket PATH] --issue-id ISSUE_ID --base-rev REV [--slug SLUG]
  tuskd dispatch-lane [--repo PATH] [--socket PATH] --issue-id ISSUE_ID [--worker WORKER] [--mode MODE] [--note TEXT] [--plan]
  tuskd autonomous-lane [--repo PATH] [--socket PATH] --issue-id ISSUE_ID [--base-rev REV] [--slug SLUG] [--worker WORKER] [--note TEXT] [--quarantine] [--plan]
  tuskd handoff-lane [--repo PATH] [--socket PATH] --issue-id ISSUE_ID --revision REV [--note TEXT]
  tuskd finish-lane [--repo PATH] [--socket PATH] --issue-id ISSUE_ID --outcome OUTCOME [--note TEXT]
  tuskd lane-park [--repo PATH] --issue-id ISSUE_ID
  tuskd lane-abandon [--repo PATH] --issue-id ISSUE_ID
  tuskd archive-lane [--repo PATH] [--socket PATH] --issue-id ISSUE_ID [--note TEXT]
  tuskd complete-lane [--repo PATH] [--socket PATH] --issue-id ISSUE_ID --reason REASON [--revision REV] [--outcome OUTCOME] [--note TEXT] [--quarantine] [--plan]
  tuskd compact-lane [--repo PATH] [--socket PATH] --issue-id ISSUE_ID --reason REASON [--revision REV] [--outcome OUTCOME] [--note TEXT] [--quarantine] [--force]
  tuskd supervisor-attach [--repo PATH]
  tuskd supervisor-start [--repo PATH]
  tuskd supervisor-stop [--repo PATH] [--force]
  tuskd serve [--repo PATH] [--socket PATH]
  tuskd query [--repo PATH] [--socket PATH] --kind KIND [--request-id ID] [--payload JSON]

Commands:
  core-seam     Print the first Rust-owned backend/service seam contract.
  ensure        Ensure repo-local state exists and tracker health is recorded.
  status        Print the current tracker service projection.
  coordinator-status Print the default-workspace drift projection.
  doctor        Print the read-only tracker preflight invariant report.
  operator-snapshot Print the compact operator-facing home projection.
  board-status  Print the current board projection.
  sessions-status Print the current worker session projection.
  receipts-status Print the current receipt projection.
  self-host-run Execute the first self-host build/check loop and record receipts.
  land-main     Land one revision onto exported main, export Git state, and sync the coordinator checkout.
  repair-coordinator Rebase the default coordinator workspace onto current main and record a receipt.
  create-child-issue Create one governed child issue with tuskd-owned id allocation and verification.
  claim-issue   Claim one issue through the coordinator action surface.
  close-issue   Close one issue through the coordinator action surface.
  launch-lane   Create one dedicated issue workspace through the coordinator action surface.
  dispatch-lane Prepare or execute one bounded worker dispatch through the repo-aware codex adapter.
  autonomous-lane Run the first bounded autonomous lane class through claim, dispatch, verification, and governed closeout.
  handoff-lane  Record a lane handoff with an explicit revision.
  finish-lane   Record a terminal lane outcome without collapsing into issue closure.
  lane-park     Rewrite one lane sentinel from active to parked without removing the workspace.
  lane-abandon  Rewrite one lane sentinel to abandoned so compact-lane may clean the workspace.
  archive-lane  Remove one finished lane from live state once its workspace is gone.
  complete-lane Complete one live lane through handoff, finish, landing, cleanup, archive, and close.
  compact-lane  Compact one live lane through handoff, finish, workspace cleanup, archive, and close. Use --force only for stuck sentinels.
  supervisor-attach  Verify the Dolt supervisor is alive; never start one. Returns ok/pid/port or error with kind=supervisor-down.
  supervisor-start   Idempotent start: ok if already running; else acquires an atomic lock, calls bd dolt start, and verifies. Refuses concurrent starts via the lock.
  supervisor-stop    Stop the Dolt supervisor; --force falls back to SIGTERM if bd dolt stop fails.
  serve         Serve the local JSON protocol over a Unix socket.
  query         Query one tuskd protocol request; read kinds are handled locally, actions still require a live socket.

Protocol request kinds:
  tracker_status
  coordinator_status
  operator_snapshot
  board_status
  sessions_status
  receipts_status
  self_host_status
  create_child_issue
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

require_supervisor_alive() {
  local repo_root="$1"
  local pid_file="${repo_root}/.beads/dolt-server.pid"
  local port_file="${repo_root}/.beads/dolt-server.port"
  local pid=""
  local port=""
  local owner=""

  if [ ! -f "${pid_file}" ] || [ ! -f "${port_file}" ]; then
    fail "supervisor required; run: tuskd supervisor-start (or 'tuskd doctor' for full report)"
  fi

  pid="$(cat "${pid_file}" 2>/dev/null || true)"
  port="$(cat "${port_file}" 2>/dev/null || true)"
  if [ -z "${pid}" ] || [ -z "${port}" ] || ! kill -0 "${pid}" 2>/dev/null; then
    fail "supervisor required; run: tuskd supervisor-start (or 'tuskd doctor' for full report)"
  fi

  owner="$(lsof -nP "-iTCP:${port}" -sTCP:LISTEN -t 2>/dev/null | head -n 1 || true)"
  if [ "${owner}" != "${pid}" ]; then
    fail "supervisor required; recorded pid ${pid} does not own port ${port} (pid reuse or orphan Dolt); run: tuskd supervisor-start"
  fi
}

supervisor_alive_pid() {
  local repo_root="$1"
  local pid_file="${repo_root}/.beads/dolt-server.pid"
  local port_file="${repo_root}/.beads/dolt-server.port"
  local pid=""
  local port=""
  local owner=""

  [ -f "${pid_file}" ] && [ -f "${port_file}" ] || return 1
  pid="$(cat "${pid_file}" 2>/dev/null || true)"
  port="$(cat "${port_file}" 2>/dev/null || true)"
  [ -n "${pid}" ] && [ -n "${port}" ] || return 1
  kill -0 "${pid}" 2>/dev/null || return 1
  owner="$(lsof -nP "-iTCP:${port}" -sTCP:LISTEN -t 2>/dev/null | head -n 1 || true)"
  [ "${owner}" = "${pid}" ] || return 1
  printf '%s\n' "${pid}"
}

supervisor_lock_dir() {
  local repo_root="$1"
  printf '%s/.beads/tuskd/supervisor.start.lock\n' "${repo_root}"
}

acquire_supervisor_lock() {
  local repo_root="$1"
  local lock_dir
  lock_dir="$(supervisor_lock_dir "${repo_root}")"
  mkdir -p "$(dirname "${lock_dir}")"
  if mkdir "${lock_dir}" 2>/dev/null; then
    printf '%s' "$$" > "${lock_dir}/pid"
    return 0
  fi
  return 1
}

release_supervisor_lock() {
  local repo_root="$1"
  local lock_dir
  lock_dir="$(supervisor_lock_dir "${repo_root}")"
  [ -d "${lock_dir}" ] && rm -rf "${lock_dir}" || true
}

cmd_supervisor_attach() {
  local repo_root="$1"
  local pid port
  pid="$(supervisor_alive_pid "${repo_root}" || true)"
  port="$(cat "${repo_root}/.beads/dolt-server.port" 2>/dev/null || true)"
  if [ -z "${pid}" ]; then
    jq -cn --arg repo "${repo_root}" '{ok:false, error:{message:"supervisor not running; run: tuskd supervisor-start", kind:"supervisor-down"}, repo_root:$repo}'
    return 1
  fi
  jq -cn --arg repo "${repo_root}" --arg pid "${pid}" --arg port "${port}" \
    '{ok:true, role:"attach", repo_root:$repo, pid:($pid|tonumber), port:(if $port == "" then null else ($port|tonumber) end)}'
  return 0
}

cmd_supervisor_start() {
  local repo_root="$1"
  local pid port start_output start_exit
  pid="$(supervisor_alive_pid "${repo_root}" || true)"
  if [ -n "${pid}" ]; then
    port="$(cat "${repo_root}/.beads/dolt-server.port" 2>/dev/null || true)"
    jq -cn --arg repo "${repo_root}" --arg pid "${pid}" --arg port "${port}" \
      '{ok:true, role:"start", action:"noop-already-running", repo_root:$repo, pid:($pid|tonumber), port:(if $port == "" then null else ($port|tonumber) end)}'
    return 0
  fi
  if ! acquire_supervisor_lock "${repo_root}"; then
    jq -cn --arg repo "${repo_root}" \
      '{ok:false, error:{message:"another supervisor start is in progress; retry after it completes", kind:"supervisor-start-locked"}, repo_root:$repo}'
    return 1
  fi
  trap 'release_supervisor_lock "'"${repo_root}"'"' EXIT
  pid="$(supervisor_alive_pid "${repo_root}" || true)"
  if [ -n "${pid}" ]; then
    release_supervisor_lock "${repo_root}"
    trap - EXIT
    port="$(cat "${repo_root}/.beads/dolt-server.port" 2>/dev/null || true)"
    jq -cn --arg repo "${repo_root}" --arg pid "${pid}" --arg port "${port}" \
      '{ok:true, role:"start", action:"noop-race-loser", repo_root:$repo, pid:($pid|tonumber), port:(if $port == "" then null else ($port|tonumber) end)}'
    return 0
  fi
  if start_output="$(bd dolt start 2>&1)"; then
    start_exit=0
  else
    start_exit=$?
  fi
  release_supervisor_lock "${repo_root}"
  trap - EXIT
  if [ "${start_exit}" -ne 0 ]; then
    jq -cn --arg repo "${repo_root}" --arg output "${start_output}" --argjson exit "${start_exit}" \
      '{ok:false, error:{message:"bd dolt start failed", kind:"supervisor-start-failed", output:$output, exit_code:$exit}, repo_root:$repo}'
    return 1
  fi
  pid="$(supervisor_alive_pid "${repo_root}" || true)"
  port="$(cat "${repo_root}/.beads/dolt-server.port" 2>/dev/null || true)"
  if [ -z "${pid}" ]; then
    jq -cn --arg repo "${repo_root}" --arg output "${start_output}" \
      '{ok:false, error:{message:"bd dolt start reported success but no live pid was recorded", kind:"supervisor-start-unverified", output:$output}, repo_root:$repo}'
    return 1
  fi
  jq -cn --arg repo "${repo_root}" --arg pid "${pid}" --arg port "${port}" --arg output "${start_output}" \
    '{ok:true, role:"start", action:"started", repo_root:$repo, pid:($pid|tonumber), port:(if $port == "" then null else ($port|tonumber) end), output:$output}'
  return 0
}

cmd_supervisor_stop() {
  local repo_root="$1"
  local force_flag="${2:-false}"
  local pid stop_output stop_exit
  pid="$(supervisor_alive_pid "${repo_root}" || true)"
  if [ -z "${pid}" ]; then
    jq -cn --arg repo "${repo_root}" \
      '{ok:true, role:"stop", action:"noop-already-stopped", repo_root:$repo}'
    return 0
  fi
  if stop_output="$(bd dolt stop 2>&1)"; then
    stop_exit=0
  else
    stop_exit=$?
  fi
  if [ "${stop_exit}" -ne 0 ] && [ "${force_flag}" = "true" ]; then
    if kill "${pid}" 2>/dev/null; then
      stop_exit=0
      stop_output="${stop_output}"$'\n'"force-killed pid ${pid}"
    fi
  fi
  if [ "${stop_exit}" -ne 0 ]; then
    jq -cn --arg repo "${repo_root}" --arg output "${stop_output}" --argjson exit "${stop_exit}" --arg pid "${pid}" \
      '{ok:false, error:{message:"bd dolt stop failed; pass --force to SIGTERM the pid directly", kind:"supervisor-stop-failed", output:$output, exit_code:$exit, pid:($pid|tonumber)}, repo_root:$repo}'
    return 1
  fi
  jq -cn --arg repo "${repo_root}" --arg pid "${pid}" --arg output "${stop_output}" \
    '{ok:true, role:"stop", action:"stopped", repo_root:$repo, pid:($pid|tonumber), output:$output}'
  return 0
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
    "create_child_issue requires parent_id")
      printf 'retry with the parent issue id: tuskd %s --repo <repo> --parent-id <issue> --title <title>' "${command_name}"
      ;;
    "create_child_issue requires title")
      printf 'retry with a title: tuskd %s --repo <repo> --parent-id <issue> --title <title>' "${command_name}"
      ;;
    "create_child_issue requires an existing parent issue")
      printf 'choose an existing parent issue id before retrying create-child-issue'
      ;;
    "create_child_issue requires a non-closed parent issue")
      printf 'choose an open parent issue before retrying create-child-issue'
      ;;
    "create_child_issue could not allocate a child issue id")
      printf 're-read the parent issue and retry once; if it repeats, inspect concurrent tracker writers'
      ;;
    "create_child_issue detected issue identity mismatch after create")
      printf 'stop and inspect the returned issue id and tracker row before launching a lane from it'
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
    "dispatch_lane requires an existing lane record")
      printf 'launch a lane for %s before dispatching it' "${issue_id:-<issue>}"
      ;;
    "dispatch_lane requires a launched lane")
      printf 'dispatch is only admitted before handoff or finish; pick a launched lane for %s' "${issue_id:-<issue>}"
      ;;
    "dispatch_lane requires a live workspace")
      if [ -n "${workspace_path}" ]; then
        printf 'restore or relaunch %s before dispatching the worker' "${workspace_path}"
      else
        printf 'restore or relaunch the lane workspace before dispatching the worker'
      fi
      ;;
    "dispatch_lane worker timed out")
      if [ -n "${workspace_path}" ]; then
        printf 'inspect %s for dirty files or a visible revision, then retry dispatch-lane or finish the lane manually' "${workspace_path}"
      else
        printf 'inspect the live lane workspace for dirty files or a visible revision before retrying dispatch-lane'
      fi
      ;;
    "autonomous_lane requires an open issue")
      printf 'pick an open autonomy:v1-safe task issue before retrying autonomous-lane'
      ;;
    "autonomous_lane requires no existing live lane")
      printf 'finish, inspect, or archive the existing live lane before retrying autonomous-lane'
      ;;
    "autonomous_lane only admits autonomy:v1-safe place:tusk task issues")
      printf 'label the issue autonomy:v1-safe and keep it as a place:tusk task before using autonomous-lane'
      ;;
    "autonomous_lane requires explicit verification commands")
      printf 'add a Verification section with runnable commands before retrying autonomous-lane'
      ;;
    "autonomous_lane requires a clean visible revision from the worker lane")
      printf 'inspect the lane workspace, cut one visible jj commit, and keep the working copy clean before retrying closeout'
      ;;
    "dispatch_lane only admits place:tusk task issues")
      printf 'use the v1 autonomous dispatch class only for task issues labeled place:tusk'
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

dispatch_state_root() {
  local repo_root="$1"
  printf '%s/dispatch\n' "$(state_root "${repo_root}")"
}

dispatch_prompt_path() {
  local repo_root="$1"
  local issue_id="$2"
  printf '%s/%s.prompt.md\n' "$(dispatch_state_root "${repo_root}")" "${issue_id}"
}

dispatch_brief_path() {
  local repo_root="$1"
  local issue_id="$2"
  printf '%s/%s.brief.json\n' "$(dispatch_state_root "${repo_root}")" "${issue_id}"
}

dispatch_last_message_path() {
  local workspace_path="$1"
  printf '%s/.codex-last.txt\n' "${workspace_path}"
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

lane_sentinel_path() {
  local workspace_path="$1"
  printf '%s/.tusk-lane\n' "${workspace_path%/}"
}

file_mtime_epoch() {
  local path="$1"
  local mtime=""

  if mtime="$(stat -f '%m' "${path}" 2>/dev/null)"; then
    printf '%s\n' "${mtime}"
    return 0
  fi
  if mtime="$(stat -c '%Y' "${path}" 2>/dev/null)"; then
    printf '%s\n' "${mtime}"
    return 0
  fi

  return 1
}

lane_sentinel_is_recent() {
  local sentinel_path="$1"
  local mtime_epoch=""
  local now_epoch=""

  mtime_epoch="$(file_mtime_epoch "${sentinel_path}")" || return 1
  now_epoch="$(date -u +%s)"
  [ $((now_epoch - mtime_epoch)) -le 86400 ]
}

# .tusk-lane schema v1 is a single JSON object with:
# version, issue_id, workspace_name, state, claimed_at, coordinator_pid,
# coordinator_host, and base_rev. It is written with two-space indent so
# operators can inspect the lifecycle state directly in the workspace.
write_lane_sentinel() {
  local issue_id="$1"
  local workspace_name="$2"
  local workspace_path="$3"
  local state="$4"
  local base_rev="$5"
  local sentinel_path=""
  local tmp_path=""
  local coordinator_host=""

  sentinel_path="$(lane_sentinel_path "${workspace_path}")"
  coordinator_host="$(hostname 2>/dev/null || printf 'unknown-host')"
  tmp_path="$(mktemp "${sentinel_path}.tmp.XXXXXX")" || return 1

  if ! jq -n \
    --arg issue_id "${issue_id}" \
    --arg workspace_name "${workspace_name}" \
    --arg state "${state}" \
    --arg claimed_at "$(now_iso8601)" \
    --argjson coordinator_pid "$$" \
    --arg coordinator_host "${coordinator_host}" \
    --arg base_rev "${base_rev}" \
    '{
      version: 1,
      issue_id: $issue_id,
      workspace_name: $workspace_name,
      state: $state,
      claimed_at: $claimed_at,
      coordinator_pid: $coordinator_pid,
      coordinator_host: $coordinator_host,
      base_rev: $base_rev
    }' >"${tmp_path}"; then
    rm -f -- "${tmp_path}"
    return 1
  fi

  if ! mv -- "${tmp_path}" "${sentinel_path}"; then
    rm -f -- "${tmp_path}"
    return 1
  fi
}

compact_lane_sentinel_guard() {
  local issue_id="$1"
  local workspace_path="$2"
  local force_requested="${3:-false}"
  local sentinel_path=""
  local sentinel_json=""
  local sentinel_state=""
  local coordinator_pid=""
  local coordinator_pid_live=false
  local sentinel_recent=false
  local message=""

  if [ -z "${workspace_path}" ]; then
    jq -cn '{ok:true, sentinel:null}'
    return 0
  fi

  sentinel_path="$(lane_sentinel_path "${workspace_path}")"
  if [ ! -f "${sentinel_path}" ]; then
    jq -cn --arg sentinel_path "${sentinel_path}" '{ok:true, sentinel:{present:false, path:$sentinel_path}}'
    return 0
  fi

  if ! sentinel_json="$(jq -c '.' "${sentinel_path}" 2>/dev/null)"; then
    if [ "${force_requested}" = true ]; then
      jq -cn --arg sentinel_path "${sentinel_path}" '{ok:true, forced:true, sentinel:{present:true, valid:false, path:$sentinel_path}}'
      return 0
    fi
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg sentinel_path "${sentinel_path}" \
      '{
        ok: false,
        issue_id: $issue_id,
        error: {
          message: ("compact_lane refuses: invalid lane sentinel at " + $sentinel_path + "; run '\''tuskd lane-abandon " + $issue_id + "'\'' or pass --force")
        },
        sentinel: {
          present: true,
          valid: false,
          path: $sentinel_path
        }
      }'
    return 0
  fi

  sentinel_state="$(jq -r '.state // ""' <<<"${sentinel_json}")"
  coordinator_pid="$(jq -r '.coordinator_pid // ""' <<<"${sentinel_json}")"
  if is_live_pid "${coordinator_pid}"; then
    coordinator_pid_live=true
  fi
  if lane_sentinel_is_recent "${sentinel_path}"; then
    sentinel_recent=true
  fi

  case "${sentinel_state}" in
    abandoned)
      jq -cn --argjson sentinel "${sentinel_json}" '{ok:true, sentinel:$sentinel}'
      return 0
      ;;
    active|parked)
      if [ "${force_requested}" = true ]; then
        jq -cn \
          --argjson sentinel "${sentinel_json}" \
          --argjson coordinator_pid_live "$(json_bool "${coordinator_pid_live}")" \
          --argjson sentinel_recent "$(json_bool "${sentinel_recent}")" \
          '{ok:true, forced:true, sentinel:$sentinel, coordinator_pid_live:$coordinator_pid_live, sentinel_recent:$sentinel_recent}'
        return 0
      fi

      if [ "${coordinator_pid_live}" = true ] || [ "${sentinel_recent}" = true ]; then
        message="compact_lane refuses: ${sentinel_state} lane sentinel at ${sentinel_path}; run 'tuskd lane-abandon ${issue_id}' or pass --force"
      else
        message="compact_lane refuses: stale ${sentinel_state} lane sentinel at ${sentinel_path}; run 'tuskd lane-abandon ${issue_id}' or pass --force"
      fi

      jq -cn \
        --arg issue_id "${issue_id}" \
        --arg message "${message}" \
        --arg sentinel_path "${sentinel_path}" \
        --argjson sentinel "${sentinel_json}" \
        --argjson coordinator_pid_live "$(json_bool "${coordinator_pid_live}")" \
        --argjson sentinel_recent "$(json_bool "${sentinel_recent}")" \
        '{
          ok: false,
          issue_id: $issue_id,
          error: {
            message: $message
          },
          sentinel: $sentinel,
          sentinel_path: $sentinel_path,
          coordinator_pid_live: $coordinator_pid_live,
          sentinel_recent: $sentinel_recent,
          stale: ((not $coordinator_pid_live) and (not $sentinel_recent))
        }'
      return 0
      ;;
    *)
      if [ "${force_requested}" = true ]; then
        jq -cn --argjson sentinel "${sentinel_json}" '{ok:true, forced:true, sentinel:$sentinel}'
        return 0
      fi
      jq -cn \
        --arg issue_id "${issue_id}" \
        --arg sentinel_path "${sentinel_path}" \
        --arg state "${sentinel_state}" \
        --argjson sentinel "${sentinel_json}" \
        '{
          ok: false,
          issue_id: $issue_id,
          error: {
            message: ("compact_lane refuses: unknown lane sentinel state " + ($state | @json) + " at " + $sentinel_path + "; run '\''tuskd lane-abandon " + $issue_id + "'\'' or pass --force")
          },
          sentinel: $sentinel,
          sentinel_path: $sentinel_path
        }'
      return 0
      ;;
  esac
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

merge_backend_observation() {
  local runtime_json="$1"
  local show_output_json="${2:-null}"

  jq -cn \
    --argjson runtime "${runtime_json}" \
    --argjson show "${show_output_json}" \
    '
      def valid_port($value):
        ($value | type) == "number" and $value >= 1 and $value <= 65535;

      if ($show | type) != "object" then
        $runtime
      else
        ($runtime + $show) as $merged
        | if (($show.connection_ok // false) | not) or (valid_port($merged.port) | not) then
            $merged
            | .port = ($runtime.port // null)
            | .pid = ($runtime.pid // null)
            | .running = ($runtime.running // false)
            | .host = ($runtime.host // null)
            | .data_dir = ($runtime.data_dir // null)
          else
            $merged
            | if ((.host // "") | tostring | length) == 0 then .host = ($runtime.host // null) else . end
            | if ((.data_dir // "") | tostring | length) == 0 then .data_dir = ($runtime.data_dir // null) else . end
          end
      end'
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
  mkdir -p "$(dispatch_state_root "${repo_root}")"

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

run_in_checkout_capture() {
  local checkout_root="$1"
  local tracker_root="$2"
  shift 2

  (
    cd "${checkout_root}"
    tusk_export_runtime_roots "${checkout_root}" "${tracker_root}"
    "$@" 2>&1
  )
}

run_shell_command_in_checkout() {
  local checkout_root="$1"
  local tracker_root="$2"
  local name="$3"
  local command="$4"
  local output=""
  local exit_code=0

  if output="$(run_in_checkout_capture "${checkout_root}" "${tracker_root}" sh -lc "${command}")"; then
    exit_code=0
  else
    exit_code=$?
  fi

  render_command_result "${name}" "${exit_code}" "${output}"
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
  if jq -e '.ok and ((.output | type) == "object")' >/dev/null <<<"${dolt_show_result}"; then
    backend_json="$(merge_backend_observation "${runtime_json}" "$(jq -c '.output' <<<"${dolt_show_result}")")"
  else
    backend_json="${runtime_json}"
  fi

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

issue_has_label() {
  local issue_json="$1"
  local label="$2"

  jq -e --arg label "${label}" '
    (.labels // []) | index($label) != null
  ' >/dev/null <<<"${issue_json}"
}

issue_verification_lines() {
  local description="$1"
  local lines=""

  lines="$(
    printf '%s\n' "${description}" | awk '
      BEGIN { capture = 0 }
      capture && /^[[:alpha:]][^:]*:$/ { exit }
      capture && NF { print }
      $0 == "Verification:" { capture = 1 }
    '
  )"

  if [ -n "${lines}" ]; then
    printf '%s\n' "${lines}" | jq -Rsc 'split("\n") | map(select(length > 0))'
  else
    printf '[]\n'
  fi
}

issue_verification_commands_json() {
  local description="$1"

  jq -c '
    map(
      gsub("^[[:space:]]*[-*][[:space:]]+"; "")
      | sub("^`"; "")
      | sub("`$"; "")
      | select(length > 0)
    )
  ' <<<"$(issue_verification_lines "${description}")"
}

dispatch_policy_class_id() {
  printf 'tusk.low-risk.v1\n'
}

autonomous_policy_class_id() {
  printf 'tusk.autonomous.v1\n'
}

dispatch_worker_launcher() {
  printf '%s\n' "${TUSKD_CODEX_LAUNCHER:-${TUSK_CODEX_LAUNCHER:-tusk-codex}}"
}

dispatch_timeout_seconds() {
  printf '%s\n' "${TUSKD_DISPATCH_TIMEOUT_SECONDS:-300}"
}

dispatch_kill_after_seconds() {
  printf '%s\n' "${TUSKD_DISPATCH_KILL_AFTER_SECONDS:-10}"
}

dispatch_command_args_json() {
  local launcher="$1"
  local workspace_path="$2"
  local repo_root="$3"
  local output_path="$4"

  jq -cn \
    --arg launcher "${launcher}" \
    --arg workspace_path "${workspace_path}" \
    --arg repo_root "${repo_root}" \
    --arg output_path "${output_path}" \
    '[
      $launcher,
      "--checkout", $workspace_path,
      "--tracker-root", $repo_root,
      "--",
      "exec",
      "--full-auto",
      "--add-dir", $repo_root,
      "--output-last-message", $output_path,
      "-"
    ]'
}

dispatch_command_string() {
  local args_json="$1"
  local prompt_path="$2"

  jq -r --arg prompt_path "${prompt_path}" '
    (map(@sh) | join(" ")) + " < " + ($prompt_path | @sh)
  ' <<<"${args_json}"
}

build_dispatch_brief() {
  local repo_root="$1"
  local issue_json="$2"
  local lane_json="$3"
  local worker="$4"
  local mode="$5"
  local note="${6:-}"
  local prompt_path="$7"
  local brief_path="$8"
  local output_path="$9"
  local launcher="${10}"
  local verification_json=""
  local command_args_json=""
  local command_string=""

  verification_json="$(issue_verification_lines "$(jq -r '.description // ""' <<<"${issue_json}")")"
  command_args_json="$(dispatch_command_args_json "${launcher}" "$(jq -r '.workspace_path // ""' <<<"${lane_json}")" "${repo_root}" "${output_path}")"
  command_string="$(dispatch_command_string "${command_args_json}" "${prompt_path}")"

  jq -cn \
    --arg repo_root "${repo_root}" \
    --arg class_id "$(dispatch_policy_class_id)" \
    --arg worker "${worker}" \
    --arg mode "${mode}" \
    --arg note "${note}" \
    --arg prompt_path "${prompt_path}" \
    --arg brief_path "${brief_path}" \
    --arg output_path "${output_path}" \
    --arg launcher "${launcher}" \
    --argjson issue "${issue_json}" \
    --argjson lane "${lane_json}" \
    --argjson verification "${verification_json}" \
    --argjson command_args "${command_args_json}" \
    --arg command_string "${command_string}" \
    '{
      class_id: $class_id,
      repo_root: $repo_root,
      worker: $worker,
      mode: $mode,
      note: (if $note == "" then null else $note end),
      tracker_mutations_in_scope: false,
      landing_owner: "coordinator",
      landing_target: "main",
      runner: {
        kind: "codex",
        launcher: $launcher,
        command_args: $command_args,
        command: $command_string
      },
      issue: {
        id: ($issue.id // null),
        title: ($issue.title // null),
        description: ($issue.description // null),
        status: ($issue.status // null),
        issue_type: ($issue.issue_type // null),
        labels: ($issue.labels // [])
      },
      lane: {
        issue_id: ($lane.issue_id // null),
        workspace_name: ($lane.workspace_name // null),
        workspace_path: ($lane.workspace_path // null),
        base_rev: ($lane.base_rev // null),
        base_commit: ($lane.base_commit // null),
        status: ($lane.status // null)
      },
      prompt: {
        path: $prompt_path,
        brief_path: $brief_path,
        output_path: $output_path
      },
      verification: $verification
    }'
}

render_dispatch_prompt() {
  local brief_json="$1"

  jq -r '
    def bullets($items):
      if ($items | length) == 0 then
        "- Use the issue Verification section when present and run targeted checks for changed surfaces."
      else
        ($items | map("- " + .) | join("\n"))
      end;

    [
      "Complete issue \(.issue.id) in this workspace.",
      "",
      "Identity",
      "- Active checkout root: \(.lane.workspace_path)",
      "- Workspace path: \(.lane.workspace_path)",
      "- Workspace name: \(.lane.workspace_name)",
      "- Only active issue for this lane: \(.issue.id)",
      "- Base revision: \(.lane.base_rev)",
      "",
      "Tracker",
      "- Canonical tracker root: \(.repo_root)",
      "- Tracker preflight: ready",
      "- Shared backend owner: coordinator",
      "- Tracker mutations in scope: no",
      "",
      "Environment",
      "- Enter runtime with: nix develop --no-pure-eval path:.",
      "- Shared supervisor: coordinator-owned repo-local tuskd/backend state",
      "- Assumed tools: bd, jj, tuskd, nix, codex",
      "- Runtime changes in scope: no",
      "",
      "Publish and landing",
      "- Publish in scope: no",
      "- Landing owner: \(.landing_owner)",
      "- Landing target: \(.landing_target)",
      "- Rewrite after publish allowed: no",
      "",
      "Objective",
      "- Goal: \(.issue.title)",
      "- Done when: leave the lane with a visible commit ready for governed closeout.",
      "- Non-goals: do not widen scope beyond the tracked issue description or change the runtime contract.",
      "- Primary files or areas: derive from the issue description and the smallest affected surface.",
      "",
      "Issue Source",
      (.issue.description // ""),
      "",
      "Operational rules",
      "- Run bd only from the canonical tracker root.",
      "- Do not initialize another tracker in the workspace.",
      "- Do not close, land, or compact the lane; the coordinator owns tuskd complete-lane.",
      "- Keep retries bounded. If the worker runtime is unhealthy, report the exact command and failure.",
      "",
      "Verification",
      bullets(.verification),
      "",
      "Stop conditions",
      "- tracker backend unhealthy",
      "- ambiguous scope or conflicting repo state",
      "- verification fails in a way you cannot repair safely",
      "",
      "Output contract",
      "- State whether the goal was completed.",
      "- List the material file changes.",
      "- Report verification results command by command.",
      "- Report whether the lane is ready for coordinator closeout or remains blocked.",
      "",
      "Dispatch metadata",
      "- Policy class: \(.class_id)",
      "- Worker: \(.worker)",
      "- Mode: \(.mode)",
      "- Prompt path: \(.prompt.path)",
      "- Output path: \(.prompt.output_path)"
    ] | join("\n")
  ' <<<"${brief_json}"
}

write_dispatch_artifacts() {
  local repo_root="$1"
  local issue_id="$2"
  local brief_json="$3"
  local prompt_path
  local brief_path
  local prompt_text

  ensure_state_files "${repo_root}"
  prompt_path="$(dispatch_prompt_path "${repo_root}" "${issue_id}")"
  brief_path="$(dispatch_brief_path "${repo_root}" "${issue_id}")"
  prompt_text="$(render_dispatch_prompt "${brief_json}")"

  printf '%s\n' "${brief_json}" >"${brief_path}"
  printf '%s\n' "${prompt_text}" >"${prompt_path}"
}

dispatch_output_path_probe() {
  local output_path="$1"
  local exists=false
  local size_bytes=0

  if [ -f "${output_path}" ]; then
    exists=true
    size_bytes="$(wc -c < "${output_path}" | tr -d '[:space:]')"
    if [ -z "${size_bytes}" ]; then
      size_bytes=0
    fi
  fi

  jq -cn \
    --arg path "${output_path}" \
    --argjson exists "$(json_bool "${exists}")" \
    --argjson size_bytes "${size_bytes}" \
    '{
      path: $path,
      exists: $exists,
      size_bytes: $size_bytes
    }'
}

dispatch_workspace_probe() {
  local workspace_path="$1"
  local tracker_root="$2"
  local base_commit="$3"
  local parent_output=""
  local parent_exit=0
  local parent_commit=""
  local diff_output=""
  local diff_exit=0
  local working_copy_clean=false
  local visible_revision=false

  if parent_output="$(run_in_checkout_capture "${workspace_path}" "${tracker_root}" jj --repository "${workspace_path}" log -r '@-' --no-graph -T 'commit_id ++ "\n"')"; then
    parent_exit=0
  else
    parent_exit=$?
  fi
  parent_commit="$(printf '%s' "${parent_output}" | awk 'NF { print; exit }')"

  if diff_output="$(run_in_checkout_capture "${workspace_path}" "${tracker_root}" jj --repository "${workspace_path}" diff --summary -r @)"; then
    diff_exit=0
  else
    diff_exit=$?
  fi

  if [ "${diff_exit}" -eq 0 ] && [ -z "${diff_output}" ]; then
    working_copy_clean=true
  fi
  if [ "${parent_exit}" -eq 0 ] && [ -n "${parent_commit}" ] && [ -n "${base_commit}" ] && [ "${parent_commit}" != "${base_commit}" ]; then
    visible_revision=true
  fi

  jq -cn \
    --arg workspace_path "${workspace_path}" \
    --arg base_commit "${base_commit}" \
    --arg parent_commit "${parent_commit}" \
    --arg parent_output "${parent_output}" \
    --arg diff_output "${diff_output}" \
    --argjson parent_exit "${parent_exit}" \
    --argjson diff_exit "${diff_exit}" \
    --argjson working_copy_clean "$(json_bool "${working_copy_clean}")" \
    --argjson visible_revision "$(json_bool "${visible_revision}")" \
    '{
      workspace_path: $workspace_path,
      base_commit: (if ($base_commit | length) > 0 then $base_commit else null end),
      parent_commit: (if ($parent_commit | length) > 0 then $parent_commit else null end),
      visible_revision: $visible_revision,
      working_copy_clean: $working_copy_clean,
      parent_lookup: {
        exit_code: $parent_exit,
        output_text: (if ($parent_output | length) > 0 then $parent_output else null end)
      },
      diff_summary: {
        exit_code: $diff_exit,
        output_text: (if ($diff_output | length) > 0 then $diff_output else null end)
      }
    }'
}

run_dispatch_worker() {
  local launcher="$1"
  local workspace_path="$2"
  local repo_root="$3"
  local prompt_path="$4"
  local output_path="$5"
  local base_commit="${6:-}"
  local output=""
  local exit_code=0
  local timeout_seconds=0
  local kill_after_seconds=0
  local timed_out=false
  local classification="completed"
  local output_probe="null"
  local workspace_probe="null"

  mkdir -p "$(dirname "${output_path}")"
  rm -f -- "${output_path}" "${output_path}.prompt"
  timeout_seconds="$(dispatch_timeout_seconds)"
  kill_after_seconds="$(dispatch_kill_after_seconds)"

  set +e
  output="$(
    cd "${repo_root}"
    tusk_export_runtime_roots "${workspace_path}" "${repo_root}"
    timeout --foreground --signal=TERM --kill-after="${kill_after_seconds}s" "${timeout_seconds}s" \
      "${launcher}" \
      --checkout "${workspace_path}" \
      --tracker-root "${repo_root}" \
      -- \
      exec \
      --full-auto \
      --add-dir "${repo_root}" \
      --output-last-message "${output_path}" \
      - < "${prompt_path}" 2>&1
  )"
  exit_code=$?
  set -e

  case "${exit_code}" in
    0)
      classification="completed"
      ;;
    124|137)
      timed_out=true
      classification="timed_out"
      ;;
    126|127)
      classification="launcher_failure"
      ;;
    *)
      classification="worker_failure"
      ;;
  esac

  output_probe="$(dispatch_output_path_probe "${output_path}")"
  workspace_probe="$(dispatch_workspace_probe "${workspace_path}" "${repo_root}" "${base_commit}")"

  jq -cn \
    --argjson exit_code "${exit_code}" \
    --arg output "${output}" \
    --arg classification "${classification}" \
    --argjson timed_out "$(json_bool "${timed_out}")" \
    --argjson timeout_seconds "${timeout_seconds}" \
    --argjson kill_after_seconds "${kill_after_seconds}" \
    --argjson output_path "${output_probe}" \
    --argjson workspace_probe "${workspace_probe}" \
    '{
      exit_code: $exit_code,
      ok: ($exit_code == 0),
      timed_out: $timed_out,
      classification: $classification,
      timeout_seconds: $timeout_seconds,
      kill_after_seconds: $kill_after_seconds,
      output_path: $output_path,
      workspace_probe: $workspace_probe,
      output: (if ($output | length) > 0 then $output else null end)
    }'
}

autonomous_issue_is_admitted() {
  local issue_json="$1"

  if [ "$(jq -r '.issue_type // ""' <<<"${issue_json}")" != "task" ]; then
    return 1
  fi

  issue_has_label "${issue_json}" "place:tusk" &&
    issue_has_label "${issue_json}" "autonomy:v1-safe"
}

resolve_autonomous_handoff_revision() {
  local workspace_path="$1"
  local tracker_root="$2"
  local base_commit="$3"
  local parent_output=""
  local parent_exit=0
  local parent_commit=""
  local diff_output=""
  local diff_exit=0
  local working_copy_clean=false
  local ok_json=false

  if parent_output="$(run_in_checkout_capture "${workspace_path}" "${tracker_root}" jj --repository "${workspace_path}" log -r '@-' --no-graph -T 'commit_id ++ "\n"')"; then
    parent_exit=0
  else
    parent_exit=$?
  fi
  parent_commit="$(printf '%s' "${parent_output}" | awk 'NF { print; exit }')"

  if diff_output="$(run_in_checkout_capture "${workspace_path}" "${tracker_root}" jj --repository "${workspace_path}" diff --summary -r @)"; then
    diff_exit=0
  else
    diff_exit=$?
  fi

  if [ "${diff_exit}" -eq 0 ] && [ -z "${diff_output}" ]; then
    working_copy_clean=true
  fi
  if [ "${parent_exit}" -eq 0 ] && [ -n "${parent_commit}" ] && [ "${parent_commit}" != "${base_commit}" ] && [ "${working_copy_clean}" = "true" ]; then
    ok_json=true
  fi

  jq -cn \
    --arg workspace_path "${workspace_path}" \
    --arg base_commit "${base_commit}" \
    --arg parent_commit "${parent_commit}" \
    --arg parent_output "${parent_output}" \
    --arg diff_output "${diff_output}" \
    --argjson parent_exit "${parent_exit}" \
    --argjson diff_exit "${diff_exit}" \
    --argjson working_copy_clean "$(json_bool "${working_copy_clean}")" \
    --argjson ok "$(json_bool "${ok_json}")" \
    '{
      ok: $ok,
      workspace_path: $workspace_path,
      base_commit: (if ($base_commit | length) > 0 then $base_commit else null end),
      resolved_revision: (if ($parent_commit | length) > 0 then $parent_commit else null end),
      working_copy_clean: $working_copy_clean,
      parent_lookup: {
        exit_code: $parent_exit,
        output_text: (if ($parent_output | length) > 0 then $parent_output else null end)
      },
      diff_summary: {
        exit_code: $diff_exit,
        output_text: (if ($diff_output | length) > 0 then $diff_output else null end)
      }
    }'
}

run_issue_verification_in_checkout() {
  local checkout_root="$1"
  local tracker_root="$2"
  local commands_json="$3"
  local results="[]"
  local index=0
  local command=""
  local result=""
  local ok_json=true
  local failed_command=""
  local command_count=0

  command_count="$(jq 'length' <<<"${commands_json}")"
  while IFS= read -r command; do
    [ -n "${command}" ] || continue
    index=$((index + 1))
    result="$(run_shell_command_in_checkout "${checkout_root}" "${tracker_root}" "verification_${index}" "${command}")"
    result="$(jq -c --arg command "${command}" '. + {command:$command}' <<<"${result}")"
    results="$(jq -c --argjson result "${result}" '. + [$result]' <<<"${results}")"
    if ! jq -e '.ok == true' >/dev/null <<<"${result}"; then
      ok_json=false
      failed_command="${command}"
      break
    fi
  done < <(jq -r '.[]' <<<"${commands_json}")

  jq -cn \
    --arg checkout_root "${checkout_root}" \
    --arg tracker_root "${tracker_root}" \
    --arg failed_command "${failed_command}" \
    --argjson ok "$(json_bool "${ok_json}")" \
    --argjson command_count "${command_count}" \
    --argjson results "${results}" \
    '{
      ok: $ok,
      checkout_root: $checkout_root,
      tracker_root: $tracker_root,
      command_count: $command_count,
      failed_command: (if ($failed_command | length) > 0 then $failed_command else null end),
      results: $results
    }'
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

commit_descends_from() {
  local repo_root="$1"
  local descendant_commit="$2"
  local ancestor_commit="$3"
  local lookup_output=""
  local lookup_exit=0
  local resolved=""

  [ -n "${descendant_commit}" ] || return 1
  [ -n "${ancestor_commit}" ] || return 1

  if lookup_output="$(run_in_repo_capture "${repo_root}" jj --repository "${repo_root}" log -r "${ancestor_commit}::${descendant_commit} & ${descendant_commit}" --no-graph -T 'commit_id ++ "\n"')"; then
    lookup_exit=0
  else
    lookup_exit=$?
  fi

  resolved="$(printf '%s' "${lookup_output}" | awk 'NF { print; exit }')"
  [ "${lookup_exit}" -eq 0 ] && [ -n "${resolved}" ]
}

duplicate_revision_onto_main() {
  local repo_root="$1"
  local revision="$2"
  local duplicate_output=""
  local duplicate_exit=0
  local duplicate_change_id=""
  local duplicate_lookup='{"ok":false,"commit":null}'
  local duplicate_commit=""

  if duplicate_output="$(run_in_repo_capture "${repo_root}" jj --ignore-working-copy duplicate "${revision}" -o main)"; then
    duplicate_exit=0
  else
    duplicate_exit=$?
  fi

  duplicate_change_id="$(
    awk '
      /^Duplicated / {
        for (i = 1; i <= NF; i++) {
          if ($i == "as" && (i + 1) <= NF) {
            print $(i + 1)
            exit
          }
        }
      }
    ' <<<"${duplicate_output}"
  )"

  if [ "${duplicate_exit}" -eq 0 ] && [ -n "${duplicate_change_id}" ]; then
    duplicate_lookup="$(resolve_revision_commit "${repo_root}" "${duplicate_change_id}")"
  fi
  duplicate_commit="$(jq -r '.commit // ""' <<<"${duplicate_lookup}")"

  jq -cn \
    --arg revision "${revision}" \
    --arg output "${duplicate_output}" \
    --arg change_id "${duplicate_change_id}" \
    --arg commit "${duplicate_commit}" \
    --argjson lookup "${duplicate_lookup}" \
    --argjson ok "$([ "${duplicate_exit}" -eq 0 ] && [ -n "${duplicate_change_id}" ] && [ -n "${duplicate_commit}" ] && echo true || echo false)" \
    '{
      ok: $ok,
      revision: $revision,
      output: (if ($output | length) > 0 then $output else null end),
      change_id: (if ($change_id | length) > 0 then $change_id else null end),
      commit: (if ($commit | length) > 0 then $commit else null end),
      lookup: $lookup
    }'
}

resolve_issue_id_for_handoff_revision() {
  local repo_root="$1"
  local revision="$2"
  local path

  path="$(receipts_path "${repo_root}")"
  if [ ! -f "${path}" ]; then
    printf '{"issue_ids":[],"issue_id":null}\n'
    return
  fi

  jq -Rsc \
    --arg revision "${revision}" \
    '
      split("\n")
      | map(select(length > 0) | fromjson?)
      | map(
          select(.kind == "lane.handoff")
          | select((.payload.revision // "") == $revision)
          | (.payload.issue_id // empty)
        )
      | unique as $issue_ids
      | {
          issue_ids: $issue_ids,
          issue_id: (if ($issue_ids | length) == 1 then $issue_ids[0] else null end)
        }
    ' <"${path}"
}

append_landed_revision_issue_note() {
  local repo_root="$1"
  local source_commit="$2"
  local target_commit="$3"
  local main_before_commit="$4"
  local landing_mode="$5"
  local issue_resolution='{"issue_ids":[],"issue_id":null}'
  local issue_id=""
  local note_text=""
  local issue_show='{"ok":false,"output":[]}'
  local existing_notes=""
  local update_result='{"ok":false,"output":[]}'
  local updated_issue="null"
  local receipt_payload=""
  local receipt_json=""

  if [ -z "${source_commit}" ] || [ -z "${target_commit}" ] || [ "${source_commit}" = "${target_commit}" ]; then
    jq -cn '{status:"not_needed"}'
    return
  fi

  issue_resolution="$(resolve_issue_id_for_handoff_revision "${repo_root}" "${source_commit}")"
  issue_id="$(jq -r '.issue_id // ""' <<<"${issue_resolution}")"
  if [ -z "${issue_id}" ]; then
    jq -cn \
      --arg source_commit "${source_commit}" \
      --arg target_commit "${target_commit}" \
      --arg landing_mode "${landing_mode}" \
      --argjson resolution "${issue_resolution}" \
      '{
        status: "skipped_unresolved",
        source_commit: $source_commit,
        target_commit: $target_commit,
        landing_mode: $landing_mode,
        resolution: $resolution
      }'
    return
  fi

  note_text="Landed on main as ${target_commit} after duplicating visible handoff commit ${source_commit} onto then-current main ${main_before_commit} to avoid rewinding main."
  issue_show="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_issue_show" issue show "${issue_id}")"
  existing_notes="$(jq -r 'if .ok and ((.output | type) == "array") and ((.output | length) > 0) then (.output[0].notes // "") else "" end' <<<"${issue_show}")"
  if [ -n "${existing_notes}" ] && grep -F -- "${note_text}" >/dev/null <<<"${existing_notes}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg note "${note_text}" \
      --arg landing_mode "${landing_mode}" \
      --argjson resolution "${issue_resolution}" \
      '{
        status: "already_recorded",
        issue_id: $issue_id,
        note: $note,
        landing_mode: $landing_mode,
        resolution: $resolution
      }'
    return
  fi

  update_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_issue_append_notes" issue append-notes "${issue_id}" --text "${note_text}")"
  if ! jq -e --arg issue_id "${issue_id}" '
      .ok and
      ((.output | type) == "array") and
      ((.output | length) > 0) and
      ((.output[0].id // "") == $issue_id)
    ' >/dev/null <<<"${update_result}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg note "${note_text}" \
      --arg landing_mode "${landing_mode}" \
      --argjson resolution "${issue_resolution}" \
      --argjson tracker "${update_result}" \
      '{
        status: "update_failed",
        issue_id: $issue_id,
        note: $note,
        landing_mode: $landing_mode,
        resolution: $resolution,
        tracker: $tracker
      }'
    return
  fi

  updated_issue="$(jq -c '.output[0]' <<<"${update_result}")"
  receipt_payload="$(jq -cn \
    --arg issue_id "${issue_id}" \
    --arg source_commit "${source_commit}" \
    --arg target_commit "${target_commit}" \
    --arg main_before_commit "${main_before_commit}" \
    --arg landing_mode "${landing_mode}" \
    --arg note "${note_text}" \
    --argjson issue "${updated_issue}" \
    '{
      issue_id: $issue_id,
      source_commit: $source_commit,
      target_commit: $target_commit,
      main_before_commit: $main_before_commit,
      landing_mode: $landing_mode,
      note: $note,
      issue: $issue
    }')"

  if ! receipt_json="$(append_receipt_capture "${repo_root}" "issue.note" "${receipt_payload}")"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg note "${note_text}" \
      --arg landing_mode "${landing_mode}" \
      --argjson issue "${updated_issue}" \
      '{
        status: "receipt_failed",
        issue_id: $issue_id,
        note: $note,
        landing_mode: $landing_mode,
        issue: $issue
      }'
    return
  fi

  jq -cn \
    --arg issue_id "${issue_id}" \
    --arg note "${note_text}" \
    --arg landing_mode "${landing_mode}" \
    --argjson issue "${updated_issue}" \
    --argjson receipt "${receipt_json}" \
    '{
      status: "updated",
      issue_id: $issue_id,
      note: $note,
      landing_mode: $landing_mode,
      issue: $issue,
      receipt: $receipt
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
    create_child_issue|claim_issue|close_issue|launch_lane|handoff_lane|finish_lane|archive_lane)
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
  local force_requested="${6:-false}"
  local workspace_root=""
  local requested_mode="remove"
  local effective_mode="none"
  local quarantine_path=""
  local registration_present=false
  local path_present=false
  local sentinel_guard='{"ok":true}'
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

  sentinel_guard="$(compact_lane_sentinel_guard "${issue_id}" "${workspace_path}" "${force_requested}")"
  if ! jq -e '.ok == true' >/dev/null <<<"${sentinel_guard}"; then
    printf '%s\n' "${sentinel_guard}"
    return 0
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

  if ! write_lane_sentinel "${issue_id}" "${workspace_name}" "${workspace_path}" "active" "${base_rev}"; then
    rollback_json="$(rollback_launch_artifacts "${repo_root}" "${issue_id}" "${workspace_name}" "${workspace_path}")"
    realization_json="$(jq -cn --arg workspace_name "${workspace_name}" --arg workspace_path "${workspace_path}" --arg base_rev "${base_rev}" --argjson rollback "${rollback_json}" '{kind:"launch_lane", workspace_name:$workspace_name, workspace_path:$workspace_path, base_rev:$base_rev, sentinel_path:(($workspace_path | rtrimstr("/")) + "/.tusk-lane"), rollback:$rollback}')"
    carrier_json="$(carrier_set_realization "${carrier_json}" "${realization_json}")"
    transition_failure_result "${carrier_json}" "failed to write lane sentinel after workspace creation" "$(jq -cn --arg workspace_name "${workspace_name}" --arg workspace_path "${workspace_path}" --argjson rollback "${rollback_json}" '{workspace_name:$workspace_name, workspace_path:$workspace_path, sentinel_path:(($workspace_path | rtrimstr("/")) + "/.tusk-lane"), rollback:$rollback}')"
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

cmd_doctor() {
  local repo_root="$1"
  local socket_path="$2"
  local json_output="${3:-false}"
  local -a args=(doctor --repo "${repo_root}" --socket "${socket_path}")

  if [ "${json_output}" = true ]; then
    args+=(--json)
  fi

  exec_tuskd_core "${args[@]}"
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

cmd_sessions_status() {
  local repo_root="$1"

  exec_tuskd_core sessions-status --repo "${repo_root}"
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
  local source_commit=""
  local target_commit=""
  local main_before_commit=""
  local git_before_commit=""
  local landing_mode="direct"
  local rewrite_required=false
  local duplicate_json='null'
  local move_revision=""
  local move_output=""
  local move_exit=0
  local export_output=""
  local export_exit=0
  local repair_json='{"ok":true,"payload":null}'
  local repair_status=0
  local needs_repair_after_land=false
  local landed_status=""
  local issue_note_json='{"status":"not_needed"}'
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
  source_commit="$(jq -r '.commit // ""' <<<"${target_lookup}")"
  target_commit="${source_commit}"
  main_before_commit="$(jq -r '.commit // ""' <<<"${main_lookup}")"
  git_before_commit="$(jq -r '.commit // ""' <<<"${git_main_before}")"

  if [ -n "${main_before_commit}" ] && [ "${source_commit}" = "${main_before_commit}" ]; then
    landing_mode="already_landed"
    target_commit="${main_before_commit}"
  elif [ -n "${main_before_commit}" ] && commit_descends_from "${repo_root}" "${source_commit}" "${main_before_commit}"; then
    landing_mode="direct"
  elif [ -n "${main_before_commit}" ] && commit_descends_from "${repo_root}" "${main_before_commit}" "${source_commit}"; then
    landing_mode="already_landed"
    target_commit="${main_before_commit}"
  elif [ -n "${main_before_commit}" ]; then
    landing_mode="duplicate_onto_main"
    rewrite_required=true
    target_commit=""
  fi

  if [ "${rewrite_required}" = "true" ]; then
    needs_repair_after_land=true
  elif jq -e --arg commit "${target_commit}" '.parent_commits | index($commit) != null' >/dev/null <<<"${before_coordinator}"; then
    needs_repair_after_land=false
  else
    needs_repair_after_land=true
  fi

  if [ "${plan_only}" = "true" ]; then
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg revision "${revision}" \
      --arg source_commit "${source_commit}" \
      --arg target_commit "${target_commit}" \
      --arg main_before_commit "${main_before_commit}" \
      --arg landing_mode "${landing_mode}" \
      --arg note "${note}" \
      --argjson before_coordinator "${before_coordinator}" \
      --argjson git_main_before "${git_main_before}" \
      --argjson rewrite_required "$(json_bool "${rewrite_required}")" \
      --argjson needs_repair_after_land "$(json_bool "${needs_repair_after_land}")" \
      '{
        ok: true,
        payload: {
          repo_root: $repo_root,
          revision: $revision,
          source_commit: $source_commit,
          target_commit: (if ($target_commit | length) > 0 then $target_commit else null end),
          main_before_commit: (if ($main_before_commit | length) > 0 then $main_before_commit else null end),
          landing_mode: $landing_mode,
          rewrite_required: $rewrite_required,
          note: (if ($note | length) > 0 then $note else null end),
          status: "plan",
          before: {
            coordinator: $before_coordinator,
            git_main: $git_main_before
          },
          needs_repair_after_land: $needs_repair_after_land,
          commands: (
            if $landing_mode == "duplicate_onto_main" then [
              ("jj --repository " + $repo_root + " duplicate " + $revision + " -o main"),
              ("jj --repository " + $repo_root + " bookmark move main --to <duplicated-revision>"),
              ("jj --repository " + $repo_root + " git export")
            ] elif $landing_mode == "already_landed" then [
              ("jj --repository " + $repo_root + " git export")
            ] else [
              ("jj --repository " + $repo_root + " bookmark move main --to " + $revision),
              ("jj --repository " + $repo_root + " git export")
            ] end
          ) + (if $needs_repair_after_land then [
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
      --arg source_commit "${source_commit}" \
      --arg target_commit "${target_commit}" \
      --arg landing_mode "${landing_mode}" \
      --arg note "${note}" \
      --argjson before_coordinator "${before_coordinator}" \
      --argjson git_main_before "${git_main_before}" \
      '{
        ok: true,
        payload: {
          repo_root: $repo_root,
          revision: $revision,
          source_commit: $source_commit,
          target_commit: $target_commit,
          landing_mode: $landing_mode,
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
          repair: null,
          issue_note: null
        }
      }'
    return 0
  fi

  if [ "${landing_mode}" = "duplicate_onto_main" ]; then
    duplicate_json="$(duplicate_revision_onto_main "${repo_root}" "${revision}")"
    if ! jq -e '.ok == true' >/dev/null <<<"${duplicate_json}"; then
      jq -cn \
        --arg repo_root "${repo_root}" \
        --arg revision "${revision}" \
        --arg source_commit "${source_commit}" \
        --arg main_before_commit "${main_before_commit}" \
        --arg landing_mode "${landing_mode}" \
        --argjson duplicate "${duplicate_json}" \
        --argjson before_coordinator "${before_coordinator}" \
        --argjson git_main_before "${git_main_before}" \
        '{
          ok: false,
          error: {
            message: "land-main failed to duplicate the requested revision onto main"
          },
          payload: {
            repo_root: $repo_root,
            revision: $revision,
            source_commit: $source_commit,
            main_before_commit: (if ($main_before_commit | length) > 0 then $main_before_commit else null end),
            landing_mode: $landing_mode,
            before: {
              coordinator: $before_coordinator,
              git_main: $git_main_before
            },
            duplicate: $duplicate
          }
        }'
      return 1
    fi
    target_commit="$(jq -r '.commit // ""' <<<"${duplicate_json}")"
  fi

  move_revision="${target_commit}"
  if [ "${landing_mode}" != "already_landed" ]; then
    if move_output="$(run_in_repo_capture "${repo_root}" jj --repository "${repo_root}" bookmark move main --to "${move_revision}")"; then
      move_exit=0
    else
      move_exit=$?
    fi
  fi
  if [ "${move_exit}" -ne 0 ]; then
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg revision "${revision}" \
      --arg source_commit "${source_commit}" \
      --arg main_before_commit "${main_before_commit}" \
      --arg landing_mode "${landing_mode}" \
      --arg output "${move_output}" \
      --argjson duplicate "${duplicate_json}" \
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
          source_commit: $source_commit,
          main_before_commit: (if ($main_before_commit | length) > 0 then $main_before_commit else null end),
          landing_mode: $landing_mode,
          before: {
            coordinator: $before_coordinator,
            git_main: $git_main_before
          },
          duplicate: (if $duplicate == null then null else $duplicate end),
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
      --arg source_commit "${source_commit}" \
      --arg target_commit "${target_commit}" \
      --arg main_before_commit "${main_before_commit}" \
      --arg landing_mode "${landing_mode}" \
      --arg note "${note}" \
      --arg status "${landed_status}" \
      --arg move_output "${move_output}" \
      --arg export_output "${export_output}" \
      --argjson export_exit "${export_exit}" \
      --argjson duplicate "${duplicate_json}" \
      --argjson before_coordinator "${before_coordinator}" \
      --argjson after_coordinator "${after_coordinator}" \
      --argjson git_main_before "${git_main_before}" \
      --argjson git_main_after "${git_main_after}" \
      '{
        repo_root: $repo_root,
        revision: $revision,
        source_commit: $source_commit,
        target_commit: $target_commit,
        main_before_commit: (if ($main_before_commit | length) > 0 then $main_before_commit else null end),
        landing_mode: $landing_mode,
        note: (if ($note | length) > 0 then $note else null end),
        status: $status,
        duplicate: (if $duplicate == null then null else $duplicate end),
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
      --arg source_commit "${source_commit}" \
      --arg status "${landed_status}" \
      --arg landing_mode "${landing_mode}" \
      --argjson before_coordinator "${before_coordinator}" \
      --argjson after_coordinator "${after_coordinator}" \
      --argjson git_main_before "${git_main_before}" \
      --argjson git_main_after "${git_main_after}" \
      --arg move_output "${move_output}" \
      --arg export_output "${export_output}" \
      --argjson export_exit "${export_exit}" \
      --argjson duplicate "${duplicate_json}" \
      --argjson receipt "$(if [ -n "${receipt_json}" ]; then printf '%s' "${receipt_json}"; else printf 'null'; fi)" \
      '{
        ok: false,
        error: {
          message: "land-main failed to export the colocated Git main ref"
        },
        payload: {
          repo_root: $repo_root,
          revision: $revision,
          source_commit: $source_commit,
          status: $status,
          landing_mode: $landing_mode,
          duplicate: (if $duplicate == null then null else $duplicate end),
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

  if [ "${rewrite_required}" = "true" ]; then
    issue_note_json="$(append_landed_revision_issue_note "${repo_root}" "${source_commit}" "${target_commit}" "${main_before_commit}" "${landing_mode}")"
  fi

  receipt_payload="$(jq -cn \
    --arg repo_root "${repo_root}" \
    --arg revision "${revision}" \
    --arg source_commit "${source_commit}" \
    --arg target_commit "${target_commit}" \
    --arg main_before_commit "${main_before_commit}" \
    --arg landing_mode "${landing_mode}" \
    --arg note "${note}" \
    --arg status "${landed_status}" \
    --arg move_output "${move_output}" \
    --arg export_output "${export_output}" \
    --argjson duplicate "${duplicate_json}" \
    --argjson before_coordinator "${before_coordinator}" \
    --argjson after_coordinator "${after_coordinator}" \
    --argjson git_main_before "${git_main_before}" \
    --argjson git_main_after "${git_main_after}" \
    --argjson repair "${repair_json}" \
    --argjson issue_note "${issue_note_json}" \
    '{
      repo_root: $repo_root,
      revision: $revision,
      source_commit: $source_commit,
      target_commit: $target_commit,
      main_before_commit: (if ($main_before_commit | length) > 0 then $main_before_commit else null end),
      landing_mode: $landing_mode,
      note: (if ($note | length) > 0 then $note else null end),
      status: $status,
      duplicate: (if $duplicate == null then null else $duplicate end),
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
        repair: ($repair.payload // null),
        issue_note: (if ($issue_note.status // "not_needed") == "not_needed" then null else $issue_note end)
      }')"

  if ! receipt_json="$(append_receipt_capture "${repo_root}" "land.main" "${receipt_payload}")"; then
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg revision "${revision}" \
      --arg source_commit "${source_commit}" \
      --arg status "${landed_status}" \
      --arg landing_mode "${landing_mode}" \
      --argjson before_coordinator "${before_coordinator}" \
      --argjson after_coordinator "${after_coordinator}" \
      --argjson git_main_before "${git_main_before}" \
      --argjson git_main_after "${git_main_after}" \
      --argjson duplicate "${duplicate_json}" \
      --argjson repair "${repair_json}" \
      --argjson issue_note "${issue_note_json}" \
      '{
        ok: false,
        error: {
          message: "land-main failed to append land.main receipt"
        },
        payload: {
          repo_root: $repo_root,
          revision: $revision,
          source_commit: $source_commit,
          status: $status,
          landing_mode: $landing_mode,
          duplicate: (if $duplicate == null then null else $duplicate end),
          before: {
            coordinator: $before_coordinator,
            git_main: $git_main_before
          },
          after: {
            coordinator: $after_coordinator,
            git_main: $git_main_after
          },
          repair: ($repair.payload // null),
          issue_note: (if ($issue_note.status // "not_needed") == "not_needed" then null else $issue_note end)
        }
      }'
    return 1
  fi

  jq -cn \
    --arg repo_root "${repo_root}" \
    --arg revision "${revision}" \
    --arg source_commit "${source_commit}" \
    --arg target_commit "${target_commit}" \
    --arg main_before_commit "${main_before_commit}" \
    --arg landing_mode "${landing_mode}" \
    --arg note "${note}" \
    --arg status "${landed_status}" \
    --argjson rewrite_required "$(json_bool "${rewrite_required}")" \
    --argjson duplicate "${duplicate_json}" \
    --argjson before_coordinator "${before_coordinator}" \
    --argjson after_coordinator "${after_coordinator}" \
    --argjson git_main_before "${git_main_before}" \
    --argjson git_main_after "${git_main_after}" \
    --argjson repair "${repair_json}" \
    --argjson issue_note "${issue_note_json}" \
    --argjson receipt "${receipt_json}" \
    '{
      ok: ($status == "landed" or $status == "landed_repaired"),
      payload: {
        repo_root: $repo_root,
        revision: $revision,
        source_commit: $source_commit,
        target_commit: $target_commit,
        main_before_commit: (if ($main_before_commit | length) > 0 then $main_before_commit else null end),
        landing_mode: $landing_mode,
        rewrite_required: $rewrite_required,
        duplicate: (if $duplicate == null then null else $duplicate end),
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
        issue_note: (if ($issue_note.status // "not_needed") == "not_needed" then null else $issue_note end),
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

cmd_create_child_issue() {
  local repo_root="$1"
  local socket_path="$2"
  local parent_id="$3"
  local title="$4"
  local description="${5:-}"
  local issue_type="${6:-task}"
  local priority="${7:-2}"
  local labels="${8:-}"

  cmd_transition_action "${repo_root}" "${socket_path}" "create_child_issue" "$(
    jq -cn \
      --arg parent_id "${parent_id}" \
      --arg title "${title}" \
      --arg description "${description}" \
      --arg issue_type "${issue_type}" \
      --arg priority "${priority}" \
      --arg labels "${labels}" \
      '{parent_id:$parent_id, title:$title, description:$description, issue_type:$issue_type, priority:$priority, labels:$labels}'
  )"
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

dispatch_lane_action() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local worker="${4:-codex}"
  local mode="${5:-handoff}"
  local note="${6:-}"
  local plan_only="${7:-false}"
  local lane_json="null"
  local lane_status=""
  local workspace_path=""
  local issue_result="null"
  local issue_json="null"
  local prompt_path=""
  local brief_path=""
  local output_path=""
  local launcher=""
  local brief_json="null"
  local dispatch_status="handoff"
  local dispatch_requested_at=""
  local previous_lane_json="null"
  local updated_lane_json="null"
  local exec_result='null'
  local board_json="null"
  local board_summary="null"
  local lanes_json="[]"
  local receipt_payload=""
  local receipt_json=""
  local payload_json=""

  if [ -z "${issue_id}" ]; then
    jq -cn '{ok:false, error:{message:"dispatch_lane requires issue_id"}}'
    return 0
  fi

  case "${worker}" in
    codex)
      ;;
    *)
      jq -cn \
        --arg issue_id "${issue_id}" \
        --arg worker "${worker}" \
        '{ok:false, issue_id:$issue_id, worker:$worker, error:{message:"dispatch_lane only supports worker codex"}}'
      return 0
      ;;
  esac

  case "${mode}" in
    handoff|exec)
      ;;
    *)
      jq -cn \
        --arg issue_id "${issue_id}" \
        --arg mode "${mode}" \
        '{ok:false, issue_id:$issue_id, mode:$mode, error:{message:"dispatch_lane only supports mode handoff or exec"}}'
      return 0
      ;;
  esac

  ensure_state_files "${repo_root}"
  lane_json="$(current_lane_for_issue "${repo_root}" "${issue_id}")"
  if [ "${lane_json}" = "null" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      '{ok:false, issue_id:$issue_id, error:{message:"dispatch_lane requires an existing lane record"}}'
    return 0
  fi

  lane_status="$(jq -r '.status // ""' <<<"${lane_json}")"
  if [ "${lane_status}" != "launched" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg status "${lane_status}" \
      '{ok:false, issue_id:$issue_id, status:$status, error:{message:"dispatch_lane requires a launched lane"}}'
    return 0
  fi

  workspace_path="$(jq -r '.workspace_path // ""' <<<"${lane_json}")"
  if [ -z "${workspace_path}" ] || [ ! -d "${workspace_path}" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg workspace_path "${workspace_path}" \
      '{ok:false, issue_id:$issue_id, workspace_path:$workspace_path, error:{message:"dispatch_lane requires a live workspace"}}'
    return 0
  fi

  issue_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_issue_show" issue show "${issue_id}")"
  issue_json="$(issue_snapshot_from_result "${issue_result}")"
  if [ "${issue_json}" = "null" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson tracker "${issue_result}" \
      '{ok:false, issue_id:$issue_id, error:{message:"dispatch_lane requires an existing issue", details:{tracker:$tracker}}}'
    return 0
  fi

  if [ "$(jq -r '.issue_type // ""' <<<"${issue_json}")" != "task" ] || ! issue_has_label "${issue_json}" "place:tusk"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson issue "${issue_json}" \
      '{ok:false, issue_id:$issue_id, error:{message:"dispatch_lane only admits place:tusk task issues", details:{issue:$issue}}}'
    return 0
  fi

  prompt_path="$(dispatch_prompt_path "${repo_root}" "${issue_id}")"
  brief_path="$(dispatch_brief_path "${repo_root}" "${issue_id}")"
  output_path="$(dispatch_last_message_path "${workspace_path}")"
  launcher="$(dispatch_worker_launcher)"
  brief_json="$(build_dispatch_brief "${repo_root}" "${issue_json}" "${lane_json}" "${worker}" "${mode}" "${note}" "${prompt_path}" "${brief_path}" "${output_path}" "${launcher}")"

  if [ "${plan_only}" = "true" ]; then
    payload_json="$(
      jq -cn \
        --arg status "plan" \
        --arg repo_root "${repo_root}" \
        --arg issue_id "${issue_id}" \
        --arg worker "${worker}" \
        --arg mode "${mode}" \
        --arg prompt_path "${prompt_path}" \
        --arg brief_path "${brief_path}" \
        --arg output_path "${output_path}" \
        --arg policy_class "$(dispatch_policy_class_id)" \
        --argjson lane "${lane_json}" \
        --argjson brief "${brief_json}" \
        '{
          status: $status,
          repo_root: $repo_root,
          issue_id: $issue_id,
          worker: $worker,
          mode: $mode,
          policy_class: $policy_class,
          prompt_path: $prompt_path,
          brief_path: $brief_path,
          output_path: $output_path,
          launch_command: ($brief.runner.command // null),
          lane: $lane,
          brief: $brief
        }'
    )"
    jq -cn --argjson payload "${payload_json}" '{ok:true, payload:$payload}'
    return 0
  fi

  write_dispatch_artifacts "${repo_root}" "${issue_id}" "${brief_json}"

  if [ "${mode}" = "exec" ]; then
    exec_result="$(run_dispatch_worker "${launcher}" "${workspace_path}" "${repo_root}" "${prompt_path}" "${output_path}" "$(jq -r '.base_commit // ""' <<<"${lane_json}")")"
    if jq -e '.ok == true' >/dev/null <<<"${exec_result}"; then
      dispatch_status="executed"
    elif jq -e '.timed_out == true' >/dev/null <<<"${exec_result}"; then
      dispatch_status="timed_out"
    else
      dispatch_status="failed"
    fi
  fi

  dispatch_requested_at="$(now_iso8601)"
  previous_lane_json="${lane_json}"
  updated_lane_json="$(
    jq -c \
      --arg status "${dispatch_status}" \
      --arg worker "${worker}" \
      --arg mode "${mode}" \
      --arg note "${note}" \
      --arg launcher "${launcher}" \
      --arg prompt_path "${prompt_path}" \
      --arg brief_path "${brief_path}" \
      --arg output_path "${output_path}" \
      --arg command "$(jq -r '.runner.command // ""' <<<"${brief_json}")" \
      --arg class_id "$(dispatch_policy_class_id)" \
      --arg requested_at "${dispatch_requested_at}" \
      --argjson runner_result "${exec_result}" \
      '
        . + {
          dispatch: {
            class_id: $class_id,
            worker: $worker,
            mode: $mode,
            status: $status,
            launcher: $launcher,
            prompt_path: $prompt_path,
            brief_path: $brief_path,
            output_path: $output_path,
            command: $command,
            requested_at: $requested_at,
            note: (if ($note | length) > 0 then $note else null end),
            runner_result: (if $runner_result == null then null else $runner_result end)
          }
        }
      ' <<<"${lane_json}"
  )"

  if ! upsert_lane_state "${repo_root}" "${updated_lane_json}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson lane "${updated_lane_json}" \
      '{ok:false, issue_id:$issue_id, error:{message:"failed to persist dispatched lane state", details:{lane:$lane}}}'
    return 0
  fi

  board_json="$(refresh_transition_board "${repo_root}" "${socket_path}")"
  board_summary="$(jq -c '.summary // null' <<<"${board_json}")"
  lanes_json="$(jq -c '.lanes // []' <<<"${board_json}")"
  receipt_payload="$(
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg worker "${worker}" \
      --arg mode "${mode}" \
      --arg note "${note}" \
      --argjson lane "${updated_lane_json}" \
      --argjson dispatch "$(jq -c '.dispatch // null' <<<"${updated_lane_json}")" \
      --argjson board_summary "${board_summary}" \
      '{
        issue_id: $issue_id,
        worker: $worker,
        mode: $mode,
        note: $note,
        lane: $lane,
        dispatch: $dispatch,
        board_summary: $board_summary
      }'
  )"

  if ! receipt_json="$(append_receipt_capture "${repo_root}" "lane.dispatch" "${receipt_payload}")"; then
    restore_lane_state_snapshot "${repo_root}" "${previous_lane_json}" >/dev/null 2>&1 || true
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson restored_lane "${previous_lane_json}" \
      '{ok:false, issue_id:$issue_id, error:{message:"failed to append lane.dispatch receipt", details:{restored_lane:$restored_lane}}}'
    return 0
  fi

  payload_json="$(
    jq -cn \
      --arg status "${dispatch_status}" \
      --arg repo_root "${repo_root}" \
      --arg issue_id "${issue_id}" \
      --arg worker "${worker}" \
      --arg mode "${mode}" \
      --arg prompt_path "${prompt_path}" \
      --arg brief_path "${brief_path}" \
      --arg output_path "${output_path}" \
      --arg policy_class "$(dispatch_policy_class_id)" \
      --argjson lane "${updated_lane_json}" \
      --argjson dispatch "$(jq -c '.dispatch // null' <<<"${updated_lane_json}")" \
      --argjson brief "${brief_json}" \
      --argjson receipt "${receipt_json}" \
      --argjson lanes "${lanes_json}" \
      --argjson board_summary "${board_summary}" \
      '{
        status: $status,
        repo_root: $repo_root,
        issue_id: $issue_id,
        worker: $worker,
        mode: $mode,
        policy_class: $policy_class,
        prompt_path: $prompt_path,
        brief_path: $brief_path,
        output_path: $output_path,
        launch_command: ($brief.runner.command // null),
        lane: $lane,
        dispatch: $dispatch,
        brief: $brief,
        receipt: $receipt,
        lanes: $lanes,
        board_summary: $board_summary
      }'
  )"

  if [ "${dispatch_status}" = "timed_out" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson details "${payload_json}" \
      '{ok:false, issue_id:$issue_id, error:{message:"dispatch_lane worker timed out", details:$details}}'
    return 0
  fi

  if [ "${dispatch_status}" = "failed" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson details "${payload_json}" \
      '{ok:false, issue_id:$issue_id, error:{message:"dispatch_lane worker execution failed", details:$details}}'
    return 0
  fi

  jq -cn --argjson payload "${payload_json}" '{ok:true, payload:$payload}'
}

cmd_dispatch_lane() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local worker="${4:-codex}"
  local mode="${5:-handoff}"
  local note="${6:-}"
  local plan_only="${7:-false}"
  local dispatch_result=""

  dispatch_result="$(dispatch_lane_action "${repo_root}" "${socket_path}" "${issue_id}" "${worker}" "${mode}" "${note}" "${plan_only}")"
  if jq -e '.ok == true' >/dev/null <<<"${dispatch_result}"; then
    jq -c '.payload' <<<"${dispatch_result}"
    return 0
  fi

  jq -c '.' <<<"${dispatch_result}"
  return 1
}

autonomous_lane_action() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local base_rev="${4:-main}"
  local slug="${5:-}"
  local worker="${6:-codex}"
  local note="${7:-}"
  local quarantine_requested="${8:-false}"
  local plan_only="${9:-false}"
  local issue_result="null"
  local issue_json="null"
  local verification_json="[]"
  local claim_result='{"ok":true,"payload":null}'
  local launch_result='{"ok":true,"payload":null}'
  local dispatch_result='{"ok":true,"payload":null}'
  local lane_json="null"
  local workspace_path=""
  local workspace_name=""
  local lane_base_commit=""
  local revision_probe='null'
  local verification_result='null'
  local resolved_revision=""
  local reason=""
  local complete_result='{"ok":true,"payload":null}'
  local receipt_payload=""
  local receipt_json=""

  if [ -z "${issue_id}" ]; then
    jq -cn '{ok:false, error:{message:"autonomous_lane requires issue_id"}}'
    return 0
  fi

  ensure_state_files "${repo_root}"
  issue_result="$(run_tracker_json_command_in_repo "${repo_root}" "tracker_issue_show" issue show "${issue_id}")"
  issue_json="$(issue_snapshot_from_result "${issue_result}")"
  if [ "${issue_json}" = "null" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson tracker "${issue_result}" \
      '{ok:false, issue_id:$issue_id, error:{message:"autonomous_lane requires an existing issue", details:{tracker:$tracker}}}'
    return 0
  fi

  if [ "$(jq -r '.status // ""' <<<"${issue_json}")" != "open" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson issue "${issue_json}" \
      '{ok:false, issue_id:$issue_id, error:{message:"autonomous_lane requires an open issue", details:{issue:$issue}}}'
    return 0
  fi

  lane_json="$(current_lane_for_issue "${repo_root}" "${issue_id}")"
  if [ "${lane_json}" != "null" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson lane "${lane_json}" \
      '{ok:false, issue_id:$issue_id, error:{message:"autonomous_lane requires no existing live lane", details:{lane:$lane}}}'
    return 0
  fi

  if ! autonomous_issue_is_admitted "${issue_json}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson issue "${issue_json}" \
      '{ok:false, issue_id:$issue_id, error:{message:"autonomous_lane only admits autonomy:v1-safe place:tusk task issues", details:{issue:$issue}}}'
    return 0
  fi

  verification_json="$(issue_verification_commands_json "$(jq -r '.description // ""' <<<"${issue_json}")")"
  if [ "$(jq 'length' <<<"${verification_json}")" -eq 0 ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson issue "${issue_json}" \
      '{ok:false, issue_id:$issue_id, error:{message:"autonomous_lane requires explicit verification commands", details:{issue:$issue}}}'
    return 0
  fi

  if [ "${plan_only}" = "true" ]; then
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg issue_id "${issue_id}" \
      --arg base_rev "${base_rev}" \
      --arg slug "${slug}" \
      --arg worker "${worker}" \
      --arg note "${note}" \
      --arg policy_class "$(autonomous_policy_class_id)" \
      --argjson verification "${verification_json}" \
      --argjson quarantine_requested "$(json_bool "${quarantine_requested}")" \
      --argjson issue "${issue_json}" \
      '{
        ok: true,
        payload: {
          status: "plan",
          repo_root: $repo_root,
          issue_id: $issue_id,
          base_rev: $base_rev,
          slug: (if ($slug | length) > 0 then $slug else null end),
          worker: $worker,
          policy_class: $policy_class,
          note: (if ($note | length) > 0 then $note else null end),
          quarantine_requested: $quarantine_requested,
          issue: $issue,
          verification: $verification,
          commands: [
            ("tuskd claim-issue --repo " + $repo_root + " --issue-id " + $issue_id),
            ("tuskd launch-lane --repo " + $repo_root + " --issue-id " + $issue_id + " --base-rev " + $base_rev + (if ($slug | length) > 0 then " --slug " + $slug else "" end)),
            ("tuskd dispatch-lane --repo " + $repo_root + " --issue-id " + $issue_id + " --mode exec --worker " + $worker),
            "run issue Verification commands in the lane checkout",
            "resolve one clean visible jj revision from the lane workspace",
            ("tuskd complete-lane --repo " + $repo_root + " --issue-id " + $issue_id + " --revision <resolved-rev> --reason \"completed in visible commit <resolved-rev>\"")
          ]
        }
      }'
    return 0
  fi

  claim_result="$(run_transition_action "${repo_root}" "${socket_path}" "claim_issue" "$(jq -cn --arg issue_id "${issue_id}" '{issue_id:$issue_id}')")"
  if ! jq -e '.ok == true' >/dev/null <<<"${claim_result}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson details "${claim_result}" \
      '{ok:false, issue_id:$issue_id, error:{message:"autonomous_lane failed during claim_issue", details:$details}}'
    return 0
  fi

  launch_result="$(run_transition_action "${repo_root}" "${socket_path}" "launch_lane" "$(jq -cn --arg issue_id "${issue_id}" --arg base_rev "${base_rev}" --arg slug "${slug}" '{issue_id:$issue_id, base_rev:$base_rev, slug:(if ($slug | length) > 0 then $slug else null end)}')")"
  if ! jq -e '.ok == true' >/dev/null <<<"${launch_result}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson details "${launch_result}" \
      '{ok:false, issue_id:$issue_id, error:{message:"autonomous_lane failed during launch_lane", details:$details}}'
    return 0
  fi

  dispatch_result="$(dispatch_lane_action "${repo_root}" "${socket_path}" "${issue_id}" "${worker}" "exec" "${note}" "false")"
  if ! jq -e '.ok == true' >/dev/null <<<"${dispatch_result}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson details "${dispatch_result}" \
      --argjson claim "$(jq -c '.payload' <<<"${claim_result}")" \
      --argjson launch "$(jq -c '.payload' <<<"${launch_result}")" \
      '{ok:false, issue_id:$issue_id, error:{message:"autonomous_lane failed during dispatch_lane", details:$details}, payload:{issue_id:$issue_id, status:"failed", phase:"dispatch", claim:$claim, launch:$launch}}'
    return 0
  fi

  lane_json="$(current_lane_for_issue "${repo_root}" "${issue_id}")"
  workspace_path="$(jq -r '.workspace_path // ""' <<<"${lane_json}")"
  workspace_name="$(jq -r '.workspace_name // ""' <<<"${lane_json}")"
  lane_base_commit="$(jq -r '.base_commit // ""' <<<"${lane_json}")"

  revision_probe="$(resolve_autonomous_handoff_revision "${workspace_path}" "${repo_root}" "${lane_base_commit}")"
  if ! jq -e '.ok == true' >/dev/null <<<"${revision_probe}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson claim "$(jq -c '.payload' <<<"${claim_result}")" \
      --argjson launch "$(jq -c '.payload' <<<"${launch_result}")" \
      --argjson dispatch "$(jq -c '.payload' <<<"${dispatch_result}")" \
      --argjson revision_probe "${revision_probe}" \
      '{ok:false, issue_id:$issue_id, error:{message:"autonomous_lane requires a clean visible revision from the worker lane", details:{revision_probe:$revision_probe}}, payload:{issue_id:$issue_id, status:"failed", phase:"revision", claim:$claim, launch:$launch, dispatch:$dispatch, revision_probe:$revision_probe}}'
    return 0
  fi
  resolved_revision="$(jq -r '.resolved_revision // ""' <<<"${revision_probe}")"

  verification_result="$(run_issue_verification_in_checkout "${workspace_path}" "${repo_root}" "${verification_json}")"
  if ! jq -e '.ok == true' >/dev/null <<<"${verification_result}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson claim "$(jq -c '.payload' <<<"${claim_result}")" \
      --argjson launch "$(jq -c '.payload' <<<"${launch_result}")" \
      --argjson dispatch "$(jq -c '.payload' <<<"${dispatch_result}")" \
      --argjson revision_probe "${revision_probe}" \
      --argjson verification "${verification_result}" \
      '{ok:false, issue_id:$issue_id, error:{message:"autonomous_lane verification failed", details:{verification:$verification}}, payload:{issue_id:$issue_id, status:"failed", phase:"verification", claim:$claim, launch:$launch, dispatch:$dispatch, revision_probe:$revision_probe, verification:$verification}}'
    return 0
  fi

  reason="completed in visible commit ${resolved_revision}"
  complete_result="$(complete_lane_action "${repo_root}" "${socket_path}" "${issue_id}" "${resolved_revision}" "${reason}" "completed" "${note}" "${quarantine_requested}" "false")"
  if ! jq -e '.ok == true' >/dev/null <<<"${complete_result}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson claim "$(jq -c '.payload' <<<"${claim_result}")" \
      --argjson launch "$(jq -c '.payload' <<<"${launch_result}")" \
      --argjson dispatch "$(jq -c '.payload' <<<"${dispatch_result}")" \
      --argjson revision_probe "${revision_probe}" \
      --argjson verification "${verification_result}" \
      --argjson complete "${complete_result}" \
      '{ok:false, issue_id:$issue_id, error:{message:"autonomous_lane failed during complete_lane", details:$complete}, payload:{issue_id:$issue_id, status:"failed", phase:"closeout", claim:$claim, launch:$launch, dispatch:$dispatch, revision_probe:$revision_probe, verification:$verification, complete:$complete}}'
    return 0
  fi

  receipt_payload="$(
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg policy_class "$(autonomous_policy_class_id)" \
      --arg worker "${worker}" \
      --arg base_rev "${base_rev}" \
      --arg workspace_name "${workspace_name}" \
      --arg workspace_path "${workspace_path}" \
      --arg reason "${reason}" \
      --arg note "${note}" \
      --argjson claim "$(jq -c '.payload' <<<"${claim_result}")" \
      --argjson launch "$(jq -c '.payload' <<<"${launch_result}")" \
      --argjson dispatch "$(jq -c '.payload' <<<"${dispatch_result}")" \
      --argjson revision_probe "${revision_probe}" \
      --argjson verification "${verification_result}" \
      --argjson complete "$(jq -c '.payload' <<<"${complete_result}")" \
      '{
        issue_id: $issue_id,
        policy_class: $policy_class,
        worker: $worker,
        base_rev: $base_rev,
        workspace: {
          name: $workspace_name,
          path: $workspace_path
        },
        status: "completed",
        reason: $reason,
        note: (if ($note | length) > 0 then $note else null end),
        claim: $claim,
        launch: $launch,
        dispatch: $dispatch,
        revision_probe: $revision_probe,
        verification: $verification,
        complete: $complete
      }'
  )"
  if ! receipt_json="$(append_receipt_capture "${repo_root}" "lane.autonomous" "${receipt_payload}")"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --argjson claim "$(jq -c '.payload' <<<"${claim_result}")" \
      --argjson launch "$(jq -c '.payload' <<<"${launch_result}")" \
      --argjson dispatch "$(jq -c '.payload' <<<"${dispatch_result}")" \
      --argjson revision_probe "${revision_probe}" \
      --argjson verification "${verification_result}" \
      --argjson complete "$(jq -c '.payload' <<<"${complete_result}")" \
      '{ok:false, issue_id:$issue_id, error:{message:"autonomous_lane failed to append lane.autonomous receipt"}, payload:{issue_id:$issue_id, status:"completed", claim:$claim, launch:$launch, dispatch:$dispatch, revision_probe:$revision_probe, verification:$verification, complete:$complete}}'
    return 1
  fi

  jq -cn \
    --arg issue_id "${issue_id}" \
    --arg policy_class "$(autonomous_policy_class_id)" \
    --arg worker "${worker}" \
    --arg base_rev "${base_rev}" \
    --arg reason "${reason}" \
    --arg note "${note}" \
    --argjson claim "$(jq -c '.payload' <<<"${claim_result}")" \
    --argjson launch "$(jq -c '.payload' <<<"${launch_result}")" \
    --argjson dispatch "$(jq -c '.payload' <<<"${dispatch_result}")" \
    --argjson revision_probe "${revision_probe}" \
    --argjson verification "${verification_result}" \
    --argjson complete "$(jq -c '.payload' <<<"${complete_result}")" \
    --argjson receipt "${receipt_json}" \
    '{
      ok: true,
      payload: {
        issue_id: $issue_id,
        status: "completed",
        policy_class: $policy_class,
        worker: $worker,
        base_rev: $base_rev,
        reason: $reason,
        note: (if ($note | length) > 0 then $note else null end),
        claim: $claim,
        launch: $launch,
        dispatch: $dispatch,
        revision_probe: $revision_probe,
        verification: $verification,
        complete: $complete,
        receipt: $receipt
      }
    }'
}

cmd_autonomous_lane() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local base_rev="${4:-main}"
  local slug="${5:-}"
  local worker="${6:-codex}"
  local note="${7:-}"
  local quarantine_requested="${8:-false}"
  local plan_only="${9:-false}"
  local autonomous_result=""

  autonomous_result="$(autonomous_lane_action "${repo_root}" "${socket_path}" "${issue_id}" "${base_rev}" "${slug}" "${worker}" "${note}" "${quarantine_requested}" "${plan_only}")"
  if jq -e '.ok == true' >/dev/null <<<"${autonomous_result}"; then
    jq -c '.payload' <<<"${autonomous_result}"
    return 0
  fi

  jq -c '.' <<<"${autonomous_result}"
  return 1
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

cmd_lane_park() {
  local repo_root="$1"
  local issue_id="$2"

  exec_tuskd_core lane-park --repo "${repo_root}" --issue-id "${issue_id}"
}

cmd_lane_abandon() {
  local repo_root="$1"
  local issue_id="$2"

  exec_tuskd_core lane-abandon --repo "${repo_root}" --issue-id "${issue_id}"
}

cmd_archive_lane() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local note="${4:-}"
  cmd_transition_action "${repo_root}" "${socket_path}" "archive_lane" "$(jq -cn --arg issue_id "${issue_id}" --arg note "${note}" '{issue_id:$issue_id, note:$note}')"
}

complete_lane_action() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local revision="$4"
  local reason="$5"
  local outcome="${6:-completed}"
  local note="${7:-}"
  local quarantine_requested="${8:-false}"
  local plan_only="${9:-false}"
  local lane_json="null"
  local lane_status=""
  local workspace_name=""
  local workspace_path=""
  local resolved_revision=""
  local cleanup_mode="remove"
  local cleanup_command=""
  local handoff_result='{"ok":true,"payload":null}'
  local finish_result='{"ok":true,"payload":null}'
  local land_result='{"ok":true,"payload":null}'
  local cleanup_result='{"ok":true,"payload":null}'
  local archive_result='{"ok":true,"payload":null}'
  local close_result='{"ok":true,"payload":null}'
  local receipt_payload=""
  local receipt_json=""

  if [ -z "${issue_id}" ]; then
    jq -cn '{ok:false, error:{message:"complete_lane requires issue_id"}}'
    return 0
  fi

  if [ -z "${reason}" ]; then
    jq -cn --arg issue_id "${issue_id}" '{ok:false, error:{message:"complete_lane requires reason"}, issue_id:$issue_id}'
    return 0
  fi

  ensure_state_files "${repo_root}"
  lane_json="$(current_lane_for_issue "${repo_root}" "${issue_id}")"
  if [ "${lane_json}" = "null" ]; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      '{ok:false, issue_id:$issue_id, error:{message:"complete_lane requires an existing lane record"}}'
    return 0
  fi

  lane_status="$(jq -r '.status // ""' <<<"${lane_json}")"
  workspace_name="$(jq -r '.workspace_name // ""' <<<"${lane_json}")"
  workspace_path="$(jq -r '.workspace_path // ""' <<<"${lane_json}")"
  resolved_revision="${revision}"
  if [ -z "${resolved_revision}" ]; then
    resolved_revision="$(jq -r '.handoff_revision // ""' <<<"${lane_json}")"
  fi
  if [ "${quarantine_requested}" = "true" ]; then
    cleanup_mode="quarantine"
  fi
  if [ "${cleanup_mode}" = "quarantine" ]; then
    cleanup_command="forget lane workspace registration and quarantine the workspace directory"
  else
    cleanup_command="forget lane workspace registration and remove the workspace directory"
  fi

  case "${lane_status}" in
    launched)
      if [ -z "${resolved_revision}" ]; then
        jq -cn \
          --arg issue_id "${issue_id}" \
          --arg status "${lane_status}" \
          '{ok:false, issue_id:$issue_id, status:$status, error:{message:"complete_lane requires --revision before a launched lane can be completed"}}'
        return 0
      fi
      ;;
    handoff|finished)
      if [ -z "${resolved_revision}" ]; then
        jq -cn \
          --arg issue_id "${issue_id}" \
          --arg status "${lane_status}" \
          '{ok:false, issue_id:$issue_id, status:$status, error:{message:"complete_lane requires a resolved revision from --revision or prior handoff"}}'
        return 0
      fi
      ;;
    *)
      jq -cn \
        --arg issue_id "${issue_id}" \
        --arg status "${lane_status}" \
        '{ok:false, issue_id:$issue_id, status:$status, error:{message:"complete_lane requires a launched, handoff, or finished lane"}}'
      return 0
      ;;
  esac

  if [ "${plan_only}" = "true" ]; then
    jq -cn \
      --arg repo_root "${repo_root}" \
      --arg issue_id "${issue_id}" \
      --arg from_status "${lane_status}" \
      --arg revision "${resolved_revision}" \
      --arg reason "${reason}" \
      --arg outcome "${outcome}" \
      --arg note "${note}" \
      --arg workspace_name "${workspace_name}" \
      --arg workspace_path "${workspace_path}" \
      --arg cleanup_mode "${cleanup_mode}" \
      --arg cleanup_command "${cleanup_command}" \
      --argjson lane "${lane_json}" \
      --argjson quarantine_requested "$(json_bool "${quarantine_requested}")" \
      '{
        ok: true,
        payload: {
          repo_root: $repo_root,
          issue_id: $issue_id,
          from_status: $from_status,
          revision: $revision,
          reason: $reason,
          outcome: $outcome,
          note: (if ($note | length) > 0 then $note else null end),
          status: "plan",
          lane: $lane,
          workspace: {
            name: $workspace_name,
            path: $workspace_path
          },
          cleanup: {
            mode: $cleanup_mode,
            quarantine_requested: $quarantine_requested,
            command: $cleanup_command
          },
          commands: (
            (if $from_status == "launched" then [
              ("tuskd handoff-lane --repo " + $repo_root + " --issue-id " + $issue_id + " --revision " + $revision),
              ("tuskd finish-lane --repo " + $repo_root + " --issue-id " + $issue_id + " --outcome " + $outcome)
            ] elif $from_status == "handoff" then [
              ("tuskd finish-lane --repo " + $repo_root + " --issue-id " + $issue_id + " --outcome " + $outcome)
            ] else [] end)
            + [
              ("tuskd land-main --repo " + $repo_root + " --revision " + $revision),
              $cleanup_command,
              ("tuskd archive-lane --repo " + $repo_root + " --issue-id " + $issue_id),
              ("tuskd close-issue --repo " + $repo_root + " --issue-id " + $issue_id + " --reason " + $reason)
            ]
          )
        }
      }'
    return 0
  fi

  case "${lane_status}" in
    launched)
      handoff_result="$(run_transition_action "${repo_root}" "${socket_path}" "handoff_lane" "$(jq -cn --arg issue_id "${issue_id}" --arg revision "${resolved_revision}" --arg note "${note}" '{issue_id:$issue_id, revision:$revision, note:$note}')")"
      if ! jq -e '.ok == true' >/dev/null <<<"${handoff_result}"; then
        jq -cn \
          --arg issue_id "${issue_id}" \
          --arg status "${lane_status}" \
          --argjson details "${handoff_result}" \
          '{ok:false, issue_id:$issue_id, status:$status, error:{message:"complete_lane failed during handoff_lane", details:$details}}'
        return 0
      fi
      finish_result="$(run_transition_action "${repo_root}" "${socket_path}" "finish_lane" "$(jq -cn --arg issue_id "${issue_id}" --arg outcome "${outcome}" --arg note "${note}" '{issue_id:$issue_id, outcome:$outcome, note:$note}')")"
      if ! jq -e '.ok == true' >/dev/null <<<"${finish_result}"; then
        jq -cn \
          --arg issue_id "${issue_id}" \
          --arg status "${lane_status}" \
          --argjson details "${finish_result}" \
          '{ok:false, issue_id:$issue_id, status:$status, error:{message:"complete_lane failed during finish_lane", details:$details}}'
        return 0
      fi
      ;;
    handoff)
      finish_result="$(run_transition_action "${repo_root}" "${socket_path}" "finish_lane" "$(jq -cn --arg issue_id "${issue_id}" --arg outcome "${outcome}" --arg note "${note}" '{issue_id:$issue_id, outcome:$outcome, note:$note}')")"
      if ! jq -e '.ok == true' >/dev/null <<<"${finish_result}"; then
        jq -cn \
          --arg issue_id "${issue_id}" \
          --arg status "${lane_status}" \
          --argjson details "${finish_result}" \
          '{ok:false, issue_id:$issue_id, status:$status, error:{message:"complete_lane failed during finish_lane", details:$details}}'
        return 0
      fi
      ;;
    finished)
      ;;
  esac

  if ! land_result="$(cmd_land_main "${repo_root}" "${resolved_revision}" "${note}" "false")"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg status "${lane_status}" \
      --argjson details "${land_result}" \
      '{ok:false, issue_id:$issue_id, status:$status, error:{message:"complete_lane failed during land-main", details:$details}}'
    return 1
  fi

  cleanup_result="$(compact_lane_workspace "${repo_root}" "${issue_id}" "${workspace_name}" "${workspace_path}" "${quarantine_requested}")"
  if ! jq -e '.ok == true' >/dev/null <<<"${cleanup_result}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg status "${lane_status}" \
      --argjson details "${cleanup_result}" \
      '{ok:false, issue_id:$issue_id, status:$status, error:{message:"complete_lane failed during workspace cleanup", details:$details}}'
    return 0
  fi

  archive_result="$(run_transition_action "${repo_root}" "${socket_path}" "archive_lane" "$(jq -cn --arg issue_id "${issue_id}" --arg note "${note}" '{issue_id:$issue_id, note:$note}')")"
  if ! jq -e '.ok == true' >/dev/null <<<"${archive_result}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg status "${lane_status}" \
      --argjson details "${archive_result}" \
      '{ok:false, issue_id:$issue_id, status:$status, error:{message:"complete_lane failed during archive_lane", details:$details}}'
    return 0
  fi

  close_result="$(run_transition_action "${repo_root}" "${socket_path}" "close_issue" "$(jq -cn --arg issue_id "${issue_id}" --arg reason "${reason}" '{issue_id:$issue_id, reason:$reason}')")"
  if ! jq -e '.ok == true' >/dev/null <<<"${close_result}"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg status "${lane_status}" \
      --argjson details "${close_result}" \
      '{ok:false, issue_id:$issue_id, status:$status, error:{message:"complete_lane failed during close_issue", details:$details}}'
    return 0
  fi

  receipt_payload="$(jq -cn \
    --arg issue_id "${issue_id}" \
    --arg from_status "${lane_status}" \
    --arg reason "${reason}" \
    --arg outcome "${outcome}" \
    --arg revision "${resolved_revision}" \
    --arg note "${note}" \
    --argjson handoff "$(jq -c '.payload' <<<"${handoff_result}")" \
    --argjson finish "$(jq -c '.payload' <<<"${finish_result}")" \
    --argjson land "$(jq -c '.payload' <<<"${land_result}")" \
    --argjson cleanup "${cleanup_result}" \
    --argjson archive "$(jq -c '.payload' <<<"${archive_result}")" \
    --argjson close "$(jq -c '.payload' <<<"${close_result}")" \
    '{
      issue_id: $issue_id,
      from_status: $from_status,
      reason: $reason,
      outcome: $outcome,
      revision: $revision,
      note: (if ($note | length) > 0 then $note else null end),
      handoff: $handoff,
      finish: $finish,
      land: $land,
      cleanup: $cleanup,
      archive: $archive,
      close: $close
    }')"
  if ! receipt_json="$(append_receipt_capture "${repo_root}" "lane.complete" "${receipt_payload}")"; then
    jq -cn \
      --arg issue_id "${issue_id}" \
      --arg status "${lane_status}" \
      --arg revision "${resolved_revision}" \
      --arg reason "${reason}" \
      --arg outcome "${outcome}" \
      --arg note "${note}" \
      --argjson land "$(jq -c '.payload' <<<"${land_result}")" \
      --argjson cleanup "${cleanup_result}" \
      --argjson archive "$(jq -c '.payload' <<<"${archive_result}")" \
      --argjson close "$(jq -c '.payload' <<<"${close_result}")" \
      '{
        ok: false,
        error: {
          message: "complete_lane failed to append lane.complete receipt"
        },
        payload: {
          issue_id: $issue_id,
          status: $status,
          revision: $revision,
          reason: $reason,
          outcome: $outcome,
          note: (if ($note | length) > 0 then $note else null end),
          land: $land,
          cleanup: $cleanup,
          archive: $archive,
          close: $close
        }
      }'
    return 1
  fi

  jq -cn \
    --arg issue_id "${issue_id}" \
    --arg from_status "${lane_status}" \
    --arg reason "${reason}" \
    --arg outcome "${outcome}" \
    --arg revision "${resolved_revision}" \
    --arg note "${note}" \
    --argjson handoff "$(jq -c '.payload' <<<"${handoff_result}")" \
    --argjson finish "$(jq -c '.payload' <<<"${finish_result}")" \
    --argjson land "$(jq -c '.payload' <<<"${land_result}")" \
    --argjson cleanup "${cleanup_result}" \
    --argjson archive "$(jq -c '.payload' <<<"${archive_result}")" \
    --argjson close "$(jq -c '.payload' <<<"${close_result}")" \
    --argjson receipt "${receipt_json}" \
    '{
      ok: true,
      payload: {
        issue_id: $issue_id,
        from_status: $from_status,
        reason: $reason,
        outcome: $outcome,
        revision: $revision,
        note: (if ($note | length) > 0 then $note else null end),
        status: "completed",
        handoff: $handoff,
        finish: $finish,
        land: $land,
        cleanup: $cleanup,
        archive: $archive,
        close: $close,
        receipt: $receipt
      }
    }'
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
  local force_requested="${9:-false}"
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
    handoff)
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
        '{ok:false, issue_id:$issue_id, status:$status, error:{message:"compact_lane requires a launched, handoff, or finished lane"}}'
      return 0
      ;;
  esac

  cleanup_result="$(compact_lane_workspace "${repo_root}" "${issue_id}" "${workspace_name}" "${workspace_path}" "${quarantine_requested}" "${force_requested}")"
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
  local force_requested="${9:-false}"
  local compact_result=""

  compact_result="$(compact_lane_action "${repo_root}" "${socket_path}" "${issue_id}" "${revision}" "${reason}" "${outcome}" "${note}" "${quarantine_requested}" "${force_requested}")"
  if jq -e '.ok == true' >/dev/null <<<"${compact_result}"; then
    jq -c '.payload' <<<"${compact_result}"
    return 0
  fi

  jq -c '.' <<<"${compact_result}"
  return 1
}

cmd_complete_lane() {
  local repo_root="$1"
  local socket_path="$2"
  local issue_id="$3"
  local revision="$4"
  local reason="$5"
  local outcome="${6:-completed}"
  local note="${7:-}"
  local quarantine_requested="${8:-false}"
  local plan_only="${9:-false}"
  local complete_result=""

  complete_result="$(complete_lane_action "${repo_root}" "${socket_path}" "${issue_id}" "${revision}" "${reason}" "${outcome}" "${note}" "${quarantine_requested}" "${plan_only}")"
  if jq -e '.ok == true' >/dev/null <<<"${complete_result}"; then
    jq -c '.payload' <<<"${complete_result}"
    return 0
  fi

  jq -c '.' <<<"${complete_result}"
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
parent_id_arg=""
issue_id_arg=""
title_arg=""
description_arg=""
type_arg=""
priority_arg=""
labels_arg=""
worker_arg=""
mode_arg=""
reason_arg=""
base_rev_arg=""
target_rev_arg=""
slug_arg=""
revision_arg=""
outcome_arg=""
note_arg=""
payload_arg="null"
quarantine_arg=false
json_arg=false
force_arg=false

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
    --json)
      json_arg=true
      shift
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
    --parent-id)
      [ $# -ge 2 ] || fail "--parent-id requires a value"
      parent_id_arg="$2"
      shift 2
      ;;
    --title)
      [ $# -ge 2 ] || fail "--title requires a value"
      title_arg="$2"
      shift 2
      ;;
    --description)
      [ $# -ge 2 ] || fail "--description requires a value"
      description_arg="$2"
      shift 2
      ;;
    --type)
      [ $# -ge 2 ] || fail "--type requires a value"
      type_arg="$2"
      shift 2
      ;;
    --priority)
      [ $# -ge 2 ] || fail "--priority requires a value"
      priority_arg="$2"
      shift 2
      ;;
    --labels)
      [ $# -ge 2 ] || fail "--labels requires a value"
      labels_arg="$2"
      shift 2
      ;;
    --worker)
      [ $# -ge 2 ] || fail "--worker requires a value"
      worker_arg="$2"
      shift 2
      ;;
    --mode)
      [ $# -ge 2 ] || fail "--mode requires a value"
      mode_arg="$2"
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
    --force)
      force_arg=true
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

if [ "${json_arg}" = true ] && [ "${command}" != "doctor" ]; then
  fail "unknown argument: --json"
fi

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
  doctor)
    cmd_doctor "${repo_root}" "${socket_path}" "${json_arg}"
    ;;
  operator-snapshot)
    cmd_operator_snapshot "${repo_root}" "${socket_path}"
    ;;
  board-status)
    cmd_board_status "${repo_root}" "${socket_path}"
    ;;
  sessions-status)
    cmd_sessions_status "${repo_root}"
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
  create-child-issue)
    [ -n "${parent_id_arg}" ] || fail "create-child-issue requires --parent-id"
    [ -n "${title_arg:-}" ] || fail "create-child-issue requires --title"
    cmd_create_child_issue "${repo_root}" "${socket_path}" "${parent_id_arg}" "${title_arg}" "${description_arg:-}" "${type_arg:-task}" "${priority_arg:-2}" "${labels_arg:-}"
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
    require_supervisor_alive "${repo_root}"
    cmd_launch_lane "${repo_root}" "${socket_path}" "${issue_id_arg}" "${base_rev_arg}" "${slug_arg}"
    ;;
  dispatch-lane)
    [ -n "${issue_id_arg}" ] || fail "dispatch-lane requires --issue-id"
    require_supervisor_alive "${repo_root}"
    cmd_dispatch_lane "${repo_root}" "${socket_path}" "${issue_id_arg}" "${worker_arg:-codex}" "${mode_arg:-handoff}" "${note_arg}" "${plan_arg:-false}"
    ;;
  autonomous-lane)
    [ -n "${issue_id_arg}" ] || fail "autonomous-lane requires --issue-id"
    require_supervisor_alive "${repo_root}"
    cmd_autonomous_lane "${repo_root}" "${socket_path}" "${issue_id_arg}" "${base_rev_arg:-main}" "${slug_arg}" "${worker_arg:-codex}" "${note_arg}" "${quarantine_arg}" "${plan_arg:-false}"
    ;;
  handoff-lane)
    [ -n "${issue_id_arg}" ] || fail "handoff-lane requires --issue-id"
    [ -n "${revision_arg}" ] || fail "handoff-lane requires --revision"
    require_supervisor_alive "${repo_root}"
    cmd_handoff_lane "${repo_root}" "${socket_path}" "${issue_id_arg}" "${revision_arg}" "${note_arg}"
    ;;
  finish-lane)
    [ -n "${issue_id_arg}" ] || fail "finish-lane requires --issue-id"
    [ -n "${outcome_arg}" ] || fail "finish-lane requires --outcome"
    require_supervisor_alive "${repo_root}"
    cmd_finish_lane "${repo_root}" "${socket_path}" "${issue_id_arg}" "${outcome_arg}" "${note_arg}"
    ;;
  lane-park)
    [ -n "${issue_id_arg}" ] || fail "lane-park requires --issue-id"
    require_supervisor_alive "${repo_root}"
    cmd_lane_park "${repo_root}" "${issue_id_arg}"
    ;;
  lane-abandon)
    [ -n "${issue_id_arg}" ] || fail "lane-abandon requires --issue-id"
    require_supervisor_alive "${repo_root}"
    cmd_lane_abandon "${repo_root}" "${issue_id_arg}"
    ;;
  archive-lane)
    [ -n "${issue_id_arg}" ] || fail "archive-lane requires --issue-id"
    require_supervisor_alive "${repo_root}"
    cmd_archive_lane "${repo_root}" "${socket_path}" "${issue_id_arg}" "${note_arg}"
    ;;
  complete-lane)
    [ -n "${issue_id_arg}" ] || fail "complete-lane requires --issue-id"
    [ -n "${reason_arg}" ] || fail "complete-lane requires --reason"
    require_supervisor_alive "${repo_root}"
    cmd_complete_lane "${repo_root}" "${socket_path}" "${issue_id_arg}" "${revision_arg}" "${reason_arg}" "${outcome_arg:-completed}" "${note_arg}" "${quarantine_arg}" "${plan_arg:-false}"
    ;;
  compact-lane)
    [ -n "${issue_id_arg}" ] || fail "compact-lane requires --issue-id"
    [ -n "${reason_arg}" ] || fail "compact-lane requires --reason"
    require_supervisor_alive "${repo_root}"
    cmd_compact_lane "${repo_root}" "${socket_path}" "${issue_id_arg}" "${revision_arg}" "${reason_arg}" "${outcome_arg:-completed}" "${note_arg}" "${quarantine_arg}" "${force_arg}"
    ;;
  supervisor-attach)
    cmd_supervisor_attach "${repo_root}"
    ;;
  supervisor-start)
    cmd_supervisor_start "${repo_root}"
    ;;
  supervisor-stop)
    cmd_supervisor_stop "${repo_root}" "${force_arg:-false}"
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
