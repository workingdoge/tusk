#!/usr/bin/env bash
set -euo pipefail

program_name="${0##*/}"
real_bd="${TUSK_TRACKER_REAL_BD:?TUSK_TRACKER_REAL_BD is required}"
paths_sh="${TUSK_PATHS_SH:?TUSK_PATHS_SH is required}"

source "${paths_sh}"

usage() {
  cat <<'EOF'
Usage:
  tusk-tracker ready [--repo PATH]
  tusk-tracker status [--repo PATH]
  tusk-tracker issue show ISSUE_ID [--repo PATH]
  tusk-tracker issue create-child PARENT_ID --issue-id ISSUE_ID --title TITLE [--description TEXT] [--type TYPE] [--priority PRIORITY] [--labels CSV] [--metadata JSON] [--repo PATH]
  tusk-tracker issue claim ISSUE_ID [--repo PATH]
  tusk-tracker issue close ISSUE_ID --reason REASON [--repo PATH]
  tusk-tracker issues board [--repo PATH]
  tusk-tracker backend show [--repo PATH]
  tusk-tracker backend status [--repo PATH]
  tusk-tracker backend test [--repo PATH]
  tusk-tracker backend start [--repo PATH]
  tusk-tracker backend configure [--repo PATH] [--host HOST] [--port PORT] [--data-dir PATH]

Commands:
  ready              Print the current ready issue set as JSON.
  status             Print the current tracker status summary as JSON.
  issue show         Show one issue and print the issue JSON.
  issue create-child Create one child issue with an explicit child id and print the issue JSON.
  issue claim        Claim one issue and print the updated issue JSON.
  issue close        Close one issue and print the updated issue JSON.
  issues board       Print machine-readable board issue buckets as JSON.
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

resolve_repo_root() {
  local repo_arg="${1:-}"
  tusk_resolve_tracker_root "${repo_arg}"
}

run_in_repo() {
  local repo_root="$1"
  shift

  (
    cd "${repo_root}"
    tusk_export_runtime_roots "${repo_root}" "${repo_root}"
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

cmd_issue_show() {
  local repo_root="$1"
  local issue_id="${2:-}"

  [ -n "${issue_id}" ] || fail "issue show requires ISSUE_ID"
  run_in_repo "${repo_root}" "${real_bd}" show "${issue_id}" --json
}

cmd_issue_claim() {
  local repo_root="$1"
  local issue_id="${2:-}"

  [ -n "${issue_id}" ] || fail "issue claim requires ISSUE_ID"
  run_in_repo "${repo_root}" "${real_bd}" update "${issue_id}" --claim --json
}

cmd_issue_create_child() {
  local repo_root="$1"
  local parent_id="${2:-}"
  local issue_id="${3:-}"
  local title="${4:-}"
  local description="${5:-}"
  local issue_type="${6:-task}"
  local priority="${7:-2}"
  local labels="${8:-}"
  local metadata="${9:-}"
  local -a args=()

  [ -n "${parent_id}" ] || fail "issue create-child requires PARENT_ID"
  [ -n "${issue_id}" ] || fail "issue create-child requires --issue-id"
  [ -n "${title}" ] || fail "issue create-child requires --title"

  args=(
    create
    --id "${issue_id}"
    --title "${title}"
    --type "${issue_type}"
    --priority "${priority}"
    --deps "parent-child:${parent_id}"
    --json
  )
  if [ -n "${description}" ]; then
    args+=(--description "${description}")
  fi
  if [ -n "${labels}" ]; then
    args+=(--labels "${labels}")
  fi
  if [ -n "${metadata}" ]; then
    args+=(--metadata "${metadata}")
  fi

  run_in_repo "${repo_root}" "${real_bd}" "${args[@]}"
}

cmd_issue_close() {
  local repo_root="$1"
  local issue_id="${2:-}"
  local reason="${3:-}"

  [ -n "${issue_id}" ] || fail "issue close requires ISSUE_ID"
  [ -n "${reason}" ] || fail "issue close requires --reason"
  run_in_repo "${repo_root}" "${real_bd}" close "${issue_id}" --reason "${reason}" --json
}

cmd_issues_board() {
  local repo_root="$1"
  local export_output=""
  local blocked_output=""

  export_output="$(run_in_repo "${repo_root}" "${real_bd}" export)"
  blocked_output="$(run_in_repo "${repo_root}" "${real_bd}" blocked --json)"

  jq -Rsc \
    --argjson blocked "${blocked_output}" \
    '
      def issue_view:
        {
          id: .id,
          title: .title,
          status: (.status // null)
        };

      split("\n")
      | map(select(length > 0) | fromjson)
      | {
          claimed_issues: (
            map(select(.status == "in_progress") | issue_view)
            | sort_by(.id)
          ),
          deferred_issues: (
            map(select(.status == "deferred") | issue_view)
            | sort_by(.id)
          ),
          blocked_issues: (
            ($blocked // [])
            | map(issue_view)
            | sort_by(.id)
          )
        }
    ' <<<"${export_output}"
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
  local scope=""

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
        show)
          issue_id="${1:-}"
          [ "$#" -eq 1 ] || fail "issue show requires exactly one ISSUE_ID"
          cmd_issue_show "${repo_root}" "${issue_id}"
          ;;
        create-child)
          local parent_id=""
          local child_issue_id=""
          local title=""
          local description=""
          local issue_type="task"
          local priority="2"
          local labels=""
          local metadata=""

          parent_id="${1:-}"
          shift
          [ -n "${parent_id}" ] || fail "issue create-child requires PARENT_ID"

          while [ "$#" -gt 0 ]; do
            case "$1" in
              --issue-id)
                [ "$#" -ge 2 ] || fail "issue create-child requires a value for --issue-id"
                child_issue_id="$2"
                shift 2
                ;;
              --title)
                [ "$#" -ge 2 ] || fail "issue create-child requires a value for --title"
                title="$2"
                shift 2
                ;;
              --description)
                [ "$#" -ge 2 ] || fail "issue create-child requires a value for --description"
                description="$2"
                shift 2
                ;;
              --type)
                [ "$#" -ge 2 ] || fail "issue create-child requires a value for --type"
                issue_type="$2"
                shift 2
                ;;
              --priority)
                [ "$#" -ge 2 ] || fail "issue create-child requires a value for --priority"
                priority="$2"
                shift 2
                ;;
              --labels)
                [ "$#" -ge 2 ] || fail "issue create-child requires a value for --labels"
                labels="$2"
                shift 2
                ;;
              --metadata)
                [ "$#" -ge 2 ] || fail "issue create-child requires a value for --metadata"
                metadata="$2"
                shift 2
                ;;
              *)
                fail "unknown issue create-child argument: $1"
                ;;
            esac
          done

          cmd_issue_create_child "${repo_root}" "${parent_id}" "${child_issue_id}" "${title}" "${description}" "${issue_type}" "${priority}" "${labels}" "${metadata}"
          ;;
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
    issues)
      scope="${2:-}"
      [ -n "${scope}" ] || fail "issues requires a subcommand"
      shift 2
      case "${scope}" in
        board)
          [ "$#" -eq 0 ] || fail "issues board does not accept positional arguments"
          cmd_issues_board "${repo_root}"
          ;;
        *)
          fail "unknown issues subcommand: ${scope}"
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
