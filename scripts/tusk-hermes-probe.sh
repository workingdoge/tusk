#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  tusk-hermes-probe [--repo PATH] [--checkout PATH] [--backend podman] [--image REF]
                    [--machine NAME] [--machine-cpus N] [--machine-memory MIB]
                    [--machine-disk-size GIB] [--network default|none]
                    [--installer-url URL] [--branch NAME] [--probe-command CMD]
                    [--pass-env NAME]... [--run-root PATH] [--note TEXT] [--plan]

Options:
  --repo PATH               Canonical tracker root. Defaults to the current repo context.
  --checkout PATH           Checkout root to attribute as the launch context.
  --backend podman          Local runtime backend. Only `podman` is supported today.
  --image REF               Container image to use. Defaults to `docker.io/library/debian:bookworm-slim`.
  --machine NAME            Podman machine name on macOS. Defaults to `tusk-hermes`.
  --machine-cpus N          Podman machine CPU count on macOS. Defaults to `4`.
  --machine-memory MIB      Podman machine memory in MiB on macOS. Defaults to `4096`.
  --machine-disk-size GIB   Podman machine disk size in GiB on macOS. Defaults to `40`.
  --network MODE            `default` or `none`. Defaults to `default`.
  --installer-url URL       Hermes installer URL. Defaults to the upstream install script.
  --branch NAME             Hermes git branch for the installer. Defaults to `main`.
  --probe-command CMD       Command to run after install. Defaults to `hermes --help`.
  --pass-env NAME           Forward a host environment variable into the isolated runtime.
                            Repeat to forward multiple names.
  --run-root PATH           Override the host run root. Defaults under `TUSK_SCRATCH_ROOT`.
  --note TEXT               Optional operator note stored on the emitted receipt.
  --plan                    Print the execution plan instead of running it.
  --help                    Show this help text.
EOF
}

repo_arg=""
checkout_arg=""
backend="podman"
image="docker.io/library/debian:bookworm-slim"
machine_name="tusk-hermes"
machine_cpus="4"
machine_memory="4096"
machine_disk_size="40"
network_mode="default"
installer_url="https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh"
branch="main"
probe_command="hermes --help"
run_root=""
note=""
plan_only=0
pass_env_names=()

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
    --backend)
      backend="${2:?--backend requires a value}"
      shift 2
      ;;
    --image)
      image="${2:?--image requires a value}"
      shift 2
      ;;
    --machine)
      machine_name="${2:?--machine requires a value}"
      shift 2
      ;;
    --machine-cpus)
      machine_cpus="${2:?--machine-cpus requires a value}"
      shift 2
      ;;
    --machine-memory)
      machine_memory="${2:?--machine-memory requires a value}"
      shift 2
      ;;
    --machine-disk-size)
      machine_disk_size="${2:?--machine-disk-size requires a value}"
      shift 2
      ;;
    --network)
      network_mode="${2:?--network requires a value}"
      shift 2
      ;;
    --installer-url)
      installer_url="${2:?--installer-url requires a value}"
      shift 2
      ;;
    --branch)
      branch="${2:?--branch requires a value}"
      shift 2
      ;;
    --probe-command)
      probe_command="${2:?--probe-command requires a value}"
      shift 2
      ;;
    --pass-env)
      pass_env_names+=("${2:?--pass-env requires a variable name}")
      shift 2
      ;;
    --run-root)
      run_root="${2:?--run-root requires a path}"
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
      printf 'tusk-hermes-probe: unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [ "${backend}" != "podman" ]; then
  printf 'tusk-hermes-probe: unsupported backend: %s\n' "${backend}" >&2
  exit 1
fi

case "${network_mode}" in
  default|none)
    ;;
  *)
    printf 'tusk-hermes-probe: unsupported network mode: %s\n' "${network_mode}" >&2
    exit 1
    ;;
esac

for numeric_value in "${machine_cpus}" "${machine_memory}" "${machine_disk_size}"; do
  if ! [[ "${numeric_value}" =~ ^[0-9]+$ ]]; then
    printf 'tusk-hermes-probe: numeric machine settings must be integers\n' >&2
    exit 1
  fi
done

if [ -z "${TUSK_HERMES_PROBE_CONTAINER_SH:-}" ] || [ ! -r "${TUSK_HERMES_PROBE_CONTAINER_SH:-}" ]; then
  printf 'tusk-hermes-probe: TUSK_HERMES_PROBE_CONTAINER_SH must point to a readable container launcher\n' >&2
  exit 1
fi

export TUSK_PATHS_SH
# shellcheck disable=SC1090
source "$TUSK_PATHS_SH"

tusk_sanitize_slug() {
  printf '%s' "$1" | tr '/: ' '---' | tr -cd '[:alnum:]._\n-'
}

json_array_from_lines() {
  if [ "$#" -eq 0 ]; then
    printf '[]\n'
    return
  fi

  printf '%s\n' "$@" | ${JQ_BIN} -Rsc 'split("\n") | map(select(length > 0))'
}

tail_json_lines() {
  local path="$1"
  local count="${2:-20}"

  if [ ! -f "${path}" ]; then
    printf '[]\n'
    return
  fi

  tail -n "${count}" "${path}" | ${JQ_BIN} -Rsc 'split("\n") | map(select(length > 0))'
}

read_optional_line() {
  local path="$1"

  if [ -f "${path}" ]; then
    head -n 1 "${path}"
  fi
}

checkout_probe="${checkout_arg:-${repo_arg:-$PWD}}"
tracker_probe="${repo_arg:-${checkout_arg:-$PWD}}"
checkout_root="$(tusk_resolve_checkout_root "${checkout_probe}")"
tracker_root="$(tusk_resolve_tracker_root "${tracker_probe}")"
tusk_export_runtime_roots "${checkout_root}" "${tracker_root}"

workspace_name="$(basename "${checkout_root}")"
workspace_slug="$(tusk_sanitize_slug "${workspace_name}")"
timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
run_id="${workspace_slug}-${timestamp}-$$"

: "${XDG_CACHE_HOME:="$HOME/.cache"}"
if [ -z "${run_root}" ]; then
  if [ -n "${TUSK_SCRATCH_ROOT:-}" ]; then
    scratch_root="${TUSK_SCRATCH_ROOT}"
  else
    scratch_root="${XDG_CACHE_HOME}/tusk-scratch/$(tusk_sanitize_slug "${checkout_root}")"
  fi
  run_root="${scratch_root}/hermes-probe/${run_id}"
fi

if [ "${plan_only}" -eq 0 ]; then
  mkdir -p "${run_root}"
  run_root="$(cd "${run_root}" && pwd)"
fi

artifacts_dir="${run_root}/artifacts"
runtime_home="${run_root}/home"
plan_path="${run_root}/plan.json"
receipt_path="${run_root}/receipt.json"
machine_log="${run_root}/machine.log"
container_log="${run_root}/container.log"
machine_inspect_path="${artifacts_dir}/machine-inspect.json"
container_script_host_path="${run_root}/tusk-hermes-probe-container.sh"
container_script_guest_path="/usr/local/bin/tusk-hermes-probe-container.sh"
container_name="tusk-hermes-${workspace_slug}-$$"
install_dir="/runtime/home/.hermes/hermes-agent"

requested_forward_names_json="$(json_array_from_lines "${pass_env_names[@]}")"
forwarded_names=()
podman_env_args=()
for name in "${pass_env_names[@]}"; do
  if ! [[ "${name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    printf 'tusk-hermes-probe: invalid --pass-env name: %s\n' "${name}" >&2
    exit 1
  fi

  if [ -n "${!name-}" ]; then
    forwarded_names+=("${name}")
    podman_env_args+=(--env "${name}=${!name}")
  fi
done
forwarded_names_json="$(json_array_from_lines "${forwarded_names[@]}")"
internal_names_json="$(
  json_array_from_lines \
    HOME \
    XDG_CACHE_HOME \
    HERMES_INSTALL_DIR \
    TUSK_HERMES_INSTALLER_URL \
    TUSK_HERMES_BRANCH \
    TUSK_HERMES_PROBE_COMMAND
)"

runtime_kind="container"
machine_required_json="false"
if [ "$(uname -s)" = "Darwin" ]; then
  runtime_kind="vm-backed-container"
  machine_required_json="true"
fi

render_plan_json() {
  ${JQ_BIN} -cn \
    --arg run_id "${run_id}" \
    --arg checkout_root "${checkout_root}" \
    --arg tracker_root "${tracker_root}" \
    --arg workspace_name "${workspace_name}" \
    --arg backend "${backend}" \
    --arg runtime_kind "${runtime_kind}" \
    --arg image "${image}" \
    --arg machine_name "${machine_name}" \
    --arg machine_cpus "${machine_cpus}" \
    --arg machine_memory "${machine_memory}" \
    --arg machine_disk_size "${machine_disk_size}" \
    --arg network_mode "${network_mode}" \
    --arg installer_url "${installer_url}" \
    --arg branch "${branch}" \
    --arg install_dir "${install_dir}" \
    --arg probe_command "${probe_command}" \
    --arg run_root "${run_root}" \
    --arg artifacts_dir "${artifacts_dir}" \
    --arg runtime_home "${runtime_home}" \
    --arg container_name "${container_name}" \
    --arg container_script_host_path "${container_script_host_path}" \
    --arg container_script_guest_path "${container_script_guest_path}" \
    --arg plan_path "${plan_path}" \
    --arg receipt_path "${receipt_path}" \
    --arg machine_log "${machine_log}" \
    --arg container_log "${container_log}" \
    --arg machine_inspect_path "${machine_inspect_path}" \
    --arg note "${note}" \
    --argjson machine_required "${machine_required_json}" \
    --argjson requested_forward_names "${requested_forward_names_json}" \
    --argjson forwarded_names "${forwarded_names_json}" \
    --argjson internal_names "${internal_names_json}" \
    '{
      run_id: $run_id,
      source: {
        checkout_root: $checkout_root,
        tracker_root: $tracker_root,
        workspace_name: $workspace_name
      },
      runtime: {
        backend: $backend,
        kind: $runtime_kind,
        image: $image,
        container_name: $container_name,
        machine: {
          name: $machine_name,
          cpus: ($machine_cpus | tonumber),
          memory_mib: ($machine_memory | tonumber),
          disk_gib: ($machine_disk_size | tonumber),
          required: $machine_required
        }
      },
      mounts: [
        {
          name: "launcher_script",
          host_path: $container_script_host_path,
          guest_path: $container_script_guest_path,
          mode: "ro"
        },
        {
          name: "runtime_home",
          host_path: $runtime_home,
          guest_path: "/runtime/home",
          mode: "rw"
        },
        {
          name: "artifacts",
          host_path: $artifacts_dir,
          guest_path: "/artifacts",
          mode: "rw"
        }
      ],
      environment_policy: {
        requested_forward_names: $requested_forward_names,
        forwarded_names: $forwarded_names,
        internal_names: $internal_names
      },
      network_policy: {
        mode: $network_mode
      },
      upstream: {
        mode: "installer",
        url: $installer_url,
        branch: $branch,
        install_dir: $install_dir
      },
      probe_command: $probe_command,
      note: (if $note == "" then null else $note end),
      receipt: {
        kind: "hermes.probe",
        append: true,
        file: $receipt_path
      },
      reattach: {
        mode: "artifact-only",
        run_root: $run_root,
        artifact_root: $artifacts_dir,
        logs: {
          machine: $machine_log,
          container: $container_log,
          machine_inspect: $machine_inspect_path
        },
        outputs: {
          plan: $plan_path,
          hermes_path: ($artifacts_dir + "/hermes-path.txt"),
          install_dir: ($artifacts_dir + "/install-dir.txt"),
          upstream_revision: ($artifacts_dir + "/upstream-revision.txt"),
          system_setup_log: ($artifacts_dir + "/system-setup.log"),
          install_log: ($artifacts_dir + "/install.log"),
          probe_log: ($artifacts_dir + "/probe.log")
        }
      }
    }'
}

plan_json="$(render_plan_json)"
if [ "${plan_only}" -eq 1 ]; then
  printf '%s\n' "${plan_json}"
  exit 0
fi

mkdir -p "${artifacts_dir}" "${runtime_home}"
printf '%s\n' "${plan_json}" >"${plan_path}"

machine_observation_json="null"

append_probe_receipt() {
  local status="$1"
  local failure_json="$2"
  local hermes_path=""
  local installed_dir=""
  local upstream_revision=""
  local payload_json=""
  local receipt_json=""

  hermes_path="$(read_optional_line "${artifacts_dir}/hermes-path.txt")"
  installed_dir="$(read_optional_line "${artifacts_dir}/install-dir.txt")"
  upstream_revision="$(read_optional_line "${artifacts_dir}/upstream-revision.txt")"

  payload_json="$(
    ${JQ_BIN} -cn \
      --arg run_id "${run_id}" \
      --arg status "${status}" \
      --arg note "${note}" \
      --arg checkout_root "${checkout_root}" \
      --arg tracker_root "${tracker_root}" \
      --arg run_root "${run_root}" \
      --arg hermes_path "${hermes_path}" \
      --arg installed_dir "${installed_dir}" \
      --arg upstream_revision "${upstream_revision}" \
      --arg plan_path "${plan_path}" \
      --arg artifacts_dir "${artifacts_dir}" \
      --arg runtime_home "${runtime_home}" \
      --arg container_log "${container_log}" \
      --arg machine_log "${machine_log}" \
      --arg machine_inspect_path "${machine_inspect_path}" \
      --argjson plan "${plan_json}" \
      --argjson failure "${failure_json}" \
      --argjson machine_observation "${machine_observation_json}" '
        {
          run_id: $run_id,
          status: $status,
          note: (if $note == "" then null else $note end),
          checkout_root: $checkout_root,
          tracker_root: $tracker_root,
          plan: $plan,
          runtime_observation: {
            machine: (if $machine_observation == null then null else $machine_observation end),
            run_root: $run_root,
            artifacts_dir: $artifacts_dir,
            runtime_home: $runtime_home,
            logs: {
              machine: $machine_log,
              container: $container_log,
              machine_inspect: $machine_inspect_path
            }
          },
          artifacts: {
            plan: $plan_path,
            hermes_path: (if $hermes_path == "" then null else $hermes_path end),
            install_dir: (if $installed_dir == "" then null else $installed_dir end),
            upstream_revision: (if $upstream_revision == "" then null else $upstream_revision end),
            install_log: ($artifacts_dir + "/install.log"),
            system_setup_log: ($artifacts_dir + "/system-setup.log"),
            probe_log: ($artifacts_dir + "/probe.log")
          },
          failure: (if $failure == null then null else $failure end)
        }
      '
  )"

  receipt_json="$(
    ${TUSKD_CORE_BIN} receipt append \
      --repo "${tracker_root}" \
      --kind "hermes.probe" \
      --payload "${payload_json}"
  )"
  printf '%s\n' "${receipt_json}" >"${receipt_path}"
}

append_failure_and_exit() {
  local phase="$1"
  local exit_code="$2"
  local log_path="$3"
  local message="$4"
  local summary_json=""
  local failure_json=""

  summary_json="$(tail_json_lines "${log_path}" 20)"
  failure_json="$(
    ${JQ_BIN} -cn \
      --arg phase "${phase}" \
      --arg exit_code "${exit_code}" \
      --arg log_path "${log_path}" \
      --arg message "${message}" \
      --argjson summary "${summary_json}" '
        {
          phase: $phase,
          exit_code: ($exit_code | tonumber),
          log_path: (if $log_path == "" then null else $log_path end),
          message: (if $message == "" then null else $message end),
          summary: $summary
        }
      '
  )"

  append_probe_receipt "failed" "${failure_json}"
  exit "${exit_code}"
}

ensure_podman_machine() {
  local inspect_json=""
  local machine_state=""
  local exit_code=0

  if [ "$(uname -s)" != "Darwin" ]; then
    return 0
  fi

  : >"${machine_log}"

  if inspect_json="$(podman machine inspect "${machine_name}" 2>>"${machine_log}")"; then
    :
  else
    if podman machine init \
      --cpus "${machine_cpus}" \
      --memory "${machine_memory}" \
      --disk-size "${machine_disk_size}" \
      "${machine_name}" >>"${machine_log}" 2>&1; then
      :
    else
      exit_code=$?
      append_failure_and_exit "machine.init" "${exit_code}" "${machine_log}" "failed to initialize the podman machine"
    fi

    if ! inspect_json="$(podman machine inspect "${machine_name}" 2>>"${machine_log}")"; then
      exit_code=$?
      append_failure_and_exit "machine.inspect" "${exit_code}" "${machine_log}" "failed to inspect the podman machine after init"
    fi
  fi

  printf '%s\n' "${inspect_json}" >"${machine_inspect_path}"
  machine_state="$(${JQ_BIN} -r '.[0].State // .[0].state // ""' "${machine_inspect_path}" 2>/dev/null || true)"
  if [ "${machine_state}" != "running" ]; then
    if podman machine start "${machine_name}" >>"${machine_log}" 2>&1; then
      :
    else
      exit_code=$?
      append_failure_and_exit "machine.start" "${exit_code}" "${machine_log}" "failed to start the podman machine"
    fi
    if ! podman machine inspect "${machine_name}" >"${machine_inspect_path}" 2>>"${machine_log}"; then
      exit_code=$?
      append_failure_and_exit "machine.inspect" "${exit_code}" "${machine_log}" "failed to inspect the podman machine after start"
    fi
  fi

  machine_observation_json="$(${JQ_BIN} -ec '.[0] // null' "${machine_inspect_path}" 2>/dev/null || printf 'null\n')"
}

cp "${TUSK_HERMES_PROBE_CONTAINER_SH}" "${container_script_host_path}"
chmod 0555 "${container_script_host_path}"

ensure_podman_machine

network_args=()
container_exit_code=0
if [ "${network_mode}" = "none" ]; then
  network_args+=(--network none)
fi

if podman run \
  --rm \
  --replace \
  --pull=missing \
  --name "${container_name}" \
  --workdir /runtime/home \
  -v "${container_script_host_path}:${container_script_guest_path}:ro" \
  -v "${runtime_home}:/runtime/home:rw" \
  -v "${artifacts_dir}:/artifacts:rw" \
  --env HOME=/runtime/home \
  --env XDG_CACHE_HOME=/runtime/home/.cache \
  --env HERMES_INSTALL_DIR="${install_dir}" \
  --env TUSK_HERMES_INSTALLER_URL="${installer_url}" \
  --env TUSK_HERMES_BRANCH="${branch}" \
  --env TUSK_HERMES_PROBE_COMMAND="${probe_command}" \
  "${podman_env_args[@]}" \
  "${network_args[@]}" \
  "${image}" \
  bash "${container_script_guest_path}" >"${container_log}" 2>&1; then
  :
else
  container_exit_code=$?
  append_failure_and_exit "container.run" "${container_exit_code}" "${container_log}" "the Hermes probe container exited non-zero"
fi

append_probe_receipt "completed" "null"
