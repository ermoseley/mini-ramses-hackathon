#!/usr/bin/env bash
# Run a command on Marlowe via the shared ControlMaster socket (no re-auth).
set -euo pipefail

MARLOWE_HOST="${MARLOWE_SSH_HOST:-marlowe}"

if ! ssh -O check "${MARLOWE_HOST}" 2>/dev/null; then
  echo "ERROR: Marlowe SSH not authenticated." >&2
  echo "       Run: ${HARNESS_DIR:-.}/bin/marlowe_login.sh" >&2
  echo "       (Add Host marlowe -> login.marlowe.stanford.edu, User emoseley, ControlPath like Stellar.)" >&2
  exit 2
fi

exec ssh "${MARLOWE_HOST}" "$@"
