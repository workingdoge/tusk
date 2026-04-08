#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tusk-skill-loop [--checkout PATH] [--tracker-root PATH] [--interval SECONDS] [--] [codex args...]

Watch repo-authored skill sources, rerun the explicit skill contract checks on
change, and restart Codex against the active checkout when validation passes.

This is a fast restart loop, not in-process hot reload. If a skill edit fails
validation, the loop reports the error and waits for the next change instead of
launching a broken session.

Wrapper options:
  --checkout PATH      Active checkout or lane workspace to run Codex from.
  --repo PATH          Alias for --checkout.
  --tracker-root PATH  Canonical tracker root to use instead of auto-detection.
  --interval SECONDS   Poll interval for skill source changes. Default: 1.
  --watch-help         Show this help and exit.

All other arguments are passed through to `tusk-codex` unchanged.
EOF
}

checkout_arg=""
tracker_arg=""
poll_interval="1"
pass_args=()
child_pid=""
child_exit=0
current_signature=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --checkout|--repo)
      if [ "$#" -lt 2 ]; then
        echo "tusk-skill-loop: $1 requires a path argument" >&2
        exit 2
      fi
      checkout_arg="$2"
      shift 2
      ;;
    --tracker-root)
      if [ "$#" -lt 2 ]; then
        echo "tusk-skill-loop: --tracker-root requires a path argument" >&2
        exit 2
      fi
      tracker_arg="$2"
      shift 2
      ;;
    --interval)
      if [ "$#" -lt 2 ]; then
        echo "tusk-skill-loop: --interval requires a value" >&2
        exit 2
      fi
      poll_interval="$2"
      shift 2
      ;;
    --watch-help)
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

export TUSK_PATHS_SH="${TUSK_PATHS_SH:?tusk-skill-loop requires TUSK_PATHS_SH}"
# shellcheck disable=SC1090
source "$TUSK_PATHS_SH"

checkout_root="$(tusk_resolve_checkout_root "${checkout_arg:-}")"
if [ -n "${tracker_arg}" ]; then
  tracker_root="$(tusk_resolve_tracker_root "${tracker_arg}")"
else
  tracker_root="$(tusk_resolve_tracker_root)"
fi
tusk_export_runtime_roots "$checkout_root" "$tracker_root"

watch_root="$checkout_root/.agents/skills"
if [ ! -d "$watch_root" ]; then
  echo "tusk-skill-loop: missing skill source directory: $watch_root" >&2
  exit 1
fi

compute_watch_signature() {
  local output=""

  output="$(
    find "$watch_root" -type f -print | LC_ALL=C sort | while IFS= read -r path; do
      cksum "$path"
    done | cksum
  )"

  if [ -n "$output" ]; then
    printf '%s\n' "$output" | awk '{print $1}'
  else
    printf 'empty\n'
  fi
}

stop_child() {
  local pid="${child_pid:-}"

  if [ -z "$pid" ]; then
    return 0
  fi

  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null || true
    wait "$pid" || true
  fi

  child_pid=""
}

validate_skills() {
  "${TUSK_SKILL_CONTRACT_CHECK_BIN:?tusk-skill-loop requires TUSK_SKILL_CONTRACT_CHECK_BIN}" --repo "$checkout_root"
}

launch_codex() {
  if [ "${#pass_args[@]}" -gt 0 ]; then
    "${TUSK_CODEX_LAUNCHER:?tusk-skill-loop requires TUSK_CODEX_LAUNCHER}" \
      --checkout "$checkout_root" \
      --tracker-root "$tracker_root" \
      -- "${pass_args[@]}" &
  else
    "${TUSK_CODEX_LAUNCHER:?tusk-skill-loop requires TUSK_CODEX_LAUNCHER}" \
      --checkout "$checkout_root" \
      --tracker-root "$tracker_root" &
  fi
  child_pid="$!"
}

trap 'stop_child' EXIT INT TERM

last_signature="$(compute_watch_signature)"

if validate_skills; then
  echo "tusk-skill-loop: skill contract ok; launching Codex from $checkout_root"
  launch_codex
else
  echo "tusk-skill-loop: validation failed; waiting for the next skill edit before launch" >&2
fi

while :; do
  child_exit=0
  current_signature=""

  sleep "$poll_interval"
  current_signature="$(compute_watch_signature)"

  if [ "$current_signature" != "$last_signature" ]; then
    last_signature="$current_signature"
    if [ -n "${child_pid:-}" ]; then
      echo "tusk-skill-loop: skill edit detected; stopping the current session"
      stop_child
    else
      echo "tusk-skill-loop: skill edit detected; re-running validation"
    fi

    if validate_skills; then
      echo "tusk-skill-loop: skill contract ok; restarting Codex"
      launch_codex
    else
      echo "tusk-skill-loop: validation failed; fix the skill and save again to retry" >&2
    fi
    continue
  fi

  if [ -n "${child_pid:-}" ] && ! kill -0 "$child_pid" 2>/dev/null; then
    wait "$child_pid" || child_exit="$?"
    child_pid=""
    exit "$child_exit"
  fi
done
