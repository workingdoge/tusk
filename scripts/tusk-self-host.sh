#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  tusk-self-host [--repo PATH] [--checkout PATH] [--realization ID] [--note TEXT] [--plan]

Options:
  --repo PATH         Canonical tracker root. Defaults to the current repo context.
  --checkout PATH     Checkout root to build and verify. Defaults to the current checkout context.
  --realization ID    Self-host realization id. Defaults to self.trace-core-health.local.
  --note TEXT         Optional operator note stored on emitted receipts.
  --plan              Print the execution plan instead of running it.
  --help              Show this help text.
EOF
}

repo_arg=""
checkout_arg=""
realization_id="self.trace-core-health.local"
note=""
plan_only=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      repo_arg="${2:?--repo requires a path}"
      shift 2
      ;;
    --checkout)
      checkout_arg="${2:?--checkout requires a path}"
      shift 2
      ;;
    --realization)
      realization_id="${2:?--realization requires an id}"
      shift 2
      ;;
    --note)
      note="${2:?--note requires text}"
      shift 2
      ;;
    --plan)
      plan_only=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'tusk-self-host: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

export TUSK_PATHS_SH
# shellcheck disable=SC1090
source "$TUSK_PATHS_SH"

checkout_probe="${checkout_arg:-${repo_arg:-$PWD}}"
tracker_probe="${repo_arg:-${checkout_arg:-$PWD}}"
checkout_root="$(tusk_resolve_checkout_root "${checkout_probe}")"
tracker_root="$(tusk_resolve_tracker_root "${tracker_probe}")"
tusk_export_runtime_roots "$checkout_root" "$tracker_root"

graph_json="$(${NIX_BIN} eval --json "path:${checkout_root}#tusk")"

plan_json="$(
  printf '%s' "${graph_json}" | ${JQ_BIN} -ec \
    --arg realization_id "${realization_id}" '
      . as $graph
      | ($graph.realizations[$realization_id] // error("unknown realization `" + $realization_id + "`")) as $realization
      | ($graph.admission.realizations.byRealization[$realization_id] // error("missing realization admission for `" + $realization_id + "`")) as $realization_admission
      | if $realization_admission.status != "admitted" then
          error("realization `" + $realization_id + "` is not admitted")
        else
          .
        end
      | ($graph.effects[$realization.effect] // error("missing effect `" + $realization.effect + "`")) as $effect
      | {
          realization_id: $realization.id,
          effect_id: $effect.id,
          intent: $effect.intent,
          required_base_ids: $effect.requires.base,
          steps: [
            $effect.requires.base[]
            | $graph.base[.]
            | if .command != null then
                {
                  base_id: .id,
                  mode: "command",
                  locator: .command,
                  description: .description
                }
              elif .installable != null then
                {
                  base_id: .id,
                  mode: "installable",
                  locator: .installable,
                  description: .description
                }
              else
                {
                  base_id: .id,
                  mode: "witness-only",
                  locator: null,
                  description: .description
                }
              end
          ]
        }
    '
)"

if [ "${plan_only}" -eq 1 ]; then
  printf '%s\n' "${plan_json}"
  exit 0
fi

results_file="$(mktemp)"
cleanup() {
  rm -f "${results_file}"
}
trap cleanup EXIT

execute_step() {
  local mode="$1"
  local locator="$2"

  case "${mode}" in
    command)
      (
        cd "${checkout_root}"
        export TUSK_CHECKOUT_ROOT="${checkout_root}"
        export TUSK_TRACKER_ROOT="${tracker_root}"
        export DEVENV_ROOT="${checkout_root}"
        export BEADS_WORKSPACE_ROOT="${tracker_root}"
        bash -lc "${locator}"
      )
      ;;
    installable)
      local build_ref="${locator}"
      if [ "${build_ref#.#}" != "${build_ref}" ]; then
        build_ref="path:${checkout_root}#${build_ref#.#}"
      fi
      ${NIX_BIN} build "${build_ref}"
      ;;
    witness-only)
      return 0
      ;;
    *)
      printf 'unsupported execution mode: %s\n' "${mode}" >&2
      return 1
      ;;
  esac
}

run_step_capture() {
  local mode="$1"
  local locator="$2"
  local output_file="$3"
  local exit_code=0

  if execute_step "${mode}" "${locator}" >"${output_file}" 2>&1; then
    exit_code=0
  else
    exit_code=$?
  fi

  return "${exit_code}"
}

append_run_receipt() {
  local status="$1"
  local failure_json="$2"
  local trace_receipt_json="$3"

  local base_results_json
  if [ -s "${results_file}" ]; then
    base_results_json="$(${JQ_BIN} -cs '.' "${results_file}")"
  else
    base_results_json='[]'
  fi

  local payload_json
  payload_json="$(
    ${JQ_BIN} -cn \
      --arg realization_id "${realization_id}" \
      --arg status "${status}" \
      --arg note "${note}" \
      --arg checkout_root "${checkout_root}" \
      --arg tracker_root "${tracker_root}" \
      --argjson plan "${plan_json}" \
      --argjson base_results "${base_results_json}" \
      --argjson failure "${failure_json}" \
      --argjson trace_receipt "${trace_receipt_json}" '
        {
          realization_id: $realization_id,
          status: $status,
          mode: "local-build",
          note: (if $note == "" then null else $note end),
          checkout_root: $checkout_root,
          tracker_root: $tracker_root,
          plan: $plan,
          base_results: $base_results,
          failure: (if $failure == null then null else $failure end),
          trace_receipt: (if $trace_receipt == null then null else {
            kind: $trace_receipt.kind,
            timestamp: $trace_receipt.timestamp,
            repo_root: $trace_receipt.repo_root
          } end)
        }
      '
  )"

  ${TUSKD_CORE_BIN} receipt append \
    --repo "${tracker_root}" \
    --kind "self_host.run" \
    --payload "${payload_json}"
}

while IFS= read -r step_json; do
  [ -n "${step_json}" ] || continue

  base_id="$(${JQ_BIN} -r '.base_id' <<<"${step_json}")"
  mode="$(${JQ_BIN} -r '.mode' <<<"${step_json}")"
  locator="$(${JQ_BIN} -r '.locator // ""' <<<"${step_json}")"
  description="$(${JQ_BIN} -r '.description // ""' <<<"${step_json}")"
  output_file="$(mktemp)"

  if run_step_capture "${mode}" "${locator}" "${output_file}"; then
    ${JQ_BIN} -cn \
      --arg base_id "${base_id}" \
      --arg mode "${mode}" \
      --arg locator "${locator}" \
      --arg description "${description}" \
      '{
        base_id: $base_id,
        mode: $mode,
        locator: (if $locator == "" then null else $locator end),
        description: (if $description == "" then null else $description end),
        status: "passed"
      }' >>"${results_file}"
    rm -f "${output_file}"
    continue
  fi

  exit_code=$?
  output="$(cat "${output_file}")"
  rm -f "${output_file}"
  summary="$(
    printf '%s\n' "${output}" | tail -n 20 | ${JQ_BIN} -Rcs 'split("\n") | map(select(length > 0))'
  )"
  ${JQ_BIN} -cn \
    --arg base_id "${base_id}" \
    --arg mode "${mode}" \
    --arg locator "${locator}" \
    --arg description "${description}" \
    --argjson output_tail "${summary}" \
    --argjson exit_code "${exit_code}" \
    '{
      base_id: $base_id,
      mode: $mode,
      locator: (if $locator == "" then null else $locator end),
      description: (if $description == "" then null else $description end),
      status: "failed",
      exit_code: $exit_code,
      output_tail: $output_tail
    }' >>"${results_file}"

  failure_json="$(
    ${JQ_BIN} -cn \
      --arg base_id "${base_id}" \
      --arg mode "${mode}" \
      --arg locator "${locator}" \
      --argjson exit_code "${exit_code}" \
      --argjson output_tail "${summary}" \
      '{
        base_id: $base_id,
        mode: $mode,
        locator: (if $locator == "" then null else $locator end),
        exit_code: $exit_code,
        output_tail: $output_tail
      }'
  )"
  append_run_receipt "failed" "${failure_json}" "null" >/dev/null
  exit "${exit_code}"
done < <(${JQ_BIN} -c '.steps[]' <<<"${plan_json}")

trace_note="${note:-self-host verification completed}"
trace_receipt_json="$(
  export TUSK_CHECKOUT_ROOT="${checkout_root}"
  export TUSK_TRACKER_ROOT="${tracker_root}"
  export DEVENV_ROOT="${checkout_root}"
  export BEADS_WORKSPACE_ROOT="${tracker_root}"
  "${TUSK_TRACE_EXECUTOR_BIN}" --realization "${realization_id}" --note "${trace_note}"
)"

append_run_receipt "passed" "null" "${trace_receipt_json}"
