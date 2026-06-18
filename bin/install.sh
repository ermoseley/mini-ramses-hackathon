#!/usr/bin/env bash
# Install or update mini-ramses-hackathon on cluster scratch.
#
# Usage:
#   CLUSTER=stellar bin/install.sh
#   CLUSTER=marlowe bin/install.sh
#   CLUSTER=stellar DEST=/scratch/gpfs/me/hackathon bin/install.sh
#
# Requires: git, write access to DEST. Does not copy ics_* or output_* (runtime scratch only).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITHUB_REPO="${HACKATHON_GITHUB_REPO:-https://github.com/ermoseley/mini-ramses-hackathon.git}"

_cluster="${CLUSTER:-}"
if [[ -z "${_cluster}" ]]; then
  echo "ERROR: set CLUSTER=stellar|marlowe|sherlock" >&2
  exit 2
fi

_profile="${REPO_ROOT}/clusters/${_cluster}.profile"
if [[ ! -f "${_profile}" ]]; then
  echo "ERROR: missing ${_profile}" >&2
  exit 2
fi
# shellcheck source=/dev/null
source "${_profile}"

DEST="${DEST:-${HARNESS_DIR_DEFAULT:-}}"
if [[ -z "${DEST}" ]]; then
  echo "ERROR: DEST or HARNESS_DIR_DEFAULT must be set in ${_profile}" >&2
  exit 2
fi

echo "== install hackathon cluster=${_cluster} dest=${DEST}"

if [[ -d "${DEST}/.git" ]]; then
  echo "== git pull in ${DEST}"
  git -C "${DEST}" pull --ff-only
elif [[ -d "${DEST}" ]] && [[ -n "$(ls -A "${DEST}" 2>/dev/null)" ]]; then
  echo "ERROR: ${DEST} exists but is not a git repo; move aside or set DEST=" >&2
  exit 2
else
  mkdir -p "$(dirname "${DEST}")"
  git clone "${GITHUB_REPO}" "${DEST}"
fi

chmod +x "${DEST}/submit_profiles.sh" "${DEST}/bin/"*.sh 2>/dev/null || true
echo "== installed at ${DEST}"
echo "   export CLUSTER=${_cluster}"
echo "   cd ${DEST} && bin/doctor.sh"
