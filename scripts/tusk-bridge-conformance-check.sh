#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tusk-bridge-conformance-check [--repo PATH] [--bridge-flake FLAKE_REF]

Verify the repo-owned bridge adjunct bundle checksum manifest and run the
Rust bridge adapter conformance tests against the imported fixture surface.

When --bridge-flake is provided, also verify the external bridge flake edge
contract by running:

- bridge-conformance-check
- bridge-property-check
- reference-planner -- --help
EOF
}

repo_arg=""
bridge_flake_arg=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      if [ "$#" -lt 2 ]; then
        echo "tusk-bridge-conformance-check: --repo requires a path argument" >&2
        exit 2
      fi
      repo_arg="$2"
      shift 2
      ;;
    --bridge-flake)
      if [ "$#" -lt 2 ]; then
        echo "tusk-bridge-conformance-check: --bridge-flake requires a flake reference" >&2
        exit 2
      fi
      bridge_flake_arg="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "tusk-bridge-conformance-check: unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

export TUSK_PATHS_SH="${TUSK_PATHS_SH:?tusk-bridge-conformance-check requires TUSK_PATHS_SH}"
# shellcheck disable=SC1090
source "$TUSK_PATHS_SH"

checkout_root="$(tusk_resolve_checkout_root "${repo_arg:-}")"
tracker_root="$(tusk_resolve_tracker_root "${repo_arg:-}")"
tusk_export_runtime_roots "$checkout_root" "$tracker_root"
cd "$checkout_root"

adjunct_root="$checkout_root/design/adjuncts/bridge-adapter"
cargo_manifest="$checkout_root/crates/tusk-bridge-adapter/Cargo.toml"

(
  cd "$adjunct_root"
  sha256sum --check --strict --quiet SHA256SUMS.txt
)

cargo test --manifest-path "$cargo_manifest" --locked

if [ -n "$bridge_flake_arg" ]; then
  nix run "$bridge_flake_arg"#bridge-conformance-check
  nix run "$bridge_flake_arg"#bridge-property-check
  nix run "$bridge_flake_arg"#reference-planner -- --help >/dev/null
fi
