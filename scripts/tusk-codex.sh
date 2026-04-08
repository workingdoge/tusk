#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tusk-codex [--checkout PATH] [--tracker-root PATH] [--] [codex args...]

Launch Codex against an explicit checkout or lane workspace while preserving the
canonical tracker root for shared tracker state.

Wrapper options:
  --checkout PATH      Active checkout or lane workspace to run Codex from.
  --repo PATH          Alias for --checkout.
  --tracker-root PATH  Canonical tracker root to use instead of auto-detection.
  --launcher-help      Show this wrapper help and exit.

All other arguments are passed through to Codex unchanged. Use `--` to separate
wrapper options from Codex flags when needed.
EOF
}

checkout_arg=""
tracker_arg=""
pass_args=()

while [ "$#" -gt 0 ]; do
  case "$1" in
    --checkout|--repo)
      if [ "$#" -lt 2 ]; then
        echo "tusk-codex: $1 requires a path argument" >&2
        exit 2
      fi
      checkout_arg="$2"
      shift 2
      ;;
    --tracker-root)
      if [ "$#" -lt 2 ]; then
        echo "tusk-codex: --tracker-root requires a path argument" >&2
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

export TUSK_PATHS_SH="${TUSK_PATHS_SH:?tusk-codex requires TUSK_PATHS_SH}"
# shellcheck disable=SC1090
source "$TUSK_PATHS_SH"

checkout_root="$(tusk_resolve_checkout_root "${checkout_arg:-}")"
if [ -n "${tracker_arg}" ]; then
  tracker_root="$(tusk_resolve_tracker_root "${tracker_arg}")"
else
  tracker_root="$(tusk_resolve_tracker_root)"
fi
tusk_export_runtime_roots "$checkout_root" "$tracker_root"

export CODEX_HOME="$checkout_root/.codex"
sh "${TUSK_CODEX_BOOTSTRAP_SH:?tusk-codex requires TUSK_CODEX_BOOTSTRAP_SH}" "$checkout_root" ".codex"

if [ -d "$tracker_root/.beads" ] && [ -n "${TUSK_REAL_BD:-}" ]; then
  (
    cd "$tracker_root"
    "$TUSK_REAL_BD" ready --json >/dev/null 2>&1 || true
  )
fi

cd "$checkout_root"
if [ "${#pass_args[@]}" -gt 0 ]; then
  exec "${TUSK_REAL_CODEX:?tusk-codex requires TUSK_REAL_CODEX}" "${pass_args[@]}"
fi

exec "${TUSK_REAL_CODEX:?tusk-codex requires TUSK_REAL_CODEX}"
