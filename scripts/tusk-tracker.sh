#!/usr/bin/env bash
set -euo pipefail

program_name="${0##*/}"
real_bd="${TUSK_TRACKER_REAL_BD:?TUSK_TRACKER_REAL_BD is required}"

usage() {
  cat <<'EOF'
Usage:
  tusk-tracker ready [--repo PATH]
  tusk-tracker status [--repo PATH]
  tusk-tracker issue claim ISSUE_ID [--repo PATH]
  tusk-tracker issue close ISSUE_ID --reason REASON [--repo PATH]
  tusk-tracker backend show [--repo PATH]
  tusk-tracker backend status [--repo PATH]
  tusk-tracker backend test [--repo PATH]
  tusk-tracker backend start [--repo PATH]
  tusk-tracker backend configure [--repo PATH] [--host HOST] [--port PORT] [--data-dir PATH]

Commands:
  ready              Print the current ready issue set as JSON.
  status             Print the current tracker status summary as JSON.
  issue claim        Claim one issue and print the updated issue JSON.
  issue close        Close one issue and print the updated issue JSON.
  backend show       Print the current tracker backend configuration as JSON.
  backend status     Print the current tracker backend status as JSON.
  backend test       Test the current tracker backend connection as JSON.
  backend start      Start the current tracker backend.
  backend configure  Apply backend host, port, and data-dir settings.
EOF
}

fail() {
  echo "${program_name}: $*" >&2
  exit 1
}

default_repo_root() {
  if git rev-parse --show-toplevel >/dev/null 2>&1; then
    git rev-parse --show-toplevel
    return
  fi

  if [ -n "${BEADS_WORKSPACE_ROOT:-}" ]; then
    (
      cd "${BEADS_WORKSPACE_ROOT}"
      git rev-parse --show-toplevel 2>/dev/null || pwd
    )
    return
  fi

  if [ -n "${DEVENV_ROOT:-}" ]; then
    (
      cd "${DEVENV_ROOT}"
      git rev-parse --show-toplevel 2>/dev/null || pwd
    )
    return
  fi

  pwd
}

resolve_repo_root() {
  local repo_arg="${1:-}"

  if [ -n "${repo_arg}" ]; then
    (
      cd "${repo_arg}"
      git rev-parse --show-toplevel 2>/dev/null || pwd
    )
    return
  fi

  default_repo_root
}

run_in_repo() {
  local repo_root="$1"
  shift

  (
    cd "${repo_root}"
    export BEADS_WORKSPACE_ROOT="${repo_root}"
    export DEVENV_ROOT="${repo_root}"
    "$@"
  )
}

cmd_ready() {
  local repo_root="$1"
  run_in_repo "${repo_root}" "${real_bd}" ready --json
}

cmd_status() {
  local repo_root="$1"
  run_in_repo "${repo_root}" "${real_bd}" status --json
}

cmd_issue_claim() {
  local repo_root="$1"
  local issue_id="${2:-}"

  [ -n "${issue_id}" ] || fail "issue claim requires ISSUE_ID"
  run_in_repo "${repo_root}" "${real_bd}" update "${issue_id}" --claim --json
}

cmd_issue_close() {
  local repo_root="$1"
  local issue_id="${2:-}"
  local reason="${3:-}"

  [ -n "${issue_id}" ] || fail "issue close requires ISSUE_ID"
  [ -n "${reason}" ] || fail "issue close requires --reason"
  run_in_repo "${repo_root}" "${real_bd}" close "${issue_id}" --reason "${reason}" --json
}

cmd_backend_show() {
  local repo_root="$1"
  run_in_repo "${repo_root}" "${real_bd}" dolt show --json
}

cmd_backend_status() {
  local repo_root="$1"
  run_in_repo "${repo_root}" "${real_bd}" dolt status --json
}

cmd_backend_test() {
  local repo_root="$1"
  run_in_repo "${repo_root}" "${real_bd}" dolt test --json
}

cmd_backend_start() {
  local repo_root="$1"
  run_in_repo "${repo_root}" "${real_bd}" dolt start
}

cmd_backend_configure() {
  local repo_root="$1"
  shift
  local host=""
  local port=""
  local data_dir=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --host)
        [ "$#" -ge 2 ] || fail "--host requires a value"
        host="$2"
        shift 2
        ;;
      --port)
        [ "$#" -ge 2 ] || fail "--port requires a value"
        port="$2"
        shift 2
        ;;
      --data-dir)
        [ "$#" -ge 2 ] || fail "--data-dir requires a value"
        data_dir="$2"
        shift 2
        ;;
      *)
        fail "unknown backend configure argument: $1"
        ;;
    esac
  done

  if [ -z "${host}" ] && [ -z "${port}" ] && [ -z "${data_dir}" ]; then
    fail "backend configure requires at least one of --host, --port, or --data-dir"
  fi

  if [ -n "${host}" ]; then
    run_in_repo "${repo_root}" "${real_bd}" dolt set host "${host}" >/dev/null
  fi
  if [ -n "${port}" ]; then
    run_in_repo "${repo_root}" "${real_bd}" dolt set port "${port}" >/dev/null
  fi
  if [ -n "${data_dir}" ]; then
    run_in_repo "${repo_root}" "${real_bd}" dolt set data-dir "${data_dir}" >/dev/null
  fi
}

main() {
  local repo_arg=""
  local argv=()
  local repo_root=""
  local command=""
  local subcommand=""
  local issue_id=""
  local reason=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo)
        [ "$#" -ge 2 ] || fail "--repo requires a value"
        repo_arg="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        argv+=("$1")
        shift
        ;;
    esac
  done

  [ "${#argv[@]}" -gt 0 ] || {
    usage
    exit 1
  }

  set -- "${argv[@]}"
  repo_root="$(resolve_repo_root "${repo_arg}")"
  command="$1"

  case "${command}" in
    ready)
      cmd_ready "${repo_root}"
      ;;
    status)
      cmd_status "${repo_root}"
      ;;
    issue)
      subcommand="${2:-}"
      [ -n "${subcommand}" ] || fail "issue requires a subcommand"
      shift 2
      case "${subcommand}" in
        claim)
          issue_id="${1:-}"
          [ "$#" -eq 1 ] || fail "issue claim requires exactly one ISSUE_ID"
          cmd_issue_claim "${repo_root}" "${issue_id}"
          ;;
        close)
          issue_id="${1:-}"
          shift
          [ -n "${issue_id}" ] || fail "issue close requires ISSUE_ID"

          while [ "$#" -gt 0 ]; do
            case "$1" in
              --reason|-r)
                [ "$#" -ge 2 ] || fail "issue close requires a value for --reason"
                reason="$2"
                shift 2
                ;;
              *)
                fail "unknown issue close argument: $1"
                ;;
            esac
          done

          cmd_issue_close "${repo_root}" "${issue_id}" "${reason}"
          ;;
        *)
          fail "unknown issue subcommand: ${subcommand}"
          ;;
      esac
      ;;
    backend)
      subcommand="${2:-}"
      [ -n "${subcommand}" ] || fail "backend requires a subcommand"
      shift 2
      case "${subcommand}" in
        show)
          cmd_backend_show "${repo_root}"
          ;;
        status)
          cmd_backend_status "${repo_root}"
          ;;
        test)
          cmd_backend_test "${repo_root}"
          ;;
        start)
          cmd_backend_start "${repo_root}"
          ;;
        configure)
          cmd_backend_configure "${repo_root}" "$@"
          ;;
        *)
          fail "unknown backend subcommand: ${subcommand}"
          ;;
      esac
      ;;
    *)
      fail "unknown command: ${command}"
      ;;
  esac
}

main "$@"
