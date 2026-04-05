#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" || $# -lt 4 ]]; then
  cat <<'HELP'
Usage: probe-config-path.sh <flake-ref> <domain> <name> <config-path>

Domains:
  nixos
  darwin
  home

Examples:
  probe-config-path.sh . nixos laptop networking.hostName
  probe-config-path.sh . darwin mac system.primaryUser
  probe-config-path.sh . home alice home.username

This evaluates a realized config attribute path from a flake output as JSON.
It is for realized values, not definition provenance.
HELP
  exit 0
fi

if ! command -v nix >/dev/null 2>&1; then
  echo "probe-config-path.sh: nix is not installed or not on PATH" >&2
  exit 127
fi

flake_ref="$1"
domain="$2"
name="$3"
config_path="$4"

case "$domain" in
  nixos)
    root="nixosConfigurations"
    ;;
  darwin|nix-darwin)
    root="darwinConfigurations"
    ;;
  home|home-manager|homeManager)
    root="homeConfigurations"
    ;;
  *)
    echo "probe-config-path.sh: unknown domain '$domain' (expected nixos, darwin, or home)" >&2
    exit 2
    ;;
esac

installable="${flake_ref}#${root}.${name}.config.${config_path}"

exec nix eval --json "$installable"
