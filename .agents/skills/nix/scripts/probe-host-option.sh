#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 3 ]]; then
  cat <<'HELP'
Usage: probe-host-option.sh <flake-ref> <host> <option-path>

Compatibility wrapper around:
  probe-config-path.sh <flake-ref> nixos <host> <option-path>

Example:
  probe-host-option.sh . laptop networking.hostName
HELP
  exit 0
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${script_dir}/probe-config-path.sh" "$1" nixos "$2" "$3"
