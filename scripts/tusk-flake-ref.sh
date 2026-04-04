#!/usr/bin/env bash
set -euo pipefail

program_name="${0##*/}"
default_bookmark="tusk-flake"

usage() {
  cat <<'EOF'
Usage:
  tusk-flake-ref [--repo PATH] [--bookmark NAME] [--remote NAME] [--remote-url URL] [--json]

Print the canonical local and publishable flake reference forms for this repo.

Options:
  --repo PATH         Resolve refs for PATH instead of the current repo.
  --bookmark NAME     Bookmark/branch name to publish. Default: tusk-flake
  --remote NAME       Git remote name to use. Defaults to origin, then the first remote.
  --remote-url URL    Override the remote URL directly.
  --json              Print a machine-readable JSON object.
  -h, --help          Show this help text.
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

default_remote_name() {
  local repo_root="$1"

  if git -C "${repo_root}" remote get-url origin >/dev/null 2>&1; then
    printf 'origin\n'
    return
  fi

  git -C "${repo_root}" remote | awk 'NF { print; exit }'
}

bookmark_jj_commit() {
  local repo_root="$1"
  local bookmark="$2"

  jj --repository "${repo_root}" log -r "${bookmark}" --no-graph -T 'commit_id ++ "\n"' 2>/dev/null \
    | awk 'NF { print; exit }' || true
}

bookmark_git_commit() {
  local repo_root="$1"
  local bookmark="$2"

  git -C "${repo_root}" rev-parse -q --verify "refs/heads/${bookmark}" 2>/dev/null || true
}

normalize_remote_url() {
  local raw_url="$1"
  local trimmed="${raw_url%.git}"
  local user_host=""
  local path=""

  case "${trimmed}" in
    git+*)
      printf '%s\n' "${trimmed}"
      ;;
    https://* | http://* | ssh://* | file://*)
      printf 'git+%s\n' "${trimmed}"
      ;;
    *@*:*)
      user_host="${trimmed%%:*}"
      path="${trimmed#*:}"
      printf 'git+ssh://%s/%s\n' "${user_host}" "${path}"
      ;;
    *)
      return 1
      ;;
  esac
}

print_text() {
  local repo_root="$1"
  local bookmark="$2"
  local jj_commit="$3"
  local git_commit="$4"
  local local_path_ref="$5"
  local local_git_ref="$6"
  local remote_name="$7"
  local remote_url="$8"
  local publish_ref="$9"
  local note="${10}"

  cat <<EOF
repo_root=${repo_root}
bookmark=${bookmark}
bookmark_jj_commit=${jj_commit}
bookmark_git_commit=${git_commit}
local_path_ref=${local_path_ref}
local_git_ref=${local_git_ref}
publish_remote_name=${remote_name}
publish_remote_url=${remote_url}
publish_ref=${publish_ref}
note=${note}
EOF
}

print_json() {
  local repo_root="$1"
  local bookmark="$2"
  local jj_commit="$3"
  local git_commit="$4"
  local local_path_ref="$5"
  local local_git_ref="$6"
  local remote_name="$7"
  local remote_url="$8"
  local publish_ref="$9"
  local note="${10}"

  jq -cn \
    --arg repo_root "${repo_root}" \
    --arg bookmark "${bookmark}" \
    --arg jj_commit "${jj_commit}" \
    --arg git_commit "${git_commit}" \
    --arg local_path_ref "${local_path_ref}" \
    --arg local_git_ref "${local_git_ref}" \
    --arg remote_name "${remote_name}" \
    --arg remote_url "${remote_url}" \
    --arg publish_ref "${publish_ref}" \
    --arg note "${note}" '
      {
        repo_root: $repo_root,
        bookmark: {
          name: $bookmark,
          jj_commit: (if $jj_commit == "" then null else $jj_commit end),
          git_commit: (if $git_commit == "" then null else $git_commit end),
          exported_to_git: ($git_commit != "")
        },
        refs: {
          local_path: $local_path_ref,
          local_git: (if $local_git_ref == "" then null else $local_git_ref end),
          publish: (if $publish_ref == "" then null else $publish_ref end)
        },
        remote: (
          if $remote_url == "" then
            null
          else
            {
              name: (if $remote_name == "" then null else $remote_name end),
              url: $remote_url
            }
          end
        ),
        note: $note
      }
    '
}

main() {
  local repo_arg=""
  local bookmark="${default_bookmark}"
  local remote_name=""
  local remote_url=""
  local output_json="false"
  local repo_root=""
  local jj_commit=""
  local git_commit=""
  local local_path_ref=""
  local local_git_ref=""
  local normalized_remote_url=""
  local publish_ref=""
  local note=""

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo)
        [ "$#" -ge 2 ] || fail "--repo requires a path"
        repo_arg="$2"
        shift 2
        ;;
      --bookmark)
        [ "$#" -ge 2 ] || fail "--bookmark requires a name"
        bookmark="$2"
        shift 2
        ;;
      --remote)
        [ "$#" -ge 2 ] || fail "--remote requires a name"
        remote_name="$2"
        shift 2
        ;;
      --remote-url)
        [ "$#" -ge 2 ] || fail "--remote-url requires a URL"
        remote_url="$2"
        shift 2
        ;;
      --json)
        output_json="true"
        shift
        ;;
      -h | --help | help)
        usage
        exit 0
        ;;
      *)
        fail "unknown argument: $1"
        ;;
    esac
  done

  repo_root="$(resolve_repo_root "${repo_arg}")"
  jj_commit="$(bookmark_jj_commit "${repo_root}" "${bookmark}")"
  git_commit="$(bookmark_git_commit "${repo_root}" "${bookmark}")"
  local_path_ref="path:${repo_root}"

  if [ -n "${git_commit}" ]; then
    local_git_ref="git+file://${repo_root}?ref=${bookmark}"
  fi

  if [ -z "${remote_url}" ]; then
    if [ -z "${remote_name}" ]; then
      remote_name="$(default_remote_name "${repo_root}")"
    fi
    if [ -n "${remote_name}" ]; then
      remote_url="$(git -C "${repo_root}" remote get-url "${remote_name}" 2>/dev/null || true)"
    fi
  fi

  if [ -n "${remote_url}" ]; then
    if normalized_remote_url="$(normalize_remote_url "${remote_url}")"; then
      publish_ref="${normalized_remote_url}?ref=${bookmark}"
    else
      note="remote URL is not in a supported flake format: ${remote_url}"
    fi
  fi

  if [ -z "${note}" ]; then
    if [ -z "${jj_commit}" ]; then
      note="bookmark ${bookmark} does not exist in jj yet"
    elif [ -z "${git_commit}" ]; then
      note="bookmark ${bookmark} exists in jj but is not exported to Git; run jj git export after setting it"
    elif [ -z "${remote_url}" ]; then
      note="no git remote configured; local refs are ready, publish_ref will appear once a remote exists"
    else
      note="push refs/heads/${bookmark} to ${remote_name:-the configured remote} before consuming publish_ref elsewhere"
    fi
  fi

  if [ "${output_json}" = "true" ]; then
    print_json \
      "${repo_root}" "${bookmark}" "${jj_commit}" "${git_commit}" \
      "${local_path_ref}" "${local_git_ref}" "${remote_name}" "${remote_url}" \
      "${publish_ref}" "${note}"
    return
  fi

  print_text \
    "${repo_root}" "${bookmark}" "${jj_commit}" "${git_commit}" \
    "${local_path_ref}" "${local_git_ref}" "${remote_name}" "${remote_url}" \
    "${publish_ref}" "${note}"
}

main "$@"
