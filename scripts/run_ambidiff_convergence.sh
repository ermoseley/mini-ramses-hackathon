#!/usr/bin/env bash
# Run ambidiff convergence sweep (levels 6-8) and validate against analytic decay.
set -euo pipefail

HARNESS="${HARNESS_DIR:-${SLURM_SUBMIT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}}"
MINIRAM="${MINIRAM:-${HOME}/mini-ramses-dev}"
BIN="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd.ambidiff}"
TEMPLATE_NML="${AMBI_NML:-${HARNESS}/namelists/ambidiff.nml}"
WORKDIR="${1:-${RUN_DIR:-${PWD}/ambidiff_sweep}}"
LEVELS="${AMBI_LEVELS:-6 7}"
TEND="${AMBI_TEND:-0.05}"
A_0="${AMBI_A_0:-0.01}"
B_Z="${AMBI_BZ:-1.0}"
ETA_AD="${AMBI_ETA_AD:-0.01}"
BOXLEN="${AMBI_BOXLEN:-1.0}"

mkdir -p "${WORKDIR}"
echo "== ambidiff convergence: BIN=${BIN} WORKDIR=${WORKDIR} LEVELS=${LEVELS}"

if [[ ! -x "${BIN}" ]]; then
  echo "ERROR: binary not found: ${BIN}" >&2
  exit 2
fi

for lev in ${LEVELS}; do
  run="${WORKDIR}/L${lev}"
  mkdir -p "${run}"
  ngrid=$((1 << (3 * lev - 2)))
  sed -E \
    "s/^[[:space:]]*levelmin=.*/ levelmin=${lev}/; \
     s/^[[:space:]]*levelmax=.*/ levelmax=${lev}/; \
     s/^[[:space:]]*ngridmax=.*/ ngridmax=${ngrid}/; \
     s/^[[:space:]]*tend=.*/ tend=${TEND}/" \
    "${TEMPLATE_NML}" > "${run}/input.nml"
  echo "== L${lev}: $(grep -E 'levelmin|ngridmax|tend' "${run}/input.nml" | tr '\n' ' ')"
  (cd "${run}" && "${BIN}" input.nml 2>&1 | tee run.log) || echo "WARNING: L${lev} failed"
done

export PYTHONPATH="${MINIRAM}/utils/py:${PYTHONPATH:-}"
python3 "${HARNESS}/scripts/validate_ambidiff.py" \
  --workdir "${WORKDIR}" \
  --levels ${LEVELS} \
  --a0 "${A_0}" --bz "${B_Z}" --eta-ad "${ETA_AD}" --boxlen "${BOXLEN}" \
  --out "${WORKDIR}/ambidiff_report.txt"

cat "${WORKDIR}/ambidiff_report.txt"
