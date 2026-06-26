#!/usr/bin/env bash
# Run alfven_ad convergence sweep (levels 6-8) and validate against analytic damping.
set -euo pipefail

HARNESS="${HARNESS_DIR:-${SLURM_SUBMIT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}}"
MINIRAM="${MINIRAM:-${HOME}/mini-ramses-dev}"
MINIRAM_PY="${MINIRAM_PY:-${HOME}/mini-ramses-dev}"
BIN="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd.alfvenad}"
TEMPLATE_NML="${AMBI_NML:-${HARNESS}/namelists/alfven_ad.nml}"
WORKDIR="${1:-${RUN_DIR:-${PWD}/alfven_ad_sweep}}"
LEVELS="${AMBI_LEVELS:-6 7}"
_nml_val() { grep -E "^[[:space:]]*${1}=" "${2}" | head -1 | sed -E "s/.*${1}=//; s/[[:space:]].*//"; }
TEND="${AMBI_TEND:-$(_nml_val tend "${TEMPLATE_NML}")}"
A_0="${AMBI_A_0:-$(_nml_val A_ave "${TEMPLATE_NML}")}"
B_Z="${AMBI_BZ:-$(_nml_val C_ave "${TEMPLATE_NML}")}"
ETA_AD="${AMBI_ETA_AD:-$(_nml_val eta_ad "${TEMPLATE_NML}")}"
BOXLEN="${AMBI_BOXLEN:-$(_nml_val boxlen "${TEMPLATE_NML}")}"

mkdir -p "${WORKDIR}"
echo "== alfven_ad convergence: BIN=${BIN} WORKDIR=${WORKDIR} LEVELS=${LEVELS}"

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

export PYTHONPATH="${MINIRAM_PY}/utils/py:${PYTHONPATH:-}"
python3 "${HARNESS}/scripts/validate_alfven_ad.py" \
  --workdir "${WORKDIR}" \
  --levels ${LEVELS} \
  --a0 "${A_0}" --bz "${B_Z}" --eta-ad "${ETA_AD}" --boxlen "${BOXLEN}" \
  --miniram "${MINIRAM_PY}" \
  --out "${WORKDIR}/alfven_ad_report.txt" \
  --plot --plot-out "${WORKDIR}/alfven_ad_damping.png"

cat "${WORKDIR}/alfven_ad_report.txt"
