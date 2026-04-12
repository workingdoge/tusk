#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tusk-bridge-conformance-check [--repo PATH]

Verify the repo-owned bridge adjunct bundle checksum manifest and run the
Rust bridge adapter conformance tests against the imported fixture surface.
EOF
}

repo_arg=""

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
