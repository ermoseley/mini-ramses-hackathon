#!/usr/bin/env bash
#SBATCH --job-name=alfven_alpha
#SBATCH --output=alfven_alpha_%j.out
#SBATCH --error=alfven_alpha_%j.err
#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1

set -euo pipefail

source "${HARNESS_DIR:-${SLURM_SUBMIT_DIR:?submit from ~/hackathon}}/hackathon_bootstrap.sh"

PROFILE="${PROFILE:-run}"
NML="${NML:-${HARNESS_DIR}/namelists/alfven_ad.nml}"
BUILD_BINARIES="${BUILD_BINARIES:-1}"
export MINIRAM GPU_HYDRO=1 GPU_MHD=1 GPU_NPSCAL=0 GPU_GRAV=0 GPU_UNITS=
export GPU_INIT="${GPU_INIT:-ALFVENAD}"
export BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd.alfvenad}"
export GPU_DEBUG="${GPU_DEBUG:-0}"
export DMO_NO_DEFAULT_CAPS=1
export DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-1}"
export RKG_ALPHAS="${RKG_ALPHAS:-0.5 2 10}"

workdir="${RUN_DIR}/alfven_ad_alpha_${SLURM_JOB_ID:-manual}"
mkdir -p "${workdir}"
cd "${workdir}"

echo "== alfven_ad alpha sweep job ${SLURM_JOB_ID:-manual} miniram=${MINIRAM} alphas=${RKG_ALPHAS}"
hackathon_load_modules || exit 2
unset NVCOMPILER_TERM

if [[ "${BUILD_BINARIES}" == "1" ]]; then
  build_log="${workdir}/build.log"
  hackathon_build_binary "${build_log}" || exit 2
fi

chmod +x "${HARNESS_DIR}/scripts/run_alfven_ad_alpha_sweep.sh"
AMBI_NML="${NML}" BIN_GPU="${BIN_GPU}" RUN_DIR="${workdir}" \
  RKG_ALPHAS="${RKG_ALPHAS}" AMBI_LEVEL="${AMBI_LEVEL:-7}" \
  "${HARNESS_DIR}/scripts/run_alfven_ad_alpha_sweep.sh" "${workdir}/sweep"

echo "== done. Report: ${workdir}/sweep/alfven_ad_alpha_report.txt"
