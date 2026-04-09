#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tusk-claude [--checkout PATH] [--tracker-root PATH] [--] [claude args...]

Launch Claude Code against an explicit checkout or lane workspace so repo-local
.claude/skills follows the active checkout while tracker state stays rooted at
the canonical repo.

Wrapper options:
  --checkout PATH      Active checkout or lane workspace to run Claude from.
  --repo PATH          Alias for --checkout.
  --tracker-root PATH  Canonical tracker root to use instead of auto-detection.
  --launcher-help      Show this wrapper help and exit.

All other arguments are passed through to Claude unchanged. Use `--` to
separate wrapper options from Claude flags when needed.
EOF
}

checkout_arg=""
tracker_arg=""
pass_args=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --checkout|--repo)
      if [ "$#" -lt 2 ]; then
        echo "tusk-claude: $1 requires a path argument" >&2
        exit 2
      fi
      checkout_arg="$2"
      shift 2
      ;;
    --tracker-root)
      if [ "$#" -lt 2 ]; then
        echo "tusk-claude: --tracker-root requires a path argument" >&2
        exit 2
      fi
      tracker_arg="$2"
      shift 2
      ;;
    --launcher-help)
      usage
      exit 0
      ;;
    --)
      shift
      pass_args+=("$@")
      break
      ;;
    *)
      pass_args+=("$1")
      shift
      ;;
  esac
done

export TUSK_PATHS_SH="${TUSK_PATHS_SH:?tusk-claude requires TUSK_PATHS_SH}"
# shellcheck disable=SC1090
source "$TUSK_PATHS_SH"

checkout_root="$(tusk_resolve_checkout_root "${checkout_arg:-}")"
if [ -n "${tracker_arg}" ]; then
  tracker_root="$(tusk_resolve_tracker_root "${tracker_arg}")"
else
  tracker_root="$(tusk_resolve_tracker_root)"
fi
tusk_export_runtime_roots "$checkout_root" "$tracker_root"

if [ -d "$tracker_root/.beads" ] && [ -n "${TUSK_REAL_BD:-}" ]; then
  (
    cd "$tracker_root"
    "$TUSK_REAL_BD" ready --json >/dev/null 2>&1 || true
  )
fi

claude_bin="${TUSK_REAL_CLAUDE:-claude}"
if ! command -v "$claude_bin" >/dev/null 2>&1; then
  echo "tusk-claude: missing Claude Code binary '$claude_bin' in PATH" >&2
  echo "Install Claude Code or set TUSK_REAL_CLAUDE to the executable you want to use." >&2
  exit 1
fi

session_now_iso8601() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

session_upsert() {
  local status="$1"
  local heartbeat_at="$2"
  local finished_at="$3"
  local payload=""

  payload="$(
    jq -cn \
      --arg id "${session_id}" \
      --arg runtime_kind "claude" \
      --arg launcher "tusk-claude" \
      --arg checkout_root "${checkout_root}" \
      --arg tracker_root "${tracker_root}" \
      --arg launched_at "${session_launched_at}" \
      --arg heartbeat_at "${heartbeat_at}" \
      --arg finished_at "${finished_at}" \
      --arg status "${status}" \
      --argjson pid "${session_pid}" \
      '{
        id: $id,
        runtime_kind: $runtime_kind,
        launcher: $launcher,
        checkout_root: $checkout_root,
        tracker_root: $tracker_root,
        launched_at: $launched_at,
        heartbeat_at: (if $heartbeat_at == "" then null else $heartbeat_at end),
        finished_at: (if $finished_at == "" then null else $finished_at end),
        status: $status,
        pid: $pid
      }'
  )"
  "${TUSKD_CORE_BIN}" session-state upsert --repo "${tracker_root}" --session-json "${payload}" >/dev/null 2>&1 || true
}

start_session_tracking() {
  local interval="${TUSK_SESSION_HEARTBEAT_SECONDS:-15}"

  [ -d "$tracker_root/.beads" ] || return 0
  [ -n "${TUSKD_CORE_BIN:-}" ] || return 0
  command -v jq >/dev/null 2>&1 || return 0

  case "${interval}" in
    ''|*[!0-9]*)
      interval=15
      ;;
  esac
  if [ "${interval}" -le 0 ]; then
    interval=15
  fi

  session_pid="$$"
  session_id="claude-${session_pid}-$(date -u +%Y%m%dT%H%M%SZ)"
  session_launched_at="$(session_now_iso8601)"
  session_upsert "running" "${session_launched_at}" ""

  (
    while kill -0 "${session_pid}" >/dev/null 2>&1; do
      session_upsert "running" "$(session_now_iso8601)" ""
      sleep "${interval}"
    done
    session_upsert "exited" "$(session_now_iso8601)" "$(session_now_iso8601)"
  ) >/dev/null 2>&1 &
}

session_id=""
session_pid=""
session_launched_at=""
start_session_tracking

cd "$checkout_root"
if [ "${#pass_args[@]}" -gt 0 ]; then
  exec "$claude_bin" "${pass_args[@]}"
fi

exec "$claude_bin"
