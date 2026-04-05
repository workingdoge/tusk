#!/usr/bin/env bash
set -euo pipefail

program_name="${0##*/}"

usage() {
  cat <<'EOF'
Usage:
  tuskd-transition-tests [--source-repo PATH] [--base-rev REV] [--keep-temp]

Options:
  --source-repo PATH   Source repo or workspace to replay into an isolated temp clone.
                       Defaults to the current working directory.
  --base-rev REV       Base revision used for the replay patch. Defaults to tusk-flake.
  --keep-temp          Keep the temp clone even on success.
  --help               Show this help.
EOF
}

fail() {
  echo "${program_name}: $*" >&2
  exit 1
}

note() {
  echo "${program_name}: $*" >&2
}

resolve_repo_root() {
  local path_arg="${1:-.}"
  (
    cd "${path_arg}"
    pwd -P
  )
}

resolve_git_root() {
  local path_arg="$1"
  (
    cd "${path_arg}"
    git rev-parse --show-toplevel
  )
}

capture_command() {
  local output_var="$1"
  local status_var="$2"
  shift 2
  local output=""
  local status=0

  set +e
  output="$("$@" 2>&1)"
  status=$?
  set -e

  printf -v "${output_var}" '%s' "${output}"
  printf -v "${status_var}" '%s' "${status}"
}

run_cli_json() {
  local output_var="$1"
  local status_var="$2"
  shift 2
  capture_command "${output_var}" "${status_var}" "$@"
  if [ -n "${!output_var}" ]; then
    printf '%s' "${!output_var}" | jq -e . >/dev/null 2>&1 || fail "command did not return valid JSON: $*"$'\n'"${!output_var}"
  fi
}

assert_status() {
  local actual="$1"
  local expected="$2"
  local context="$3"

  [ "${actual}" = "${expected}" ] || fail "${context}: expected exit ${expected}, got ${actual}"
}

assert_json_value() {
  local json="$1"
  local filter="$2"
  local expected="$3"
  local context="$4"
  local actual=""

  actual="$(jq -r "${filter}" <<<"${json}")"
  [ "${actual}" = "${expected}" ] || fail "${context}: expected ${expected}, got ${actual}"$'\n'"${json}"
}

assert_json_jq() {
  local json="$1"
  local context="$2"
  shift 2

  jq -e "$@" >/dev/null <<<"${json}" || fail "${context}"$'\n'"${json}"
}

assert_file_missing() {
  local path="$1"
  local context="$2"

  [ ! -e "${path}" ] || fail "${context}: ${path} still exists"
}

create_issue() {
  local repo_root="$1"
  local title="$2"
  local create_json=""
  local create_status=0
  local issue_id=""

  run_cli_json create_json create_status \
    bd create \
      --title "${title}" \
      --description "Disposable issue for automated tuskd transition tests." \
      --type task \
      --priority 2 \
      --json
  assert_status "${create_status}" "0" "bd create"

  issue_id="$(jq -r 'if type == "array" then .[0].id // "" else .id // "" end' <<<"${create_json}")"
  [ -n "${issue_id}" ] || fail "failed to extract issue id from create output"$'\n'"${create_json}"
  printf '%s\n' "${issue_id}"
}

current_revision() {
  local repo_root="$1"
  local revision=""

  revision="$(
    jj --repository "${repo_root}" log -r @ --no-graph -T 'commit_id ++ "\n"' \
      | awk 'NF { print; exit }'
  )"
  [ -n "${revision}" ] || fail "failed to resolve current revision"
  printf '%s\n' "${revision}"
}

receipts_path() {
  local repo_root="$1"
  printf '%s/.beads/tuskd/receipts.jsonl\n' "${repo_root}"
}

lanes_path() {
  local repo_root="$1"
  printf '%s/.beads/tuskd/lanes.json\n' "${repo_root}"
}

receipt_count() {
  local repo_root="$1"
  local issue_id="$2"
  local kind="$3"
  local path=""

  path="$(receipts_path "${repo_root}")"
  if [ ! -f "${path}" ]; then
    printf '0\n'
    return
  fi

  jq -Rsc \
    --arg issue_id "${issue_id}" \
    --arg kind "${kind}" \
    '
      split("\n")
      | map(select(length > 0) | fromjson?)
      | map(select(.kind == $kind and ((.payload.issue_id // "") == $issue_id)))
      | length
    ' <"${path}"
}

lane_count() {
  local repo_root="$1"
  local issue_id="$2"
  local path=""

  path="$(lanes_path "${repo_root}")"
  if [ ! -f "${path}" ]; then
    printf '0\n'
    return
  fi

  jq -r --arg issue_id "${issue_id}" '[.[] | select(.issue_id == $issue_id)] | length' "${path}"
}

forget_and_remove_workspace() {
  local repo_root="$1"
  local workspace_name="$2"
  local workspace_path="$3"

  jj --repository "${repo_root}" workspace forget "${workspace_name}" >/dev/null
  rm -rf -- "${workspace_path}"
}

wait_for_socket() {
  local socket_path="$1"
  local attempts=0

  while [ "${attempts}" -lt 50 ]; do
    if [ -S "${socket_path}" ]; then
      return 0
    fi
    sleep 0.1
    attempts=$((attempts + 1))
  done

  fail "timed out waiting for socket ${socket_path}"
}

run_query_json() {
  local output_var="$1"
  shift
  local output=""
  local status=0

  capture_command output status tuskd query "$@"
  assert_status "${status}" "0" "tuskd query"
  printf -v "${output_var}" '%s' "${output}"
  printf '%s' "${output}" | jq -e . >/dev/null 2>&1 || fail "query did not return valid JSON"$'\n'"${output}"
}

test_lifecycle_guards() {
  local repo_root="$1"
  local base_rev="$2"
  local issue_id=""
  local launch_json=""
  local launch_status=0
  local handoff_json=""
  local handoff_status=0
  local finish_json=""
  local finish_status=0
  local claim_json=""
  local claim_status=0
  local close_json=""
  local close_status=0
  local board_json=""
  local revision=""
  local archive_json=""
  local archive_status=0
  local workspace_name=""
  local workspace_path=""

  note "lifecycle: begin"
  issue_id="$(create_issue "${repo_root}" "transition lifecycle probe")"

  run_cli_json launch_json launch_status \
    tuskd launch-lane --repo "${repo_root}" --issue-id "${issue_id}" --base-rev "${base_rev}" --slug lifecycle-probe
  assert_status "${launch_status}" "1" "launch before claim"
  assert_json_value "${launch_json}" '.error.message' "launch_lane requires a claimed in_progress issue" "launch before claim rejection"

  revision="$(current_revision "${repo_root}")"
  run_cli_json handoff_json handoff_status \
    tuskd handoff-lane --repo "${repo_root}" --issue-id "${issue_id}" --revision "${revision}" --note "too early"
  assert_status "${handoff_status}" "1" "handoff before launch"
  assert_json_value "${handoff_json}" '.error.message' "handoff_lane requires an existing lane record" "handoff before launch rejection"

  run_cli_json finish_json finish_status \
    tuskd finish-lane --repo "${repo_root}" --issue-id "${issue_id}" --outcome completed --note "too early"
  assert_status "${finish_status}" "1" "finish before launch"
  assert_json_value "${finish_json}" '.error.message' "finish_lane requires an existing lane record" "finish before launch rejection"

  run_cli_json claim_json claim_status \
    tuskd claim-issue --repo "${repo_root}" --issue-id "${issue_id}"
  assert_status "${claim_status}" "0" "claim issue"
  assert_json_value "${claim_json}" '.issue_id' "${issue_id}" "claim issue id"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "issue.claim")" = "1" ] || fail "claim receipt count mismatch for ${issue_id}"

  run_cli_json launch_json launch_status \
    tuskd launch-lane --repo "${repo_root}" --issue-id "${issue_id}" --base-rev "${base_rev}" --slug lifecycle-probe
  assert_status "${launch_status}" "0" "launch lane"
  workspace_name="$(jq -r '.workspace_name' <<<"${launch_json}")"
  workspace_path="$(jq -r '.workspace_path' <<<"${launch_json}")"
  [ -d "${workspace_path}" ] || fail "launched workspace missing: ${workspace_path}"
  [ "$(lane_count "${repo_root}" "${issue_id}")" = "1" ] || fail "lane state count mismatch after launch for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.launch")" = "1" ] || fail "lane.launch receipt count mismatch for ${issue_id}"

  board_json="$(tuskd board-status --repo "${repo_root}")"
  assert_json_jq "${board_json}" "board did not show launched lane" --arg issue_id "${issue_id}" '
    [.lanes[] | select(.issue_id == $issue_id and .status == "launched" and .observed_status == "launched" and .workspace_exists == true)] | length == 1
  '

  run_cli_json close_json close_status \
    tuskd close-issue --repo "${repo_root}" --issue-id "${issue_id}" --reason "too early"
  assert_status "${close_status}" "1" "close while lane exists"
  assert_json_value "${close_json}" '.error.message' "close_issue requires the live lane to be archived first" "close while live lane rejection"

  revision="$(current_revision "${repo_root}")"
  run_cli_json handoff_json handoff_status \
    tuskd handoff-lane --repo "${repo_root}" --issue-id "${issue_id}" --revision "${revision}" --note "handoff probe"
  assert_status "${handoff_status}" "0" "handoff lane"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.handoff")" = "1" ] || fail "lane.handoff receipt count mismatch for ${issue_id}"

  run_cli_json finish_json finish_status \
    tuskd finish-lane --repo "${repo_root}" --issue-id "${issue_id}" --outcome completed --note "finished probe"
  assert_status "${finish_status}" "0" "finish lane"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.finish")" = "1" ] || fail "lane.finish receipt count mismatch for ${issue_id}"

  run_cli_json archive_json archive_status \
    tuskd archive-lane --repo "${repo_root}" --issue-id "${issue_id}" --note "workspace still present"
  assert_status "${archive_status}" "1" "archive before workspace removal"
  assert_json_value "${archive_json}" '.error.message' "archive_lane requires the lane workspace to be removed first" "archive before workspace removal rejection"

  forget_and_remove_workspace "${repo_root}" "${workspace_name}" "${workspace_path}"
  board_json="$(tuskd board-status --repo "${repo_root}")"
  assert_json_jq "${board_json}" "board did not preserve finished lane after workspace removal" --arg issue_id "${issue_id}" '
    [.lanes[] | select(.issue_id == $issue_id and .status == "finished" and .observed_status == "finished" and .workspace_exists == false)] | length == 1
  '

  run_cli_json archive_json archive_status \
    tuskd archive-lane --repo "${repo_root}" --issue-id "${issue_id}" --note "archive probe"
  assert_status "${archive_status}" "0" "archive lane"
  [ "$(lane_count "${repo_root}" "${issue_id}")" = "0" ] || fail "lane state should be empty after archive for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.archive")" = "1" ] || fail "lane.archive receipt count mismatch for ${issue_id}"

  board_json="$(tuskd board-status --repo "${repo_root}")"
  assert_json_jq "${board_json}" "archived lane still present on board" --arg issue_id "${issue_id}" '
    [.lanes[] | select(.issue_id == $issue_id)] | length == 0
  '

  run_cli_json close_json close_status \
    tuskd close-issue --repo "${repo_root}" --issue-id "${issue_id}" --reason "lifecycle test completed"
  assert_status "${close_status}" "0" "close issue after archive"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "issue.close")" = "1" ] || fail "issue.close receipt count mismatch for ${issue_id}"

  note "lifecycle: ok"
}

test_concurrent_claims() {
  local repo_root="$1"
  local issue_id=""
  local tmp_dir=""
  local one_json=""
  local two_json=""
  local one_status=0
  local two_status=0
  local successes=0
  local failures=0
  local close_json=""
  local close_status=0

  note "concurrency: begin"
  issue_id="$(create_issue "${repo_root}" "transition concurrency probe")"

  tmp_dir="$(mktemp -d)"
  (
    tuskd claim-issue \
      --repo "${repo_root}" \
      --issue-id "${issue_id}" \
      >"${tmp_dir}/one.json"
  ) &
  local one_pid=$!
  (
    tuskd claim-issue \
      --repo "${repo_root}" \
      --issue-id "${issue_id}" \
      >"${tmp_dir}/two.json"
  ) &
  local two_pid=$!

  if wait "${one_pid}"; then
    one_status=0
  else
    one_status=$?
  fi
  if wait "${two_pid}"; then
    two_status=0
  else
    two_status=$?
  fi

  one_json="$(cat "${tmp_dir}/one.json")"
  two_json="$(cat "${tmp_dir}/two.json")"
  rm -rf -- "${tmp_dir}"

  printf '%s' "${one_json}" | jq -e . >/dev/null 2>&1 || fail "first concurrent claim did not return JSON"
  printf '%s' "${two_json}" | jq -e . >/dev/null 2>&1 || fail "second concurrent claim did not return JSON"

  successes=0
  if [ "${one_status}" = "0" ]; then
    successes=$((successes + 1))
  fi
  if [ "${two_status}" = "0" ]; then
    successes=$((successes + 1))
  fi
  failures=$((2 - successes))

  [ "${successes}" = "1" ] || fail "expected exactly one successful concurrent claim"$'\n'"${one_json}"$'\n'"${two_json}"
  [ "${failures}" = "1" ] || fail "expected exactly one rejected concurrent claim"$'\n'"${one_json}"$'\n'"${two_json}"

  if [ "${one_status}" != "0" ]; then
    assert_json_jq "${one_json}" "first concurrent rejection message" '
      .error.message == "claim_issue requires an open issue" or
      .error.message == "claim_issue requires a ready issue"
    '
  fi
  if [ "${two_status}" != "0" ]; then
    assert_json_jq "${two_json}" "second concurrent rejection message" '
      .error.message == "claim_issue requires an open issue" or
      .error.message == "claim_issue requires a ready issue"
    '
  fi

  [ "$(receipt_count "${repo_root}" "${issue_id}" "issue.claim")" = "1" ] || fail "concurrent claim wrote unexpected receipt count for ${issue_id}"
  [ "$(lane_count "${repo_root}" "${issue_id}")" = "0" ] || fail "concurrent claim should not create lane state for ${issue_id}"

  run_cli_json close_json close_status \
    tuskd close-issue --repo "${repo_root}" --issue-id "${issue_id}" --reason "concurrency test completed"
  assert_status "${close_status}" "0" "close concurrency issue"

  note "concurrency: ok"
}

test_launch_rollback() {
  local repo_root="$1"
  local base_rev="$2"
  local issue_id=""
  local claim_json=""
  local claim_status=0
  local launch_json=""
  local launch_status=0
  local workspace_name=""
  local workspace_path=""
  local close_json=""
  local close_status=0

  note "rollback: begin"
  issue_id="$(create_issue "${repo_root}" "transition rollback probe")"

  run_cli_json claim_json claim_status \
    tuskd claim-issue --repo "${repo_root}" --issue-id "${issue_id}"
  assert_status "${claim_status}" "0" "claim rollback issue"

  run_cli_json launch_json launch_status \
    env TUSKD_TEST_FAIL_PHASE=launch_lane:after_workspace_add \
      tuskd launch-lane --repo "${repo_root}" --issue-id "${issue_id}" --base-rev "${base_rev}" --slug rollback-probe
  assert_status "${launch_status}" "1" "rollback launch injected failure"
  assert_json_value "${launch_json}" '.error.message' "injected transition failure after workspace add" "rollback injected failure message"

  workspace_name="$(jq -r '.error.details.workspace_name // ""' <<<"${launch_json}")"
  workspace_path="$(jq -r '.error.details.workspace_path // ""' <<<"${launch_json}")"
  [ -n "${workspace_name}" ] || fail "rollback result missing workspace_name"$'\n'"${launch_json}"
  [ -n "${workspace_path}" ] || fail "rollback result missing workspace_path"$'\n'"${launch_json}"

  assert_file_missing "${workspace_path}" "rollback workspace cleanup"
  [ "$(lane_count "${repo_root}" "${issue_id}")" = "0" ] || fail "rollback left lane state behind for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.launch")" = "0" ] || fail "rollback wrote lane.launch receipt for ${issue_id}"

  if jj --repository "${repo_root}" workspace list --ignore-working-copy --color never | grep -F "${workspace_name}" >/dev/null 2>&1; then
    fail "rollback left jj workspace registration behind for ${workspace_name}"
  fi

  run_cli_json close_json close_status \
    tuskd close-issue --repo "${repo_root}" --issue-id "${issue_id}" --reason "rollback test completed"
  assert_status "${close_status}" "0" "close rollback issue"

  note "rollback: ok"
}

run_inner_tests() {
  local repo_root="$1"
  local base_rev="$2"
  local host_state_root="$3"

  export DEVENV_ROOT="${repo_root}"
  export BEADS_WORKSPACE_ROOT="${repo_root}"
  export TUSK_HOST_STATE_ROOT="${host_state_root}"
  export XDG_STATE_HOME="${host_state_root}/xdg"

  mkdir -p "${TUSK_HOST_STATE_ROOT}" "${XDG_STATE_HOME}"
  cd "${repo_root}"

  bd init -p tusk >/dev/null
  tuskd ensure --repo "${repo_root}" >/dev/null

  test_lifecycle_guards "${repo_root}" "${base_rev}"
  test_concurrent_claims "${repo_root}"
  test_launch_rollback "${repo_root}" "${base_rev}"

  note "all transition tests passed"
}

run_outer_harness() {
  local source_repo="$1"
  local base_rev="$2"
  local keep_temp="$3"
  local source_git_root=""
  local temp_root=""
  local temp_repo=""
  local patch_path=""
  local host_state_root=""
  local diff_is_empty=true
  local status=0

  source_git_root="$(resolve_git_root "${source_repo}")"
  temp_root="$(
    cd "$(mktemp -d -t tuskd-transition-tests.XXXXXX)"
    pwd -P
  )"
  temp_repo="${temp_root}/repo"
  patch_path="${temp_root}/source.patch"
  host_state_root="${temp_root}/host-state"
  cleanup_keep_temp="${keep_temp}"
  cleanup_preserve_temp=false
  cleanup_temp_root="${temp_root}"

  cleanup_outer() {
    local exit_code="$1"

    if [ "${cleanup_keep_temp}" = "true" ] || [ "${cleanup_preserve_temp}" = "true" ] || [ "${exit_code}" -ne 0 ]; then
      note "preserving temp repo at ${cleanup_temp_root}"
      return
    fi

    rm -rf -- "${cleanup_temp_root}"
  }

  trap 'status=$?; cleanup_outer "${status}"; exit "${status}"' EXIT

  note "cloning ${source_git_root} into ${temp_repo}"
  jj git clone --colocate "file://${source_git_root}" "${temp_repo}" >/dev/null
  jj --repository "${temp_repo}" log -r "${base_rev}" --no-graph -T 'commit_id ++ "\n"' >/dev/null
  jj --repository "${temp_repo}" new "${base_rev}" -m "tuskd-transition-tests: base" >/dev/null

  jj --repository "${source_repo}" diff --git --from "${base_rev}" --to @ >"${patch_path}"
  if [ -s "${patch_path}" ]; then
    diff_is_empty=false
    git -C "${temp_repo}" apply --whitespace=nowarn "${patch_path}"
  fi

  if [ "${diff_is_empty}" = true ]; then
    note "source diff from ${base_rev} is empty; testing base clone"
  fi

  if ! TUSKD_TRANSITION_TESTS_BASE_REV="${base_rev}" \
      nix develop --no-pure-eval "path:${temp_repo}" \
        -c bash "$0" --inner-repo "${temp_repo}" --host-state-root "${host_state_root}"; then
    cleanup_preserve_temp=true
    fail "transition tests failed"
  fi
}

main() {
  local source_repo="."
  local base_rev="${TUSKD_TRANSITION_TESTS_BASE_REV:-tusk-flake}"
  local keep_temp=false
  local inner_repo=""
  local host_state_root=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --source-repo)
        [ "$#" -ge 2 ] || fail "--source-repo requires a value"
        source_repo="$2"
        shift 2
        ;;
      --base-rev)
        [ "$#" -ge 2 ] || fail "--base-rev requires a value"
        base_rev="$2"
        shift 2
        ;;
      --keep-temp)
        keep_temp=true
        shift
        ;;
      --inner-repo)
        [ "$#" -ge 2 ] || fail "--inner-repo requires a value"
        inner_repo="$2"
        shift 2
        ;;
      --host-state-root)
        [ "$#" -ge 2 ] || fail "--host-state-root requires a value"
        host_state_root="$2"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        fail "unknown argument: $1"
        ;;
    esac
  done

  if [ -n "${inner_repo}" ]; then
    [ -n "${host_state_root}" ] || fail "--inner-repo requires --host-state-root"
    run_inner_tests "$(resolve_repo_root "${inner_repo}")" "${base_rev}" "${host_state_root}"
    exit 0
  fi

  run_outer_harness "$(resolve_repo_root "${source_repo}")" "${base_rev}" "${keep_temp}"
}

main "$@"
