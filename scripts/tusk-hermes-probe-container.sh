#!/usr/bin/env bash
set -euo pipefail

require_env() {
  local name="$1"

  if [ -z "${!name:-}" ]; then
    printf 'tusk-hermes-probe-container: missing required env: %s\n' "${name}" >&2
    exit 1
  fi
}

require_env TUSK_HERMES_INSTALLER_URL
require_env TUSK_HERMES_BRANCH
require_env TUSK_HERMES_PROBE_COMMAND
require_env HERMES_INSTALL_DIR

mkdir -p "${HOME}" "${HOME}/.local/bin" "${HOME}/.cache" /artifacts
export PATH="${HOME}/.local/bin:${PATH}"
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

if command -v apt-get >/dev/null 2>&1; then
  (
    set -x
    apt-get update
    apt-get install -y ca-certificates curl git xz-utils build-essential python3-dev libffi-dev ripgrep
  ) >"/artifacts/system-setup.log" 2>&1
fi

curl -fsSL "${TUSK_HERMES_INSTALLER_URL}" -o /artifacts/hermes-install.sh
chmod 0555 /artifacts/hermes-install.sh

(
  set -x
  /artifacts/hermes-install.sh --skip-setup --branch "${TUSK_HERMES_BRANCH}" --dir "${HERMES_INSTALL_DIR}"
) >"/artifacts/install.log" 2>&1

command -v hermes >"/artifacts/hermes-path.txt"
printf '%s\n' "${HERMES_INSTALL_DIR}" >"/artifacts/install-dir.txt"

if [ -d "${HERMES_INSTALL_DIR}/.git" ]; then
  (
    cd "${HERMES_INSTALL_DIR}"
    git rev-parse HEAD
  ) >"/artifacts/upstream-revision.txt"
fi

(
  set -x
  bash -c "${TUSK_HERMES_PROBE_COMMAND}"
) >"/artifacts/probe.log" 2>&1
