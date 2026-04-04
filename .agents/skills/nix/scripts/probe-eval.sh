#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 1 ]]; then
  cat <<'HELP'
Usage: probe-eval.sh <installable> [extra nix eval args...]

Examples:
  probe-eval.sh '.#packages.x86_64-linux.hello'
  probe-eval.sh '.#nixosConfigurations.myhost.config.networking.hostName'
  probe-eval.sh '.#checks.x86_64-linux.some-check' --show-trace

By default this uses:
  nix eval --json

Note:
  --json fails for values that are not representable as JSON, such as functions.
  When that happens, narrow the attribute path further or use nix repl.
HELP
  exit 0
fi

if ! command -v nix >/dev/null 2>&1; then
  echo "probe-eval.sh: nix is not installed or not on PATH" >&2
  exit 127
fi

installable="$1"
shift || true

exec nix eval --json "$installable" "$@"
