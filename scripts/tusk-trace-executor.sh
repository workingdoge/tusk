#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  tusk-trace-executor --realization ID [--repo PATH] [--note TEXT] [--plan]

Options:
  --realization ID  Stable realization id to trace.
  --repo PATH       Checkout or tracker path. Defaults to the current repo context.
  --note TEXT       Optional operator note stored on the emitted receipt.
  --plan            Print the planned trace payload instead of appending a receipt.
  --help            Show this help text.
EOF
}

repo_arg=""
realization_id=""
note=""
plan_only=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --repo)
      repo_arg="${2:?--repo requires a path}"
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
      printf 'tusk-trace-executor: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ -z "${realization_id}" ]; then
  printf 'tusk-trace-executor: --realization is required\n' >&2
  usage >&2
  exit 1
fi

export TUSK_PATHS_SH
# shellcheck disable=SC1090
source "$TUSK_PATHS_SH"

checkout_root="$(tusk_resolve_checkout_root "${repo_arg:-$PWD}")"
tracker_root="$(tusk_resolve_tracker_root "${repo_arg:-$PWD}")"
tusk_export_runtime_roots "$checkout_root" "$tracker_root"

graph_json="$(${NIX_BIN} eval --json "path:${checkout_root}#tusk")"

trace_plan="$(
  printf '%s' "${graph_json}" | ${JQ_BIN} -ec \
    --arg realization_id "${realization_id}" \
    --arg note "${note}" '
      . as $graph
      | ($graph.realizations[$realization_id] // error("unknown realization `" + $realization_id + "`")) as $realization
      | ($graph.admission.realizations.byRealization[$realization_id] // error("missing realization admission for `" + $realization_id + "`")) as $realization_admission
      | if $realization_admission.status != "admitted" then
          error("realization `" + $realization_id + "` is not admitted")
        else
          .
        end
      | ($graph.effects[$realization.effect] // error("missing effect `" + $realization.effect + "`")) as $effect
      | ($graph.executors[$realization.executor] // error("missing executor `" + $realization.executor + "`")) as $executor
      | (
          [ $graph.drivers[][] | select(.id == $realization.driver) ][0]
          // error("missing driver `" + $realization.driver + "`")
        ) as $driver
      | {
          realization_id: $realization.id,
          receipt_kind: $realization.receipt.kind,
          payload: {
            status: "realized",
            mode: "local-trace",
            note: (if $note == "" then null else $note end),
            realization: $realization,
            realization_admission: $realization_admission,
            effect: $effect,
            executor: $executor,
            driver: $driver,
            inputs: [ $effect.inputs[] | $graph.witnesses[.] ],
            required_base: [ $effect.requires.base[] | $graph.base[.] ],
            receipt_expectation: $realization.receipt,
            transition: {
              target: $effect.intent.target,
              action: $effect.intent.action,
              kind: $effect.intent.kind
            }
          }
        }
    '
)"

if [ "${plan_only}" -eq 1 ]; then
  printf '%s\n' "${trace_plan}"
  exit 0
fi

receipt_kind="$(printf '%s' "${trace_plan}" | ${JQ_BIN} -r '.receipt_kind')"
payload_json="$(printf '%s' "${trace_plan}" | ${JQ_BIN} -c '.payload')"

exec ${TUSKD_CORE_BIN} receipt append \
  --repo "${tracker_root}" \
  --kind "${receipt_kind}" \
  --payload "${payload_json}"
