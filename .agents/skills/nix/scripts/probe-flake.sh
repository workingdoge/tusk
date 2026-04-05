#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<'HELP'
Usage: probe-flake.sh [flake-ref] [extra nix flake show args...]

Examples:
  probe-flake.sh .
  probe-flake.sh . --all-systems
  probe-flake.sh github:NixOS/nixpkgs/nixos-25.05

Emits machine-readable flake topology using:
  nix flake show --json
HELP
  exit 0
fi

flake_ref="${1:-.}"
shift || true

if ! command -v nix >/dev/null 2>&1; then
  echo "probe-flake.sh: nix is not installed or not on PATH" >&2
  exit 127
fi

exec nix flake show --json "$flake_ref" "$@"
