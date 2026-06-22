#!/usr/bin/env bash
# Interactive / single-node driver: 256^3 decaying MHD turbulence + GPU dust.
#
# Run on a Marlowe (or Stellar) GPU node after salloc/srun, or submit via:
#   sbatch --partition=preempt --gres=gpu:1 --mem=80G --time=02:00:00 \
#     --wrap="export HARNESS_DIR=... MINIRAM=...; bash scripts/run_mhd_turb_dust_interactive.sh"
#
# Env overrides:
#   MHD_TURB_DUST_PPC=1|12     dust grains per cell (default 1)
#   MHD_TURB_DUST_NSTEPMAX=N   timestep cap (default 10 for debug)
#   MHD_TURB_VRMS=N            initial RMS velocity for turb.py ICs (default 2.0)
#   BUILD_BINARIES=0|1         rebuild binary (default 1)
#   CLEAN=0|1                  make clean before build (default 1)
#   GPU_NPRE=8                 precision (default 8 on Marlowe)
#   GPU_ALWAYS_KIND8_POS=1     required for dust position kind=8 (default 1)

set -euo pipefail

HARNESS_DIR="${HARNESS_DIR:-${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}}"
export CLUSTER="${CLUSTER:-marlowe}"
# shellcheck source=/dev/null
source "${HARNESS_DIR}/hackathon_bootstrap.sh"

MHD_TURB_DUST_PPC="${MHD_TURB_DUST_PPC:-1}"
MHD_TURB_DUST_NSTEPMAX="${MHD_TURB_DUST_NSTEPMAX:-10}"
BUILD_BINARIES="${BUILD_BINARIES:-1}"
CLEAN="${CLEAN:-1}"
export CLEAN

export MINIRAM_EXPECTED_BRANCH="${MINIRAM_EXPECTED_BRANCH:-gpu_dust}"
export GPU_HYDRO=1
export GPU_MHD=1
export GPU_TURB=0
export GPU_GRAV=0
export GPU_UNITS=
export GPU_NPSCAL="${GPU_NPSCAL:-0}"
export GPU_NPRE="${GPU_NPRE:-8}"
export GPU_FASTMATH="${GPU_FASTMATH:-0}"
export GPU_ALWAYS_KIND8_POS="${GPU_ALWAYS_KIND8_POS:-1}"
export GPU_DEBUG="${GPU_DEBUG:-0}"
export BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd.dust}"
export DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-1}"

# Marlowe H100 defaults (override on Stellar: GPU_CUDA_ARCH=sm_80, drop GPU_TARGETS).
export GPU_CUDA_ARCH="${GPU_CUDA_ARCH:-sm_90}"
export GPU_TARGETS="${GPU_TARGETS:-cc90,cuda12.5}"
export NVHPC_MODULE="${NVHPC_MODULE:-nvhpc/24.7}"

echo "== mhd-turb-dust interactive (decaying)"
echo "   harness=${HARNESS_DIR} miniram=${MINIRAM} branch_expected=${MINIRAM_EXPECTED_BRANCH}"
echo "   ppc=${MHD_TURB_DUST_PPC} nstepmax=${MHD_TURB_DUST_NSTEPMAX} vrms=${MHD_TURB_VRMS:-2.0} ALWAYS_KIND8_POS=${GPU_ALWAYS_KIND8_POS}"

hackathon_load_modules || exit 2
unset NVCOMPILER_TERM
nvidia-smi || true

export MHD_TURB_LEVEL=8
export MHD_TURB_DUST=1
hackathon_ensure_mhd_turb_decay_ics 8

stamp="$(date +%Y%m%d_%H%M%S)"
workdir="${RUN_DIR}/mhd_turb_dust_l8_ppc${MHD_TURB_DUST_PPC}_${stamp}"
mkdir -p "${workdir}"
cd "${workdir}"
echo "   workdir=${workdir}"

template_nml="$(hackathon_nml mhd_turb_dust_l8.nml)"
hackathon_stage_dmo_run_nml "${template_nml}" "${workdir}/input.nml"
hackathon_apply_ndust_ppc "${workdir}/input.nml" "${MHD_TURB_DUST_PPC}"
hackathon_apply_nml_kv nstepmax "${MHD_TURB_DUST_NSTEPMAX}" "${workdir}/input.nml"

echo "== staged namelist (dust + run caps)"
grep -E 'levelmin|levelmax|nstepmax|ndust_|grain_|turb=|pic=|dust=' "${workdir}/input.nml" || true

if [[ "${BUILD_BINARIES}" == "1" ]]; then
  hackathon_build_binary "${workdir}/build.log"
else
  echo "== skipping build (BUILD_BINARIES=0)"
fi
if [[ ! -x "${BIN_GPU}" && ! -f "${BIN_GPU}" ]]; then
  echo "ERROR: missing binary ${BIN_GPU}" >&2
  exit 2
fi

if [[ "${DMO_GPU_LAUNCH_BLOCKING}" == "1" ]]; then
  export CUDA_LAUNCH_BLOCKING=1
  echo "== CUDA_LAUNCH_BLOCKING=1"
fi

run_log="${workdir}/run.log"
echo "== launching ${BIN_GPU}"
"${BIN_GPU}" input.nml 2>&1 | tee "${run_log}"

echo "== tail run.log"
tail -30 "${run_log}" || true
if grep -q 'Run completed' "${run_log}"; then
  echo "== PASS: Run completed (workdir=${workdir})"
  grep -E 'time=|emag|ndust|Found ndust' "${run_log}" | head -20 || true
  exit 0
fi
echo "== FAIL: no 'Run completed' in ${run_log}" >&2
exit 1
