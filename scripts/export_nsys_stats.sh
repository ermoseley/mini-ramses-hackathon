#!/usr/bin/env bash
# Export text summaries from an .nsys-rep (run on cluster or laptop with nsys in PATH).
#
# Usage:
#   ./export_nsys_stats.sh profiles_*/dm_pic_poisson_l7/*.nsys-rep
#   ./export_nsys_stats.sh trace.nsys-rep ./profile_exports

set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 TRACE.nsys-rep [OUT_DIR]" >&2
  exit 1
fi

TRACE="$1"
OUT_DIR="${2:-$(dirname "${TRACE}")/profile_exports}"

if [[ ! -f "${TRACE}" ]]; then
  echo "ERROR: trace not found: ${TRACE}" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hackathon_common.sh
source "${SCRIPT_DIR}/hackathon_common.sh"

hackathon_export_nsys_stats "${TRACE}" "${OUT_DIR}"
echo "Wrote stats under: ${OUT_DIR}"
