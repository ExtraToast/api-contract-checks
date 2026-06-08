#!/usr/bin/env bash
set -euo pipefail

program=${0##*/}

usage() {
  cat <<'USAGE'
Usage:
  api-contract-checks.sh --profile <name> --spec-path <path> \
    --export-command <command> [--spec-normalize-command <command>] \
    [--types-path <path> ... | --types-paths <newline-or-comma-list>] \
    [--types-generate-command <command>] \
    [--types-normalize-command <command>] \
    --guidance <command-or-note>

  api-contract-checks.sh --profile-file <file> [--profile-file <file> ...]
  api-contract-checks.sh --profiles-dir <dir> [--only <profile> ...]

Profile files are Bash fragments with these fields:
  PROFILE_NAME
  SPEC_PATH
  SPEC_EXPORT_COMMAND
  SPEC_NORMALIZE_COMMAND       optional
  TYPES_PATHS=(path ...)
  TYPES_PATHS_TEXT             optional newline-or-comma list
  TYPES_GENERATE_COMMAND       optional when TYPES_PATHS is empty
  TYPES_NORMALIZE_COMMAND      optional
  GUIDANCE
USAGE
}

trim() {
  local value=$1
  value=${value#"${value%%[![:space:]]*}"}
  value=${value%"${value##*[![:space:]]}"}
  printf '%s' "$value"
}

append_csv() {
  local raw=$1
  local target_name=$2
  # shellcheck disable=SC2178
  local -n target="$target_name"
  local part
  local -a parts=()

  IFS=',' read -r -a parts <<<"$raw"
  for part in "${parts[@]}"; do
    part=$(trim "$part")
    if [[ -n $part ]]; then
      target+=("$part")
    fi
  done
}

append_paths_text() {
  local raw=${1//$'\r'/}
  local target_name=$2
  # shellcheck disable=SC2178
  local -n target="$target_name"
  local line

  if [[ $raw == *$'\n'* ]]; then
    while IFS= read -r line || [[ -n $line ]]; do
      line=$(trim "$line")
      if [[ -n $line ]]; then
        target+=("$line")
      fi
    done <<<"$raw"
  else
    append_csv "$raw" "$target_name"
  fi
}

github_escape() {
  local value=$1
  value=${value//%/%25}
  value=${value//$'\r'/%0D}
  value=${value//$'\n'/%0A}
  printf '%s' "$value"
}

emit_github_error() {
  local path=$1
  local message=$2

  if [[ ${GITHUB_ACTIONS:-} != "true" ]]; then
    return 0
  fi

  if [[ -n $path ]]; then
    printf '::error file=%s::%s\n' "$(github_escape "$path")" "$(github_escape "$message")"
  else
    printf '::error::%s\n' "$(github_escape "$message")"
  fi
}

print_failure() {
  local profile=$1
  local stage=$2
  local path=$3
  local message=$4
  local guidance=$5

  printf '\ncontract check failure\n'
  printf 'profile: %s\n' "$profile"
  printf 'stage: %s\n' "$stage"
  if [[ -n $path ]]; then
    printf 'path: %s\n' "$path"
  fi
  printf 'message: %s\n' "$message"
  if [[ -n $guidance ]]; then
    printf 'guidance: %s\n' "$guidance"
  fi

  emit_github_error "$path" "$profile $stage: $message"
}

snapshot_path() {
  local path=$1
  local snapshot_root=$2
  local profile=$3
  local stage=$4
  local guidance=$5
  local snapshot_path=$snapshot_root/$path

  if [[ ! -e $path ]]; then
    print_failure "$profile" "$stage" "$path" "committed path is missing" "$guidance"
    return 1
  fi

  mkdir -p -- "$(dirname -- "$snapshot_path")"
  if [[ -d $path ]]; then
    mkdir -p -- "$snapshot_path"
    cp -a -- "$path"/. "$snapshot_path"/
  else
    cp -- "$path" "$snapshot_path"
  fi
}

snapshot_paths() {
  local snapshot_root=$1
  local profile=$2
  local stage=$3
  local guidance=$4
  shift 4

  local status=0
  local path
  for path in "$@"; do
    if ! snapshot_path "$path" "$snapshot_root" "$profile" "$stage" "$guidance"; then
      status=1
    fi
  done
  return "$status"
}

run_declared_command() {
  local profile=$1
  local stage=$2
  local command=$3
  local spec_path=$4
  local types_paths_text=$5

  printf '\ncontract check command\n'
  printf 'profile: %s\n' "$profile"
  printf 'stage: %s\n' "$stage"
  printf 'command: %s\n' "$command"

  CONTRACT_PROFILE=$profile \
    CONTRACT_STAGE=$stage \
    CONTRACT_SPEC_PATH=$spec_path \
    CONTRACT_TYPES_PATHS=$types_paths_text \
    bash -euo pipefail -c "$command"
}

compare_path() {
  local path=$1
  local snapshot_root=$2
  local profile=$3
  local stage=$4
  local guidance=$5
  local snapshot_path=$snapshot_root/$path

  if [[ ! -e $path ]]; then
    print_failure "$profile" "$stage" "$path" "generated path is missing after command" "$guidance"
    return 1
  fi

  if diff -ruN -- "$snapshot_path" "$path"; then
    return 0
  fi

  print_failure "$profile" "$stage" "$path" "contract drift detected" "$guidance"
  return 1
}

compare_paths() {
  local snapshot_root=$1
  local profile=$2
  local stage=$3
  local guidance=$4
  shift 4

  local status=0
  local path
  for path in "$@"; do
    if ! compare_path "$path" "$snapshot_root" "$profile" "$stage" "$guidance"; then
      status=1
    fi
  done
  return "$status"
}

types_paths_as_text() {
  local path
  for path in "$@"; do
    printf '%s\n' "$path"
  done
}

should_run_profile() {
  local profile=$1
  shift
  local requested

  if [[ $# -eq 0 ]]; then
    return 0
  fi

  for requested in "$@"; do
    if [[ $profile == "$requested" ]]; then
      return 0
    fi
  done

  return 1
}

run_profile() {
  local profile=$1
  local spec_path=$2
  local spec_export_command=$3
  local spec_normalize_command=$4
  local types_generate_command=$5
  local types_normalize_command=$6
  local guidance=$7
  shift 7
  local -a types_paths=("$@")

  local status=0
  local spec_snapshot_ok=1
  local types_snapshot_ok=1
  local tmp_dir
  local spec_snapshot
  local types_snapshot
  local types_paths_text

  if [[ -z $profile ]]; then
    print_failure "<unset>" "configuration" "" "PROFILE_NAME is required" ""
    return 1
  fi
  if [[ -z $spec_path ]]; then
    print_failure "$profile" "configuration" "" "SPEC_PATH is required" "$guidance"
    return 1
  fi
  if [[ -z $spec_export_command ]]; then
    print_failure "$profile" "configuration" "$spec_path" "SPEC_EXPORT_COMMAND is required" "$guidance"
    return 1
  fi
  if [[ -z $guidance ]]; then
    print_failure "$profile" "configuration" "$spec_path" "GUIDANCE is required" ""
    return 1
  fi
  if [[ ${#types_paths[@]} -gt 0 && -z $types_generate_command ]]; then
    print_failure "$profile" "configuration" "" "TYPES_GENERATE_COMMAND is required when TYPES_PATHS is set" "$guidance"
    return 1
  fi
  if [[ ${#types_paths[@]} -eq 0 && -n $types_generate_command ]]; then
    print_failure "$profile" "configuration" "" "TYPES_PATHS is required when TYPES_GENERATE_COMMAND is set" "$guidance"
    return 1
  fi

  tmp_dir=$(mktemp -d)
  spec_snapshot=$tmp_dir/spec
  types_snapshot=$tmp_dir/types
  mkdir -p -- "$spec_snapshot" "$types_snapshot"

  printf '\ncontract check profile\n'
  printf 'profile: %s\n' "$profile"

  if ! snapshot_paths "$spec_snapshot" "$profile" "openapi-spec" "$guidance" "$spec_path"; then
    spec_snapshot_ok=0
    status=1
  fi

  types_paths_text=$(types_paths_as_text "${types_paths[@]}")

  if ! run_declared_command "$profile" "openapi-spec" "$spec_export_command" "$spec_path" "$types_paths_text"; then
    print_failure "$profile" "openapi-spec" "$spec_path" "export command failed" "$guidance"
    status=1
  elif [[ -n $spec_normalize_command ]]; then
    if ! run_declared_command "$profile" "openapi-spec-normalize" "$spec_normalize_command" "$spec_path" "$types_paths_text"; then
      print_failure "$profile" "openapi-spec" "$spec_path" "normalization command failed" "$guidance"
      status=1
    fi
  fi

  if [[ $spec_snapshot_ok -eq 1 ]]; then
    if ! compare_paths "$spec_snapshot" "$profile" "openapi-spec" "$guidance" "$spec_path"; then
      status=1
    fi
  fi

  if [[ ${#types_paths[@]} -gt 0 ]]; then
    if ! snapshot_paths "$types_snapshot" "$profile" "types" "$guidance" "${types_paths[@]}"; then
      types_snapshot_ok=0
      status=1
    fi

    if ! run_declared_command "$profile" "types" "$types_generate_command" "$spec_path" "$types_paths_text"; then
      print_failure "$profile" "types" "${types_paths[0]}" "type generation command failed" "$guidance"
      status=1
    elif [[ -n $types_normalize_command ]]; then
      if ! run_declared_command "$profile" "types-normalize" "$types_normalize_command" "$spec_path" "$types_paths_text"; then
        print_failure "$profile" "types" "${types_paths[0]}" "normalization command failed" "$guidance"
        status=1
      fi
    fi

    if [[ $types_snapshot_ok -eq 1 ]]; then
      if ! compare_paths "$types_snapshot" "$profile" "types" "$guidance" "${types_paths[@]}"; then
        status=1
      fi
    fi
  fi

  rm -rf -- "$tmp_dir"

  if [[ $status -eq 0 ]]; then
    printf '\ncontract check passed\n'
    printf 'profile: %s\n' "$profile"
  fi

  return "$status"
}

load_profile_file() {
  local file=$1
  shift
  local -a only_names=("$@")
  local PROFILE_NAME=""
  local SPEC_PATH=""
  local SPEC_EXPORT_COMMAND=""
  local SPEC_NORMALIZE_COMMAND=""
  local TYPES_GENERATE_COMMAND=""
  local TYPES_NORMALIZE_COMMAND=""
  local TYPES_PATHS_TEXT=""
  local GUIDANCE=""
  local -a TYPES_PATHS=()

  PROFILE_SELECTED=0

  if [[ ! -f $file ]]; then
    print_failure "<unset>" "configuration" "$file" "profile file is missing" ""
    return 2
  fi

  # shellcheck source=/dev/null
  source "$file"

  if [[ -n $TYPES_PATHS_TEXT ]]; then
    append_paths_text "$TYPES_PATHS_TEXT" TYPES_PATHS
  fi

  if ! should_run_profile "$PROFILE_NAME" "${only_names[@]}"; then
    return 0
  fi

  PROFILE_SELECTED=1

  run_profile \
    "$PROFILE_NAME" \
    "$SPEC_PATH" \
    "$SPEC_EXPORT_COMMAND" \
    "$SPEC_NORMALIZE_COMMAND" \
    "$TYPES_GENERATE_COMMAND" \
    "$TYPES_NORMALIZE_COMMAND" \
    "$GUIDANCE" \
    "${TYPES_PATHS[@]}"
}

require_value() {
  local flag=$1
  local value=${2:-}

  if [[ -z $value ]]; then
    printf '%s: %s requires a value\n' "$program" "$flag" >&2
    exit 2
  fi
}

main() {
  local direct_profile=""
  local direct_spec_path=""
  local direct_export_command=""
  local direct_spec_normalize_command=""
  local direct_types_generate_command=""
  local direct_types_normalize_command=""
  local direct_guidance=""
  local profiles_dir=""
  local has_direct=0
  local matched_count=0
  local selected_count=0
  local status=0
  local file
  local arg
  local -a direct_types_paths=()
  local -a profile_files=()
  local -a only_names=()

  while [[ $# -gt 0 ]]; do
    arg=$1
    case "$arg" in
      --help|-h)
        usage
        exit 0
        ;;
      --profile-file)
        require_value "$arg" "${2:-}"
        profile_files+=("$2")
        shift 2
        ;;
      --profiles-dir)
        require_value "$arg" "${2:-}"
        profiles_dir=$2
        shift 2
        ;;
      --only)
        require_value "$arg" "${2:-}"
        append_paths_text "$2" only_names
        shift 2
        ;;
      --profile)
        require_value "$arg" "${2:-}"
        direct_profile=$2
        has_direct=1
        shift 2
        ;;
      --spec-path)
        require_value "$arg" "${2:-}"
        direct_spec_path=$2
        has_direct=1
        shift 2
        ;;
      --export-command)
        require_value "$arg" "${2:-}"
        direct_export_command=$2
        has_direct=1
        shift 2
        ;;
      --spec-normalize-command)
        require_value "$arg" "${2:-}"
        direct_spec_normalize_command=$2
        has_direct=1
        shift 2
        ;;
      --types-path)
        require_value "$arg" "${2:-}"
        direct_types_paths+=("$2")
        has_direct=1
        shift 2
        ;;
      --types-paths)
        require_value "$arg" "${2:-}"
        append_paths_text "$2" direct_types_paths
        has_direct=1
        shift 2
        ;;
      --types-generate-command)
        require_value "$arg" "${2:-}"
        direct_types_generate_command=$2
        has_direct=1
        shift 2
        ;;
      --types-normalize-command)
        require_value "$arg" "${2:-}"
        direct_types_normalize_command=$2
        has_direct=1
        shift 2
        ;;
      --guidance)
        require_value "$arg" "${2:-}"
        direct_guidance=$2
        has_direct=1
        shift 2
        ;;
      *)
        printf '%s: unknown argument: %s\n' "$program" "$arg" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  if [[ -n $profiles_dir ]]; then
    if [[ ! -d $profiles_dir ]]; then
      printf '%s: profiles directory is missing: %s\n' "$program" "$profiles_dir" >&2
      exit 2
    fi
    shopt -s nullglob
    for file in "$profiles_dir"/*.conf "$profiles_dir"/*.profile; do
      profile_files+=("$file")
    done
    shopt -u nullglob
  fi

  if [[ $has_direct -eq 1 && ${#profile_files[@]} -gt 0 ]]; then
    printf '%s: direct profile flags cannot be combined with profile files\n' "$program" >&2
    exit 2
  fi

  if [[ $has_direct -eq 0 && ${#profile_files[@]} -eq 0 ]]; then
    usage >&2
    exit 2
  fi

  if [[ $has_direct -eq 1 ]]; then
    run_profile \
      "$direct_profile" \
      "$direct_spec_path" \
      "$direct_export_command" \
      "$direct_spec_normalize_command" \
      "$direct_types_generate_command" \
      "$direct_types_normalize_command" \
      "$direct_guidance" \
      "${direct_types_paths[@]}"
    exit $?
  fi

  for file in "${profile_files[@]}"; do
    if load_profile_file "$file" "${only_names[@]}"; then
      :
    else
      status=1
    fi
    if [[ ${PROFILE_SELECTED:-0} -eq 1 ]]; then
      selected_count=$((selected_count + 1))
    fi
    matched_count=$((matched_count + 1))
  done

  if [[ $matched_count -eq 0 ]]; then
    printf '%s: no profile files found\n' "$program" >&2
    exit 2
  fi

  if [[ ${#only_names[@]} -gt 0 && $selected_count -eq 0 ]]; then
    printf '%s: no selected profiles matched: %s\n' "$program" "${only_names[*]}" >&2
    exit 2
  fi

  exit "$status"
}

main "$@"
