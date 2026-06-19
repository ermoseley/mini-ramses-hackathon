#!/usr/bin/env bash
# One-time Marlowe auth for Cursor agent. Keeps SSH socket ~8h.
set -euo pipefail

mkdir -p "${HOME}/.ssh/sockets"

MARLOWE_HOST="${MARLOWE_SSH_HOST:-marlowe}"

if ssh -O check "${MARLOWE_HOST}" 2>/dev/null; then
  echo "== Marlowe multiplex already active:"
  ssh -O check "${MARLOWE_HOST}"
  exit 0
fi

echo "== Connecting to Marlowe (${MARLOWE_HOST})"
echo "   Complete password / MFA when prompted."
echo ""

ssh "${MARLOWE_HOST}" 'echo "== login OK on $(hostname)"; uptime'

echo ""
echo "== Multiplex ready — use: bin/marlowe_remote.sh"
ssh -O check "${MARLOWE_HOST}"
