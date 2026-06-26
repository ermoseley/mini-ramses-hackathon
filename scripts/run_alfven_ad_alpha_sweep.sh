#!/usr/bin/env bash
# Alfven wave ambipolar damping: RKG alpha parameter sweep (single level).
set -euo pipefail

HARNESS="${HARNESS_DIR:-${SLURM_SUBMIT_DIR:-$(cd "$(dirname "$0")/.." && pwd)}}"
MINIRAM="${MINIRAM:-${HOME}/mini-ramses-dev}"
MINIRAM_PY="${MINIRAM_PY:-${HOME}/mini-ramses-dev}"
BIN="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd.alfvenad}"
TEMPLATE_NML="${AMBI_NML:-${HARNESS}/namelists/alfven_ad.nml}"
WORKDIR="${1:-${RUN_DIR:-${PWD}/alfven_ad_alpha_sweep}}"
LEVEL="${AMBI_LEVEL:-7}"
ALPHAS="${RKG_ALPHAS:-0.5 2 10}"
_nml_val() { grep -E "^[[:space:]]*${1}=" "${2}" | head -1 | sed -E "s/.*${1}=//; s/[[:space:]].*//"; }
TEND="${AMBI_TEND:-$(_nml_val tend "${TEMPLATE_NML}")}"
A_0="${AMBI_A_0:-$(_nml_val A_ave "${TEMPLATE_NML}")}"
B_Z="${AMBI_BZ:-$(_nml_val C_ave "${TEMPLATE_NML}")}"
ETA_AD="${AMBI_ETA_AD:-$(_nml_val eta_ad "${TEMPLATE_NML}")}"
BOXLEN="${AMBI_BOXLEN:-$(_nml_val boxlen "${TEMPLATE_NML}")}"

mkdir -p "${WORKDIR}"
echo "== alfven_ad alpha sweep: BIN=${BIN} WORKDIR=${WORKDIR} LEVEL=${LEVEL} ALPHAS=${ALPHAS}"

if [[ ! -x "${BIN}" ]]; then
  echo "ERROR: binary not found: ${BIN}" >&2
  exit 2
fi

ngrid=$((1 << (3 * LEVEL - 2)))
for alpha in ${ALPHAS}; do
  tag="${alpha//./p}"
  run="${WORKDIR}/alpha_${tag}/L${LEVEL}"
  mkdir -p "${run}"
  sed -E \
    "s/^[[:space:]]*levelmin=.*/ levelmin=${LEVEL}/; \
     s/^[[:space:]]*levelmax=.*/ levelmax=${LEVEL}/; \
     s/^[[:space:]]*ngridmax=.*/ ngridmax=${ngrid}/; \
     s/^[[:space:]]*tend=.*/ tend=${TEND}/; \
     s/^[[:space:]]*rkg_alpha=.*/ rkg_alpha=${alpha}/" \
    "${TEMPLATE_NML}" > "${run}/input.nml"
  if ! grep -qE '^[[:space:]]*rkg_alpha=' "${run}/input.nml"; then
    sed -i '/^[[:space:]]*cp_ad=/a rkg_alpha='"${alpha}" "${run}/input.nml"
  fi
  echo "== alpha=${alpha}: $(grep -E 'levelmin|tend|rkg_alpha' "${run}/input.nml" | tr '\n' ' ')"
  (cd "${run}" && "${BIN}" input.nml 2>&1 | tee run.log) || echo "WARNING: alpha=${alpha} failed"
done

export PYTHONPATH="${MINIRAM_PY}/utils/py:${PYTHONPATH:-}"
for alpha in ${ALPHAS}; do
  tag="${alpha//./p}"
  sweep="${WORKDIR}/alpha_${tag}"
  if [[ ! -d "${sweep}/L${LEVEL}" ]]; then
    continue
  fi
  python3 "${HARNESS}/scripts/validate_alfven_ad.py" \
    --workdir "${sweep}" \
    --levels "${LEVEL}" \
    --a0 "${A_0}" --bz "${B_Z}" --eta-ad "${ETA_AD}" --boxlen "${BOXLEN}" \
    --miniram "${MINIRAM_PY}" \
    --out "${sweep}/alfven_ad_report.txt" \
    --plot --plot-out "${sweep}/alfven_ad_damping.png" \
    --plot-level "${LEVEL}" || true
done

{
  echo "Alfven wave ambipolar damping — RKG alpha sweep (L${LEVEL})"
  echo "  eta_ad=${ETA_AD}  tend=${TEND}  alphas=${ALPHAS}"
  echo ""
  for alpha in ${ALPHAS}; do
    tag="${alpha//./p}"
    rep="${WORKDIR}/alpha_${tag}/alfven_ad_report.txt"
    echo "=== rkg_alpha=${alpha} ==="
    if [[ -f "${rep}" ]]; then
      cat "${rep}"
    else
      echo "  (no report)"
    fi
    echo ""
  done
} > "${WORKDIR}/alfven_ad_alpha_report.txt"
cat "${WORKDIR}/alfven_ad_alpha_report.txt"
