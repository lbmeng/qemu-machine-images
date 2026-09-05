#!/usr/bin/env bash

set -euo pipefail

if (( $# != 3 )); then
    echo "usage: $0 REPO_ROOT BASE_REF HEAD_REF" >&2
    exit 2
fi

readonly REPO_ROOT="$1"
readonly BASE_REF="$2"
readonly HEAD_REF="$3"
TEMP_ROOT="$(mktemp -d)"
readonly TEMP_ROOT
trap 'rm -rf -- "${TEMP_ROOT}"' EXIT

# Write Git output before reading it so revision errors cannot look like no changes
git -C "${REPO_ROOT}" ls-tree --name-only -r -z "${HEAD_REF}" -- machine/ \
    > "${TEMP_ROOT}/inventory"
git -C "${REPO_ROOT}" diff --name-only --no-renames -z \
    "${BASE_REF}" "${HEAD_REF}" -- > "${TEMP_ROOT}/changes"

declare -A build_files=()
declare -A machine_configs=()
declare -A known_machines=()
declare -a machines=()

while IFS= read -r -d '' path; do
    if [[ ! "${path}" =~ ^(machine/[^/]+/[^/]+)/(build\.hcl|machine\.conf)$ ]]; then
        continue
    fi
    machine_dir="${BASH_REMATCH[1]}"
    filename="${BASH_REMATCH[2]}"
    if [[ ! "${machine_dir}" =~ ^machine/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
        echo "invalid machine directory: ${machine_dir}" >&2
        exit 1
    fi

    if [[ -z "${known_machines[${machine_dir}]+present}" ]]; then
        known_machines["${machine_dir}"]=1
        machines+=("${machine_dir}")
    fi
    if [[ "${filename}" == build.hcl ]]; then
        build_files["${machine_dir}"]=1
    else
        machine_configs["${machine_dir}"]=1
    fi
done < "${TEMP_ROOT}/inventory"

for machine_dir in "${machines[@]}"; do
    if [[ -z "${build_files[${machine_dir}]+present}" ||
          -z "${machine_configs[${machine_dir}]+present}" ]]; then
        echo "machine requires build.hcl and machine.conf: ${machine_dir}" >&2
        exit 1
    fi
done

build_all=false
declare -A affected_machines=()
while IFS= read -r -d '' path; do
    if [[ "${path}" =~ ^(machine/[^/]+/[^/]+)/ ]]; then
        machine_dir="${BASH_REMATCH[1]}"
        # Fully removed machines have no remaining build to validate
        if [[ -n "${known_machines[${machine_dir}]+present}" ]]; then
            affected_machines["${machine_dir}"]=1
        fi
        continue
    fi

    case "${path}" in
        README.md|docs/*|LICENSE|LICENSE.*|.gitignore) ;;
        *) build_all=true ;;
    esac
done < "${TEMP_ROOT}/changes"

declare -a selected_machines=()
for machine_dir in "${machines[@]}"; do
    if [[ "${build_all}" == true ||
          -n "${affected_machines[${machine_dir}]+present}" ]]; then
        selected_machines+=("${machine_dir}")
    fi
done

jq --null-input --compact-output '$ARGS.positional' \
    --args "${selected_machines[@]}"
