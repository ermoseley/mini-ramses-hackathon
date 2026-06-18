#!/usr/bin/env bash
# Source cluster profile + hackathon_common.sh from repo root.
# Usage: source bin/hackathon-env.sh
#   export CLUSTER=stellar   # or marlowe, sherlock (or set in ~/.bashrc on each cluster)

set -euo pipefail

_hackathon_env_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

hackathon_detect_cluster() {
  if [[ -n "${CLUSTER:-}" ]]; then
    printf '%s' "${CLUSTER}"
    return 0
  fi
  local host="${HOSTNAME:-$(hostname -s 2>/dev/null || hostname)}"
  host="${host,,}"
  case "${host}" in
    *stellar*|*della*) printf 'stellar' ;;
    *marlowe*) printf 'marlowe' ;;
    *sherlock*) printf 'sherlock' ;;
    *) return 1 ;;
  esac
}

_cluster="$(hackathon_detect_cluster 2>/dev/null || true)"
if [[ -z "${_cluster}" ]]; then
  echo "ERROR: set CLUSTER=stellar|marlowe|sherlock before sourcing hackathon-env.sh" >&2
  return 2 2>/dev/null || exit 2
fi

_profile="${_hackathon_env_root}/clusters/${_cluster}.profile"
if [[ ! -f "${_profile}" ]]; then
  echo "ERROR: missing cluster profile: ${_profile}" >&2
  return 2 2>/dev/null || exit 2
fi

# shellcheck source=/dev/null
source "${_profile}"
export CLUSTER="${_cluster}"
export HACKATHON_REPO_ROOT="${_hackathon_env_root}"

# Default harness to repo root when running from a git checkout; on cluster use profile scratch path.
if [[ -z "${HARNESS_DIR:-}" ]]; then
  if [[ -d "${HARNESS_DIR_DEFAULT:-}" ]]; then
    export HARNESS_DIR="${HARNESS_DIR_DEFAULT}"
  else
    export HARNESS_DIR="${_hackathon_env_root}"
  fi
fi
export HARNESS_DIR="${HARNESS_DIR}"
export RUN_DIR="${RUN_DIR:-${RUN_DIR_DEFAULT:-${HARNESS_DIR}}}"
export MINIRAM="${MINIRAM:-${MINIRAM_DEFAULT:-${HOME}/mini-ramses-dev}}"

# shellcheck source=/dev/null
source "${_hackathon_env_root}/hackathon_common.sh"
hackathon_setup_paths
