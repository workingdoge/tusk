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
  --base-rev REV       Base revision used for the replay patch. Defaults to main.
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
  local stderr_path=""

  stderr_path="$(mktemp)"
  set +e
  output="$("$@" 2>"${stderr_path}")"
  status=$?
  set -e
  if [ -s "${stderr_path}" ]; then
    cat "${stderr_path}" >&2
  fi
  rm -f -- "${stderr_path}"

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

assert_file_present() {
  local path="$1"
  local context="$2"

  [ -e "${path}" ] || fail "${context}: ${path} is missing"
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

create_epic_issue() {
  local repo_root="$1"
  local title="$2"
  local create_json=""
  local create_status=0
  local issue_id=""

  run_cli_json create_json create_status \
    bd create \
      --title "${title}" \
      --description "Disposable parent issue for automated tuskd transition tests." \
      --type epic \
      --priority 2 \
      --json
  assert_status "${create_status}" "0" "bd create epic"

  issue_id="$(jq -r 'if type == "array" then .[0].id // "" else .id // "" end' <<<"${create_json}")"
  [ -n "${issue_id}" ] || fail "failed to extract epic issue id from create output"$'\n'"${create_json}"
  printf '%s\n' "${issue_id}"
}

create_labeled_issue() {
  local repo_root="$1"
  local title="$2"
  local description="$3"
  local labels="$4"
  local create_json=""
  local create_status=0
  local issue_id=""

  run_cli_json create_json create_status \
    bd create \
      --title "${title}" \
      --description "${description}" \
      --type task \
      --priority 2 \
      --labels "${labels}" \
      --json
  assert_status "${create_status}" "0" "bd create labeled issue"

  issue_id="$(jq -r 'if type == "array" then .[0].id // "" else .id // "" end' <<<"${create_json}")"
  [ -n "${issue_id}" ] || fail "failed to extract labeled issue id"$'\n'"${create_json}"
  printf '%s\n' "${issue_id}"
}

create_codex_stub_launcher() {
  local repo_root="$1"
  local stub_path="${repo_root}/.beads/tuskd/test-codex-runner.sh"

  mkdir -p "$(dirname "${stub_path}")"
  cat >"${stub_path}" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

output_path=""
checkout_path=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --checkout)
      checkout_path="${2:?--checkout requires a path}"
      shift 2
      ;;
    --output-last-message)
      output_path="${2:?--output-last-message requires a path}"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

prompt="$(cat)"
if [ "${TUSKD_TEST_STUB_TOUCH_FILE:-0}" = "1" ] && [ -n "${checkout_path}" ]; then
  printf 'stub timeout change\n' > "${checkout_path}/dispatch-timeout-stub.txt"
fi

if [ "${TUSKD_TEST_STUB_SLEEP_SECONDS:-0}" != "0" ]; then
  sleep "${TUSKD_TEST_STUB_SLEEP_SECONDS}"
fi

if [ "${TUSKD_TEST_STUB_SKIP_OUTPUT:-0}" != "1" ] && [ -n "${output_path}" ]; then
  mkdir -p "$(dirname "${output_path}")"
  printf 'stub worker completed\n' > "${output_path}"
  printf '%s\n' "${prompt}" > "${output_path}.prompt"
fi

if [ "${TUSKD_TEST_STUB_COMMIT:-0}" = "1" ] && [ -n "${checkout_path}" ]; then
  printf 'stub autonomous change\n' > "${checkout_path}/autonomous-stub.txt"
  jj --repository "${checkout_path}" commit -m "${TUSKD_TEST_STUB_COMMIT_MESSAGE:-stub autonomous commit}" >/dev/null
fi

printf '{"ok":true,"runner":"stub-codex"}\n'
EOF
  chmod +x "${stub_path}"
  printf '%s\n' "${stub_path}"
}

current_revision() {
  local repo_root="$1"
  local revision=""

  revision="$(resolve_revision "${repo_root}" "@")"
  [ -n "${revision}" ] || fail "failed to resolve current revision"
  printf '%s\n' "${revision}"
}

resolve_revision() {
  local repo_root="$1"
  local revset="$2"
  local revision=""

  revision="$(
    jj --repository "${repo_root}" log -r "${revset}" --no-graph -T 'commit_id ++ "\n"' \
      | awk 'NF { print; exit }'
  )"
  [ -n "${revision}" ] || fail "failed to resolve revision ${revset} in ${repo_root}"
  printf '%s\n' "${revision}"
}

resolve_existing_base_rev() {
  local repo_root="$1"
  local base_rev="$2"
  local candidate=""

  for candidate in "${base_rev}" "${base_rev}@origin"; do
    if jj --repository "${repo_root}" log -r "${candidate}" --no-graph -T 'commit_id ++ "\n"' >/dev/null 2>&1; then
      printf '%s\n' "${candidate}"
      return 0
    fi
  done

  fail "Revision \`${base_rev}\` doesn't exist in ${repo_root}"
}

ensure_local_main_bookmark() {
  local repo_root="$1"
  local base_rev="$2"
  local target_revision=""

  if jj --repository "${repo_root}" log -r main --no-graph -T 'commit_id ++ "\n"' >/dev/null 2>&1; then
    return 0
  fi

  target_revision="$(resolve_revision "${repo_root}" "${base_rev}")"
  jj --repository "${repo_root}" bookmark set main -r "${target_revision}" >/dev/null
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

test_concurrent_child_creates() {
  local repo_root="$1"
  local parent_id=""
  local tmp_dir=""
  local one_json=""
  local two_json=""
  local one_status=0
  local two_status=0
  local one_issue_id=""
  local two_issue_id=""

  note "child-create concurrency: begin"
  parent_id="$(create_epic_issue "${repo_root}" "transition child create parent")"

  tmp_dir="$(mktemp -d)"
  (
    tuskd create-child-issue \
      --repo "${repo_root}" \
      --parent-id "${parent_id}" \
      --title "transition child create one" \
      --description "Disposable child issue for concurrent governed-create testing." \
      --labels "place:tusk,surface:ops,track:core" \
      >"${tmp_dir}/one.json"
  ) &
  local one_pid=$!
  (
    tuskd create-child-issue \
      --repo "${repo_root}" \
      --parent-id "${parent_id}" \
      --title "transition child create two" \
      --description "Disposable child issue for concurrent governed-create testing." \
      --labels "place:tusk,surface:ops,track:core" \
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

  assert_status "${one_status}" "0" "first concurrent child create"
  assert_status "${two_status}" "0" "second concurrent child create"
  printf '%s' "${one_json}" | jq -e . >/dev/null 2>&1 || fail "first concurrent child create did not return JSON"
  printf '%s' "${two_json}" | jq -e . >/dev/null 2>&1 || fail "second concurrent child create did not return JSON"

  one_issue_id="$(jq -r '.issue_id // .issue.id // ""' <<<"${one_json}")"
  two_issue_id="$(jq -r '.issue_id // .issue.id // ""' <<<"${two_json}")"
  [ -n "${one_issue_id}" ] || fail "first concurrent child create did not return issue_id"$'\n'"${one_json}"
  [ -n "${two_issue_id}" ] || fail "second concurrent child create did not return issue_id"$'\n'"${two_json}"
  [ "${one_issue_id}" != "${two_issue_id}" ] || fail "concurrent child creates returned the same issue id"$'\n'"${one_json}"$'\n'"${two_json}"

  case "${one_issue_id}:${two_issue_id}" in
    "${parent_id}.1:${parent_id}.2"|\
    "${parent_id}.2:${parent_id}.1")
      ;;
    *)
      fail "concurrent child creates did not allocate the expected child ids"$'\n'"${one_json}"$'\n'"${two_json}"
      ;;
  esac

  [ "$(receipt_count "${repo_root}" "${one_issue_id}" "issue.create")" = "1" ] || fail "first child create receipt count mismatch for ${one_issue_id}"
  [ "$(receipt_count "${repo_root}" "${two_issue_id}" "issue.create")" = "1" ] || fail "second child create receipt count mismatch for ${two_issue_id}"

  note "child-create concurrency: ok"
}

test_child_create_identity_mismatch() {
  local repo_root="$1"
  local parent_id=""
  local create_json=""
  local create_status=0
  local issue_id=""

  note "child-create identity mismatch: begin"
  parent_id="$(create_epic_issue "${repo_root}" "transition child create mismatch parent")"

  run_cli_json create_json create_status \
    env TUSKD_TEST_FAIL_PHASE=create_child_issue:tamper_identity \
      tuskd create-child-issue \
        --repo "${repo_root}" \
        --parent-id "${parent_id}" \
        --title "transition child create mismatch" \
        --description "Disposable child issue for post-create identity verification testing." \
        --labels "place:tusk,surface:ops,track:core"
  assert_status "${create_status}" "1" "tampered child create should fail"
  assert_json_value "${create_json}" '.error.message' "create_child_issue detected issue identity mismatch after create" "child create mismatch message"

  issue_id="$(jq -r '.error.details.issue_id // ""' <<<"${create_json}")"
  [ -n "${issue_id}" ] || fail "child create mismatch did not report issue_id"$'\n'"${create_json}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "issue.create")" = "0" ] || fail "identity mismatch should not append issue.create receipt for ${issue_id}"

  note "child-create identity mismatch: ok"
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

test_compact_lane_remove() {
  local repo_root="$1"
  local base_rev="$2"
  local issue_id=""
  local claim_json=""
  local claim_status=0
  local launch_json=""
  local launch_status=0
  local compact_json=""
  local compact_status=0
  local revision=""
  local workspace_path=""

  note "compact-remove: begin"
  issue_id="$(create_issue "${repo_root}" "transition compact remove probe")"

  run_cli_json claim_json claim_status \
    tuskd claim-issue --repo "${repo_root}" --issue-id "${issue_id}"
  assert_status "${claim_status}" "0" "claim compact remove issue"

  run_cli_json launch_json launch_status \
    tuskd launch-lane --repo "${repo_root}" --issue-id "${issue_id}" --base-rev "${base_rev}" --slug compact-remove-probe
  assert_status "${launch_status}" "0" "launch compact remove lane"

  revision="$(current_revision "${repo_root}")"
  run_cli_json compact_json compact_status \
    tuskd compact-lane \
      --repo "${repo_root}" \
      --issue-id "${issue_id}" \
      --revision "${revision}" \
      --reason "compact remove test completed" \
      --note "compact remove probe"
  assert_status "${compact_status}" "0" "compact lane remove"
  assert_json_value "${compact_json}" '.cleanup.effective_mode' "remove" "compact remove mode"

  workspace_path="$(jq -r '.cleanup.workspace_path // ""' <<<"${compact_json}")"
  [ -n "${workspace_path}" ] || fail "compact remove output missing workspace_path"$'\n'"${compact_json}"
  assert_file_missing "${workspace_path}" "compact remove workspace cleanup"
  [ "$(lane_count "${repo_root}" "${issue_id}")" = "0" ] || fail "compact remove left lane state behind for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "issue.claim")" = "1" ] || fail "compact remove issue.claim receipt count mismatch for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.launch")" = "1" ] || fail "compact remove lane.launch receipt count mismatch for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.handoff")" = "1" ] || fail "compact remove lane.handoff receipt count mismatch for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.finish")" = "1" ] || fail "compact remove lane.finish receipt count mismatch for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.archive")" = "1" ] || fail "compact remove lane.archive receipt count mismatch for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "issue.close")" = "1" ] || fail "compact remove issue.close receipt count mismatch for ${issue_id}"

  note "compact-remove: ok"
}

test_compact_lane_quarantine() {
  local repo_root="$1"
  local base_rev="$2"
  local issue_id=""
  local claim_json=""
  local claim_status=0
  local launch_json=""
  local launch_status=0
  local compact_json=""
  local compact_status=0
  local revision=""
  local workspace_path=""
  local quarantine_path=""

  note "compact-quarantine: begin"
  issue_id="$(create_issue "${repo_root}" "transition compact quarantine probe")"

  run_cli_json claim_json claim_status \
    tuskd claim-issue --repo "${repo_root}" --issue-id "${issue_id}"
  assert_status "${claim_status}" "0" "claim compact quarantine issue"

  run_cli_json launch_json launch_status \
    tuskd launch-lane --repo "${repo_root}" --issue-id "${issue_id}" --base-rev "${base_rev}" --slug compact-quarantine-probe
  assert_status "${launch_status}" "0" "launch compact quarantine lane"

  revision="$(current_revision "${repo_root}")"
  run_cli_json compact_json compact_status \
    tuskd compact-lane \
      --repo "${repo_root}" \
      --issue-id "${issue_id}" \
      --revision "${revision}" \
      --reason "compact quarantine test completed" \
      --note "compact quarantine probe" \
      --quarantine
  assert_status "${compact_status}" "0" "compact lane quarantine"
  assert_json_value "${compact_json}" '.cleanup.effective_mode' "quarantine" "compact quarantine mode"

  workspace_path="$(jq -r '.cleanup.workspace_path // ""' <<<"${compact_json}")"
  quarantine_path="$(jq -r '.cleanup.quarantine_path // ""' <<<"${compact_json}")"
  [ -n "${workspace_path}" ] || fail "compact quarantine output missing workspace_path"$'\n'"${compact_json}"
  [ -n "${quarantine_path}" ] || fail "compact quarantine output missing quarantine_path"$'\n'"${compact_json}"
  assert_file_missing "${workspace_path}" "compact quarantine removed original workspace path"
  assert_file_present "${quarantine_path}" "compact quarantine moved workspace"
  [ "$(lane_count "${repo_root}" "${issue_id}")" = "0" ] || fail "compact quarantine left lane state behind for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.handoff")" = "1" ] || fail "compact quarantine lane.handoff receipt count mismatch for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.finish")" = "1" ] || fail "compact quarantine lane.finish receipt count mismatch for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.archive")" = "1" ] || fail "compact quarantine lane.archive receipt count mismatch for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "issue.close")" = "1" ] || fail "compact quarantine issue.close receipt count mismatch for ${issue_id}"

  rm -rf -- "${quarantine_path}"
  note "compact-quarantine: ok"
}

test_dispatch_lane() {
  local repo_root="$1"
  local base_rev="$2"
  local issue_id=""
  local issue_description=""
  local claim_json=""
  local claim_status=0
  local launch_json=""
  local launch_status=0
  local plan_json=""
  local plan_status=0
  local dispatch_json=""
  local dispatch_status=0
  local board_json=""
  local prompt_path=""
  local brief_path=""
  local output_path=""
  local stub_path=""

  note "dispatch-lane: begin"
  issue_description=$'Goal:\nExercise the autonomous dispatch path.\n\nVerification:\n- bash -n scripts/tuskd.sh\n- bash -n scripts/tuskd-transition-tests.sh'
  issue_id="$(create_labeled_issue "${repo_root}" "transition dispatch lane probe" "${issue_description}" "place:tusk,track:core,surface:self-hosting")"
  stub_path="$(create_codex_stub_launcher "${repo_root}")"

  run_cli_json claim_json claim_status \
    tuskd claim-issue --repo "${repo_root}" --issue-id "${issue_id}"
  assert_status "${claim_status}" "0" "claim dispatch issue"

  run_cli_json launch_json launch_status \
    tuskd launch-lane --repo "${repo_root}" --issue-id "${issue_id}" --base-rev "${base_rev}" --slug dispatch-lane-probe
  assert_status "${launch_status}" "0" "launch dispatch lane"

  run_cli_json plan_json plan_status \
    env TUSKD_CODEX_LAUNCHER="${stub_path}" \
      tuskd dispatch-lane --repo "${repo_root}" --issue-id "${issue_id}" --plan
  assert_status "${plan_status}" "0" "dispatch-lane plan"
  assert_json_value "${plan_json}" '.status' "plan" "dispatch-lane plan status"
  assert_json_value "${plan_json}" '.worker' "codex" "dispatch-lane plan worker"
  assert_json_value "${plan_json}" '.mode' "handoff" "dispatch-lane plan mode"
  assert_json_value "${plan_json}" '.policy_class' "tusk.low-risk.v1" "dispatch-lane plan policy"

  run_cli_json dispatch_json dispatch_status \
    env TUSKD_CODEX_LAUNCHER="${stub_path}" \
      tuskd dispatch-lane --repo "${repo_root}" --issue-id "${issue_id}" --mode exec --note "dispatch probe"
  assert_status "${dispatch_status}" "0" "dispatch-lane exec"
  assert_json_value "${dispatch_json}" '.status' "executed" "dispatch-lane exec status"
  assert_json_value "${dispatch_json}" '.worker' "codex" "dispatch-lane exec worker"
  assert_json_value "${dispatch_json}" '.mode' "exec" "dispatch-lane exec mode"
  assert_json_value "${dispatch_json}" '.dispatch.status' "executed" "dispatch-lane dispatch status"
  assert_json_value "${dispatch_json}" '.dispatch.runner_result.exit_code' "0" "dispatch-lane runner exit"

  prompt_path="$(jq -r '.prompt_path // ""' <<<"${dispatch_json}")"
  brief_path="$(jq -r '.brief_path // ""' <<<"${dispatch_json}")"
  output_path="$(jq -r '.output_path // ""' <<<"${dispatch_json}")"
  assert_file_present "${prompt_path}" "dispatch-lane prompt file"
  assert_file_present "${brief_path}" "dispatch-lane brief file"
  assert_file_present "${output_path}" "dispatch-lane output file"
  assert_file_present "${output_path}.prompt" "dispatch-lane stub prompt capture"
  grep -F "${issue_id}" "${prompt_path}" >/dev/null 2>&1 || fail "dispatch prompt missing issue id"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.dispatch")" = "1" ] || fail "lane.dispatch receipt count mismatch for ${issue_id}"

  board_json="$(tuskd board-status --repo "${repo_root}")"
  assert_json_jq "${board_json}" "board did not show dispatched lane" --arg issue_id "${issue_id}" '
    [.lanes[] | select(.issue_id == $issue_id and .status == "launched" and .dispatch.status == "executed")] | length == 1
  '

  note "dispatch-lane: ok"
}

test_dispatch_lane_timeout() {
  local repo_root="$1"
  local base_rev="$2"
  local issue_id=""
  local issue_description=""
  local claim_json=""
  local claim_status=0
  local launch_json=""
  local launch_status=0
  local dispatch_json=""
  local dispatch_status=0
  local board_json=""
  local show_json=""
  local show_status=0
  local stub_path=""

  note "dispatch-lane timeout: begin"
  issue_description=$'Goal:\nExercise bounded dispatch timeout handling.\n\nVerification:\n- bash -n scripts/tuskd.sh'
  issue_id="$(create_labeled_issue "${repo_root}" "transition dispatch lane timeout probe" "${issue_description}" "place:tusk,track:core,surface:self-hosting")"
  stub_path="$(create_codex_stub_launcher "${repo_root}")"

  run_cli_json claim_json claim_status \
    tuskd claim-issue --repo "${repo_root}" --issue-id "${issue_id}"
  assert_status "${claim_status}" "0" "claim dispatch timeout issue"

  run_cli_json launch_json launch_status \
    tuskd launch-lane --repo "${repo_root}" --issue-id "${issue_id}" --base-rev "${base_rev}" --slug dispatch-timeout-probe
  assert_status "${launch_status}" "0" "launch dispatch timeout lane"

  run_cli_json dispatch_json dispatch_status \
    env \
      TUSKD_CODEX_LAUNCHER="${stub_path}" \
      TUSKD_DISPATCH_TIMEOUT_SECONDS=1 \
      TUSKD_DISPATCH_KILL_AFTER_SECONDS=1 \
      TUSKD_TEST_STUB_TOUCH_FILE=1 \
      TUSKD_TEST_STUB_SKIP_OUTPUT=1 \
      TUSKD_TEST_STUB_SLEEP_SECONDS=5 \
      tuskd dispatch-lane --repo "${repo_root}" --issue-id "${issue_id}" --mode exec --note "dispatch timeout probe"
  assert_status "${dispatch_status}" "1" "dispatch-lane timeout exit"
  assert_json_value "${dispatch_json}" '.error.message' "dispatch_lane worker timed out" "dispatch-lane timeout message"
  assert_json_value "${dispatch_json}" '.error.details.dispatch.status' "timed_out" "dispatch-lane timeout status"
  assert_json_value "${dispatch_json}" '.error.details.dispatch.runner_result.timed_out' "true" "dispatch-lane timeout timed_out"
  assert_json_value "${dispatch_json}" '.error.details.dispatch.runner_result.classification' "timed_out" "dispatch-lane timeout classification"
  assert_json_value "${dispatch_json}" '.error.details.dispatch.runner_result.output_path.exists' "false" "dispatch-lane timeout output missing"
  assert_json_value "${dispatch_json}" '.error.details.dispatch.runner_result.workspace_probe.working_copy_clean' "false" "dispatch-lane timeout workspace dirty"
  assert_json_value "${dispatch_json}" '.error.details.dispatch.runner_result.workspace_probe.visible_revision' "false" "dispatch-lane timeout no visible revision"

  board_json="$(tuskd board-status --repo "${repo_root}")"
  assert_json_jq "${board_json}" "board did not keep timed-out lane inspectable" --arg issue_id "${issue_id}" '
    [.lanes[] | select(.issue_id == $issue_id and .status == "launched" and .dispatch.status == "timed_out")] | length == 1
  '

  run_cli_json show_json show_status bd show "${issue_id}" --json
  assert_status "${show_status}" "0" "dispatch-lane timeout issue show"
  assert_json_value "${show_json}" '.[0].status' "in_progress" "dispatch-lane timeout issue status"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.dispatch")" = "1" ] || fail "dispatch-lane timeout lane.dispatch receipt count mismatch for ${issue_id}"

  note "dispatch-lane timeout: ok"
}

test_autonomous_lane_success() {
  local repo_root="$1"
  local base_rev="$2"
  local issue_id=""
  local issue_description=""
  local plan_json=""
  local plan_status=0
  local autonomous_json=""
  local autonomous_status=0
  local status_json=""
  local show_json=""
  local show_status=0
  local landed_revision=""
  local git_main_commit=""
  local stub_path=""

  note "autonomous-lane success: begin"
  issue_description=$'Goal:\nExercise the bounded autonomous lane success path.\n\nVerification:\n- test -f autonomous-stub.txt\n- bash -n scripts/tuskd.sh'
  issue_id="$(create_labeled_issue "${repo_root}" "transition autonomous lane success probe" "${issue_description}" "place:tusk,track:core,surface:self-hosting,autonomy:v1-safe")"
  stub_path="$(create_codex_stub_launcher "${repo_root}")"

  run_cli_json plan_json plan_status \
    env TUSKD_CODEX_LAUNCHER="${stub_path}" \
      tuskd autonomous-lane --repo "${repo_root}" --issue-id "${issue_id}" --base-rev "${base_rev}" --slug autonomous-lane-probe --plan
  assert_status "${plan_status}" "0" "autonomous-lane plan"
  assert_json_value "${plan_json}" '.status' "plan" "autonomous-lane plan status"
  assert_json_value "${plan_json}" '.policy_class' "tusk.autonomous.v1" "autonomous-lane plan policy"
  assert_json_value "${plan_json}" '.verification | length' "2" "autonomous-lane plan verification count"

  run_cli_json autonomous_json autonomous_status \
    env \
      TUSKD_CODEX_LAUNCHER="${stub_path}" \
      TUSKD_TEST_STUB_COMMIT=1 \
      TUSKD_TEST_STUB_COMMIT_MESSAGE="${issue_id}: autonomous stub commit" \
      tuskd autonomous-lane --repo "${repo_root}" --issue-id "${issue_id}" --base-rev "${base_rev}" --slug autonomous-lane-probe --note "autonomous success probe"
  assert_status "${autonomous_status}" "0" "autonomous-lane success run"
  assert_json_value "${autonomous_json}" '.status' "completed" "autonomous-lane success status"
  assert_json_value "${autonomous_json}" '.policy_class' "tusk.autonomous.v1" "autonomous-lane success policy"
  assert_json_value "${autonomous_json}" '.dispatch.status' "executed" "autonomous-lane dispatch status"
  assert_json_value "${autonomous_json}" '.verification.ok' "true" "autonomous-lane verification ok"
  assert_json_value "${autonomous_json}" '.complete.status' "completed" "autonomous-lane complete status"
  assert_json_value "${autonomous_json}" '.receipt.kind' "lane.autonomous" "autonomous-lane receipt kind"

  landed_revision="$(jq -r '.complete.revision // ""' <<<"${autonomous_json}")"
  [ -n "${landed_revision}" ] || fail "autonomous-lane success missing landed revision"$'\n'"${autonomous_json}"
  git_main_commit="$(git -C "${repo_root}" rev-parse refs/heads/main)"
  [ "${git_main_commit}" = "${landed_revision}" ] || fail "autonomous-lane success git main mismatch: ${git_main_commit} vs ${landed_revision}"

  status_json="$(tuskd coordinator-status --repo "${repo_root}")"
  assert_json_value "${status_json}" '.status' "in_sync" "autonomous-lane success coordinator status"
  assert_json_value "${status_json}" '.parent_commits[0]' "${landed_revision}" "autonomous-lane success coordinator parent"

  run_cli_json show_json show_status bd show "${issue_id}" --json
  assert_status "${show_status}" "0" "autonomous-lane success issue show"
  assert_json_value "${show_json}" '.[0].status' "closed" "autonomous-lane success issue closed"
  [ "$(lane_count "${repo_root}" "${issue_id}")" = "0" ] || fail "autonomous-lane success left lane state behind for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.dispatch")" = "1" ] || fail "autonomous-lane success lane.dispatch receipt count mismatch for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.complete")" = "1" ] || fail "autonomous-lane success lane.complete receipt count mismatch for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.autonomous")" = "1" ] || fail "autonomous-lane success lane.autonomous receipt count mismatch for ${issue_id}"

  note "autonomous-lane success: ok"
}

test_autonomous_lane_missing_revision() {
  local repo_root="$1"
  local base_rev="$2"
  local issue_id=""
  local issue_description=""
  local autonomous_json=""
  local autonomous_status=0
  local board_json=""
  local show_json=""
  local show_status=0
  local stub_path=""

  note "autonomous-lane missing revision: begin"
  issue_description=$'Goal:\nExercise autonomous failure when the worker leaves no visible revision.\n\nVerification:\n- bash -n scripts/tuskd.sh'
  issue_id="$(create_labeled_issue "${repo_root}" "transition autonomous lane missing revision probe" "${issue_description}" "place:tusk,track:core,surface:self-hosting,autonomy:v1-safe")"
  stub_path="$(create_codex_stub_launcher "${repo_root}")"

  run_cli_json autonomous_json autonomous_status \
    env TUSKD_CODEX_LAUNCHER="${stub_path}" \
      tuskd autonomous-lane --repo "${repo_root}" --issue-id "${issue_id}" --base-rev "${base_rev}" --slug autonomous-missing-revision-probe
  assert_status "${autonomous_status}" "1" "autonomous-lane missing revision exit"
  assert_json_value "${autonomous_json}" '.error.message' "autonomous_lane requires a clean visible revision from the worker lane" "autonomous-lane missing revision message"

  board_json="$(tuskd board-status --repo "${repo_root}")"
  assert_json_jq "${board_json}" "autonomous missing revision lane did not stay inspectable" --arg issue_id "${issue_id}" '
    [.lanes[] | select(.issue_id == $issue_id and .status == "launched" and .dispatch.status == "executed")] | length == 1
  '

  run_cli_json show_json show_status bd show "${issue_id}" --json
  assert_status "${show_status}" "0" "autonomous-lane missing revision issue show"
  assert_json_value "${show_json}" '.[0].status' "in_progress" "autonomous-lane missing revision issue status"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.dispatch")" = "1" ] || fail "autonomous-lane missing revision lane.dispatch receipt count mismatch for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.autonomous")" = "0" ] || fail "autonomous-lane missing revision lane.autonomous receipt count mismatch for ${issue_id}"

  note "autonomous-lane missing revision: ok"
}

test_autonomous_lane_verification_failure() {
  local repo_root="$1"
  local base_rev="$2"
  local issue_id=""
  local issue_description=""
  local autonomous_json=""
  local autonomous_status=0
  local board_json=""
  local show_json=""
  local show_status=0
  local stub_path=""

  note "autonomous-lane verification failure: begin"
  issue_description=$'Goal:\nExercise autonomous failure when lane verification fails.\n\nVerification:\n- false'
  issue_id="$(create_labeled_issue "${repo_root}" "transition autonomous lane verification failure probe" "${issue_description}" "place:tusk,track:core,surface:self-hosting,autonomy:v1-safe")"
  stub_path="$(create_codex_stub_launcher "${repo_root}")"

  run_cli_json autonomous_json autonomous_status \
    env \
      TUSKD_CODEX_LAUNCHER="${stub_path}" \
      TUSKD_TEST_STUB_COMMIT=1 \
      TUSKD_TEST_STUB_COMMIT_MESSAGE="${issue_id}: autonomous verification failure stub commit" \
      tuskd autonomous-lane --repo "${repo_root}" --issue-id "${issue_id}" --base-rev "${base_rev}" --slug autonomous-verification-failure-probe
  assert_status "${autonomous_status}" "1" "autonomous-lane verification failure exit"
  assert_json_value "${autonomous_json}" '.error.message' "autonomous_lane verification failed" "autonomous-lane verification failure message"
  assert_json_value "${autonomous_json}" '.payload.verification.ok' "false" "autonomous-lane verification failure result"

  board_json="$(tuskd board-status --repo "${repo_root}")"
  assert_json_jq "${board_json}" "autonomous verification failure lane did not stay inspectable" --arg issue_id "${issue_id}" '
    [.lanes[] | select(.issue_id == $issue_id and .status == "launched" and .dispatch.status == "executed")] | length == 1
  '

  run_cli_json show_json show_status bd show "${issue_id}" --json
  assert_status "${show_status}" "0" "autonomous-lane verification failure issue show"
  assert_json_value "${show_json}" '.[0].status' "in_progress" "autonomous-lane verification failure issue status"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.dispatch")" = "1" ] || fail "autonomous-lane verification failure lane.dispatch receipt count mismatch for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.autonomous")" = "0" ] || fail "autonomous-lane verification failure lane.autonomous receipt count mismatch for ${issue_id}"

  note "autonomous-lane verification failure: ok"
}

test_autonomous_lane_dispatch_timeout() {
  local repo_root="$1"
  local base_rev="$2"
  local issue_id=""
  local issue_description=""
  local autonomous_json=""
  local autonomous_status=0
  local board_json=""
  local show_json=""
  local show_status=0
  local stub_path=""

  note "autonomous-lane dispatch timeout: begin"
  issue_description=$'Goal:\nExercise autonomous failure when dispatch times out.\n\nVerification:\n- bash -n scripts/tuskd.sh'
  issue_id="$(create_labeled_issue "${repo_root}" "transition autonomous lane dispatch timeout probe" "${issue_description}" "place:tusk,track:core,surface:self-hosting,autonomy:v1-safe")"
  stub_path="$(create_codex_stub_launcher "${repo_root}")"

  run_cli_json autonomous_json autonomous_status \
    env \
      TUSKD_CODEX_LAUNCHER="${stub_path}" \
      TUSKD_DISPATCH_TIMEOUT_SECONDS=1 \
      TUSKD_DISPATCH_KILL_AFTER_SECONDS=1 \
      TUSKD_TEST_STUB_TOUCH_FILE=1 \
      TUSKD_TEST_STUB_SKIP_OUTPUT=1 \
      TUSKD_TEST_STUB_SLEEP_SECONDS=5 \
      tuskd autonomous-lane --repo "${repo_root}" --issue-id "${issue_id}" --base-rev "${base_rev}" --slug autonomous-dispatch-timeout-probe
  assert_status "${autonomous_status}" "1" "autonomous-lane dispatch timeout exit"
  assert_json_value "${autonomous_json}" '.error.message' "autonomous_lane failed during dispatch_lane" "autonomous-lane dispatch timeout message"
  assert_json_value "${autonomous_json}" '.error.details.error.message' "dispatch_lane worker timed out" "autonomous-lane dispatch timeout nested message"
  assert_json_value "${autonomous_json}" '.payload.phase' "dispatch" "autonomous-lane dispatch timeout phase"

  board_json="$(tuskd board-status --repo "${repo_root}")"
  assert_json_jq "${board_json}" "autonomous dispatch timeout lane did not stay inspectable" --arg issue_id "${issue_id}" '
    [.lanes[] | select(.issue_id == $issue_id and .status == "launched" and .dispatch.status == "timed_out")] | length == 1
  '

  run_cli_json show_json show_status bd show "${issue_id}" --json
  assert_status "${show_status}" "0" "autonomous-lane dispatch timeout issue show"
  assert_json_value "${show_json}" '.[0].status' "in_progress" "autonomous-lane dispatch timeout issue status"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.dispatch")" = "1" ] || fail "autonomous-lane dispatch timeout lane.dispatch receipt count mismatch for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.autonomous")" = "0" ] || fail "autonomous-lane dispatch timeout lane.autonomous receipt count mismatch for ${issue_id}"

  note "autonomous-lane dispatch timeout: ok"
}

test_complete_lane() {
  local repo_root="$1"
  local base_rev="$2"
  local issue_id=""
  local claim_json=""
  local claim_status=0
  local launch_json=""
  local launch_status=0
  local workspace_path=""
  local landed_revision=""
  local plan_json=""
  local plan_status=0
  local complete_json=""
  local complete_status=0
  local status_json=""
  local status_exit=0
  local show_json=""
  local show_status=0
  local git_main_commit=""

  note "complete-lane: begin"
  issue_id="$(create_issue "${repo_root}" "transition complete lane probe")"

  run_cli_json claim_json claim_status \
    tuskd claim-issue --repo "${repo_root}" --issue-id "${issue_id}"
  assert_status "${claim_status}" "0" "claim complete lane issue"

  run_cli_json launch_json launch_status \
    tuskd launch-lane --repo "${repo_root}" --issue-id "${issue_id}" --base-rev main --slug complete-lane-probe
  assert_status "${launch_status}" "0" "launch complete lane"

  workspace_path="$(jq -r '.workspace_path // ""' <<<"${launch_json}")"
  [ -n "${workspace_path}" ] || fail "complete lane output missing workspace_path"$'\n'"${launch_json}"

  printf 'complete lane landed probe\n' > "${workspace_path}/complete-lane-probe.txt"
  jj --repository "${workspace_path}" commit -m "complete lane landed probe" >/dev/null
  landed_revision="$(resolve_revision "${workspace_path}" "@-")"

  run_cli_json plan_json plan_status \
    tuskd complete-lane \
      --repo "${repo_root}" \
      --issue-id "${issue_id}" \
      --revision "${landed_revision}" \
      --reason "complete lane test completed" \
      --note "complete lane probe" \
      --plan
  assert_status "${plan_status}" "0" "complete-lane plan"
  assert_json_value "${plan_json}" '.status' "plan" "complete-lane plan status"
  assert_json_value "${plan_json}" '.revision' "${landed_revision}" "complete-lane plan revision"

  run_cli_json complete_json complete_status \
    tuskd complete-lane \
      --repo "${repo_root}" \
      --issue-id "${issue_id}" \
      --revision "${landed_revision}" \
      --reason "complete lane test completed" \
      --note "complete lane probe"
  assert_status "${complete_status}" "0" "complete-lane run"
  assert_json_value "${complete_json}" '.status' "completed" "complete-lane result"
  assert_json_value "${complete_json}" '.land.status' "landed_repaired" "complete-lane landing result"
  assert_json_value "${complete_json}" '.land.receipt.kind' "land.main" "complete-lane landing receipt"
  assert_json_value "${complete_json}" '.cleanup.effective_mode' "remove" "complete-lane cleanup mode"
  assert_json_value "${complete_json}" '.close.issue.status' "closed" "complete-lane closed issue"

  assert_file_missing "${workspace_path}" "complete-lane removed workspace"
  [ "$(lane_count "${repo_root}" "${issue_id}")" = "0" ] || fail "complete-lane left lane state behind for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.handoff")" = "1" ] || fail "complete-lane lane.handoff receipt count mismatch for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.finish")" = "1" ] || fail "complete-lane lane.finish receipt count mismatch for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.complete")" = "1" ] || fail "complete-lane lane.complete receipt count mismatch for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "lane.archive")" = "1" ] || fail "complete-lane lane.archive receipt count mismatch for ${issue_id}"
  [ "$(receipt_count "${repo_root}" "${issue_id}" "issue.close")" = "1" ] || fail "complete-lane issue.close receipt count mismatch for ${issue_id}"

  run_cli_json status_json status_exit \
    tuskd coordinator-status --repo "${repo_root}"
  assert_status "${status_exit}" "0" "coordinator-status after complete-lane"
  assert_json_value "${status_json}" '.status' "in_sync" "coordinator-status after complete-lane state"
  assert_json_value "${status_json}" '.parent_commits[0]' "${landed_revision}" "coordinator-status after complete-lane parent"

  git_main_commit="$(git -C "${repo_root}" rev-parse --verify refs/heads/main)"
  [ "${git_main_commit}" = "${landed_revision}" ] || fail "complete-lane left git main at ${git_main_commit}, expected ${landed_revision}"

  run_cli_json show_json show_status \
    bd show "${issue_id}" --json
  assert_status "${show_status}" "0" "bd show after complete-lane"
  assert_json_value "${show_json}" '.[0].status' "closed" "complete-lane issue status"

  note "complete-lane: ok"
}

test_coordinator_repair() {
  local repo_root="$1"
  local base_rev="$2"
  local landing_name="coordinator-repair-land"
  local landing_path="${repo_root}/.jj-workspaces/${landing_name}"
  local landed_revision=""
  local status_json=""
  local status_exit=0
  local repair_plan_json=""
  local repair_plan_status=0
  local repair_json=""
  local repair_status=0

  note "coordinator-repair: begin"

  printf '\ncoordinator repair probe\n' >> "${repo_root}/AGENTS.md"

  jj --repository "${repo_root}" workspace add "${landing_path}" --name "${landing_name}" -r "${base_rev}" >/dev/null
  printf 'coordinator repair landed probe\n' > "${landing_path}/coordinator-repair-probe.txt"
  jj --repository "${landing_path}" commit -m "coordinator repair landed probe" >/dev/null
  landed_revision="$(resolve_revision "${landing_path}" "@-")"
  jj --repository "${repo_root}" bookmark move main --to "${landed_revision}" >/dev/null

  run_cli_json status_json status_exit \
    tuskd coordinator-status --repo "${repo_root}"
  assert_status "${status_exit}" "1" "coordinator-status should detect drift"
  assert_json_value "${status_json}" '.drifted' "true" "coordinator-status drifted"
  assert_json_value "${status_json}" '.needs_repair' "true" "coordinator-status needs repair"

  run_cli_json repair_plan_json repair_plan_status \
    tuskd repair-coordinator --repo "${repo_root}" --target-rev main --plan
  assert_status "${repair_plan_status}" "0" "repair-coordinator plan"
  assert_json_value "${repair_plan_json}" '.payload.status' "plan" "repair-coordinator plan status"

  run_cli_json repair_json repair_status \
    tuskd repair-coordinator --repo "${repo_root}" --target-rev main --note "transition probe"
  assert_status "${repair_status}" "0" "repair-coordinator run"
  assert_json_value "${repair_json}" '.payload.status' "repaired" "repair-coordinator result"
  assert_json_value "${repair_json}" '.payload.after.drifted' "false" "repair-coordinator cleared drift"
  assert_json_value "${repair_json}" '.payload.after.conflicted' "false" "repair-coordinator avoided conflicts"
  assert_json_value "${repair_json}" '.payload.after.parent_commits[0]' "${landed_revision}" "repair-coordinator updated parent"

  run_cli_json status_json status_exit \
    tuskd coordinator-status --repo "${repo_root}"
  assert_status "${status_exit}" "0" "coordinator-status after repair"
  assert_json_value "${status_json}" '.status' "in_sync" "coordinator-status after repair state"

  forget_and_remove_workspace "${repo_root}" "${landing_name}" "${landing_path}"
  note "coordinator-repair: ok"
}

test_land_main() {
  local repo_root="$1"
  local landing_name="land-main-probe"
  local landing_path="${repo_root}/.jj-workspaces/${landing_name}"
  local landed_revision=""
  local plan_json=""
  local plan_status=0
  local land_json=""
  local land_status=0
  local status_json=""
  local status_exit=0
  local git_main_commit=""
  local land_receipt_count_before=""
  local land_receipt_count=""

  note "land-main: begin"

  printf '\nland-main probe\n' >> "${repo_root}/AGENTS.md"

  land_receipt_count_before="$(
    jq -Rsc \
      '
        split("\n")
        | map(select(length > 0) | fromjson?)
        | map(select(.kind == "land.main"))
        | length
      ' <"$(receipts_path "${repo_root}")"
  )"

  jj --repository "${repo_root}" workspace add "${landing_path}" --name "${landing_name}" -r main >/dev/null
  printf 'land-main landed probe\n' > "${landing_path}/land-main-probe.txt"
  jj --repository "${landing_path}" commit -m "land-main landed probe" >/dev/null
  landed_revision="$(resolve_revision "${landing_path}" "@-")"

  run_cli_json plan_json plan_status \
    tuskd land-main --repo "${repo_root}" --revision "${landed_revision}" --plan
  assert_status "${plan_status}" "0" "land-main plan"
  assert_json_value "${plan_json}" '.payload.status' "plan" "land-main plan status"
  assert_json_value "${plan_json}" '.payload.target_commit' "${landed_revision}" "land-main plan target"
  assert_json_value "${plan_json}" '.payload.needs_repair_after_land' "true" "land-main plan repair flag"

  run_cli_json land_json land_status \
    tuskd land-main --repo "${repo_root}" --revision "${landed_revision}" --note "transition probe"
  assert_status "${land_status}" "0" "land-main run"
  assert_json_value "${land_json}" '.payload.status' "landed_repaired" "land-main result"
  assert_json_value "${land_json}" '.payload.after.coordinator.status' "in_sync" "land-main synced coordinator"
  assert_json_value "${land_json}" '.payload.after.coordinator.parent_commits[0]' "${landed_revision}" "land-main updated coordinator parent"
  assert_json_value "${land_json}" '.payload.after.git_main.commit' "${landed_revision}" "land-main exported git main"
  assert_json_value "${land_json}" '.payload.repair.status' "repaired" "land-main repair result"

  run_cli_json status_json status_exit \
    tuskd coordinator-status --repo "${repo_root}"
  assert_status "${status_exit}" "0" "coordinator-status after land-main"
  assert_json_value "${status_json}" '.status' "in_sync" "coordinator-status after land-main state"
  assert_json_value "${status_json}" '.parent_commits[0]' "${landed_revision}" "coordinator-status after land-main parent"

  git_main_commit="$(git -C "${repo_root}" rev-parse --verify refs/heads/main)"
  [ "${git_main_commit}" = "${landed_revision}" ] || fail "land-main left git main at ${git_main_commit}, expected ${landed_revision}"

  land_receipt_count="$(
    jq -Rsc \
      '
        split("\n")
        | map(select(length > 0) | fromjson?)
        | map(select(.kind == "land.main"))
        | length
      ' <"$(receipts_path "${repo_root}")"
  )"
  [ "${land_receipt_count}" = "$((land_receipt_count_before + 1))" ] || fail "land-main receipt count mismatch: ${land_receipt_count} (before ${land_receipt_count_before})"

  forget_and_remove_workspace "${repo_root}" "${landing_name}" "${landing_path}"
  note "land-main: ok"
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

  bd init -p tusk --server >/dev/null
  tuskd ensure --repo "${repo_root}" >/dev/null
  ensure_local_main_bookmark "${repo_root}" "${base_rev}"

  test_lifecycle_guards "${repo_root}" "${base_rev}"
  test_concurrent_claims "${repo_root}"
  test_concurrent_child_creates "${repo_root}"
  test_child_create_identity_mismatch "${repo_root}"
  test_launch_rollback "${repo_root}" "${base_rev}"
  test_dispatch_lane "${repo_root}" "${base_rev}"
  test_dispatch_lane_timeout "${repo_root}" "${base_rev}"
  test_autonomous_lane_missing_revision "${repo_root}" "${base_rev}"
  test_autonomous_lane_verification_failure "${repo_root}" "${base_rev}"
  test_autonomous_lane_dispatch_timeout "${repo_root}" "${base_rev}"
  test_autonomous_lane_success "${repo_root}" "${base_rev}"
  test_compact_lane_remove "${repo_root}" "${base_rev}"
  test_compact_lane_quarantine "${repo_root}" "${base_rev}"
  test_coordinator_repair "${repo_root}" "${base_rev}"
  test_land_main "${repo_root}"
  test_complete_lane "${repo_root}" "${base_rev}"

  note "all transition tests passed"
}

run_outer_harness() {
  local source_repo="$1"
  local base_rev="$2"
  local keep_temp="$3"
  local source_git_root=""
  local source_base_rev=""
  local temp_root=""
  local temp_repo=""
  local temp_base_rev=""
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
  source_base_rev="$(resolve_existing_base_rev "${source_repo}" "${base_rev}")"
  temp_base_rev="$(resolve_existing_base_rev "${temp_repo}" "${base_rev}")"

  jj --repository "${temp_repo}" new "${temp_base_rev}" -m "tuskd-transition-tests: base" >/dev/null

  jj --repository "${source_repo}" diff --git --from "${source_base_rev}" --to @ >"${patch_path}"
  if [ -s "${patch_path}" ]; then
    diff_is_empty=false
    git -C "${temp_repo}" apply --whitespace=nowarn "${patch_path}"
  fi

  if [ "${diff_is_empty}" = true ]; then
    note "source diff from ${source_base_rev} is empty; testing base clone"
  fi

  if ! (
      unset TUSK_CHECKOUT_ROOT TUSK_TRACKER_ROOT DEVENV_ROOT BEADS_WORKSPACE_ROOT CODEX_HOME
      cd "${temp_repo}"
      TUSKD_TRANSITION_TESTS_BASE_REV="${temp_base_rev}" \
        nix develop --no-pure-eval "path:${temp_repo}" \
          -c bash "$0" --inner-repo "${temp_repo}" --host-state-root "${host_state_root}"
    ); then
    cleanup_preserve_temp=true
    fail "transition tests failed"
  fi
}

main() {
  local source_repo="."
  local base_rev="${TUSKD_TRANSITION_TESTS_BASE_REV:-main}"
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
