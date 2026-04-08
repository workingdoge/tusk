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

cd "$checkout_root"
if [ "${#pass_args[@]}" -gt 0 ]; then
  exec "$claude_bin" "${pass_args[@]}"
fi

exec "$claude_bin"
