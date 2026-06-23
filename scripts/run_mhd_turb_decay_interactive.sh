#!/usr/bin/env bash
# Interactive / single-node driver: decaying MHD turbulence (no dust) on the
# nsubgrid_experiments branch (nsubgrid=2 MHD via dynamic shared memory).
#
# Run on a Marlowe GPU node inside an salloc/srun allocation, or submit via:
#   sbatch -A marlowe-m000115 -p preempt --gres=gpu:1 --mem=80G --time=02:00:00 \
#     --wrap="export HARNESS_DIR=... MINIRAM=...; bash scripts/run_mhd_turb_decay_interactive.sh"
#
# Env overrides:
#   MHD_TURB_LEVEL=6           grid is 2^level per axis (default 6 -> 64^3)
#   MHD_TURB_VRMS=2.0          initial RMS velocity for turb.py ICs
#   MHD_TURB_BZ=4              uniform Bz threaded through the box
#   MHD_TURB_DECAY_NSTEPMAX=N  cap timesteps (default: unset -> run to tend)
#   GPU_NPRE=4                 precision (default 4, per request)
#   BUILD_BINARIES=0|1         rebuild binary (default 1)
#   CLEAN=0|1                  make clean before build (default 1)

set -euo pipefail

HARNESS_DIR="${HARNESS_DIR:-${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}}"
export CLUSTER="${CLUSTER:-marlowe}"
# shellcheck source=/dev/null
source "${HARNESS_DIR}/hackathon_bootstrap.sh"

BUILD_BINARIES="${BUILD_BINARIES:-1}"
CLEAN="${CLEAN:-1}"
export CLEAN

# nsubgrid=2 MHD lives on this branch.
export MINIRAM_EXPECTED_BRANCH="${MINIRAM_EXPECTED_BRANCH:-nsubgrid_experiments}"
export GPU_HYDRO=1
export GPU_MHD=1
export GPU_TURB=0          # decaying: no stochastic driving, no FFTW
export GPU_GRAV=0
export GPU_UNITS=
export GPU_NPSCAL="${GPU_NPSCAL:-0}"     # NVAR=5; B in bold/bnew
export GPU_NPRE="${GPU_NPRE:-4}"          # single precision (per request)
export GPU_FASTMATH="${GPU_FASTMATH:-0}"  # never combine NPRE=4 + FASTMATH=1
export GPU_PAPER=0
export GPU_DEBUG="${GPU_DEBUG:-0}"
export BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd}"
export DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-1}"

# Marlowe H100 defaults.
export GPU_CUDA_ARCH="${GPU_CUDA_ARCH:-sm_90}"
export GPU_TARGETS="${GPU_TARGETS:-cc90,cuda12.5}"
export NVHPC_MODULE="${NVHPC_MODULE:-nvhpc/24.7}"

mt_level="${MHD_TURB_LEVEL:-6}"

echo "== mhd-turb-decay interactive (decaying MHD turbulence, no dust)"
echo "   harness=${HARNESS_DIR} miniram=${MINIRAM} branch_expected=${MINIRAM_EXPECTED_BRANCH}"
echo "   level=${mt_level} ($((2**mt_level))^3) NPRE=${GPU_NPRE} riemann=hlld vrms=${MHD_TURB_VRMS:-2.0} Bz=${MHD_TURB_BZ:-4}"

hackathon_load_modules || exit 2
unset NVCOMPILER_TERM
nvidia-smi || true

# Decaying turbulent-velocity + uniform-Bz grafic ICs (turb.py; turb=.false.).
export MHD_TURB_LEVEL="${mt_level}"
hackathon_ensure_mhd_turb_decay_ics "${mt_level}"

stamp="$(date +%Y%m%d_%H%M%S)"
workdir="${RUN_DIR}/mhd_turb_decay_l${mt_level}_nsub2_${stamp}"
mkdir -p "${workdir}"
cd "${workdir}"
echo "   workdir=${workdir}"

template_nml="$(hackathon_nml mhd_turb_decay.nml)"
hackathon_stage_dmo_run_nml "${template_nml}" "${workdir}/input.nml"
if [[ "${mt_level}" != "6" ]]; then
  hackathon_apply_nml_kv levelmin "${mt_level}" "${workdir}/input.nml"
  hackathon_apply_nml_kv levelmax "${mt_level}" "${workdir}/input.nml"
fi
if [[ -n "${MHD_TURB_DECAY_NSTEPMAX:-}" ]]; then
  hackathon_apply_nml_kv nstepmax "${MHD_TURB_DECAY_NSTEPMAX}" "${workdir}/input.nml"
fi
# Larger grids need bigger oct pools: level 9 (512^3) holds ~19M octs, far above
# the 64^3 namelist default. Override ngridmax/ncachemax via env when scaling up.
if [[ -n "${MHD_TURB_NGRIDMAX:-}" ]]; then
  hackathon_apply_nml_kv ngridmax "${MHD_TURB_NGRIDMAX}" "${workdir}/input.nml"
fi
if [[ -n "${MHD_TURB_NCACHEMAX:-}" ]]; then
  hackathon_apply_nml_kv ncachemax "${MHD_TURB_NCACHEMAX}" "${workdir}/input.nml"
fi

echo "== staged namelist"
grep -E 'levelmin|levelmax|nstepmax|turb=|pic=|riemann|tend|periodic' "${workdir}/input.nml" || true

if [[ "${BUILD_BINARIES}" == "1" ]]; then
  hackathon_build_binary "${workdir}/build.log"
else
  echo "== skipping build (BUILD_BINARIES=0)"
fi
if [[ ! -x "${BIN_GPU}" && ! -f "${BIN_GPU}" ]]; then
  echo "ERROR: missing binary ${BIN_GPU} (see ${workdir}/build.log)" >&2
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
echo "== emag / divB sanity (decaying MHD turb gate) =="
grep -iE 'emag|div.?b|reading ic_' "${run_log}" | head -20 || true
if grep -q 'Run completed' "${run_log}"; then
  echo "== PASS: Run completed (workdir=${workdir})"
  exit 0
fi
echo "== FAIL: no 'Run completed' in ${run_log}" >&2
exit 1
