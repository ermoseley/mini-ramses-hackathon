#!/bin/bash
# Template: full-grid MHD+turb (256^3 default). Submit via submit_profiles.sh mhd-turb-l8
# or: sbatch with WORK, NML, BIN_GPU exported (see hackathon_mhd_turb_prepare_run).
#SBATCH --job-name=mhd_turb_l8
#SBATCH --output=slurm_%j.out
#SBATCH --error=slurm_%j.err
#SBATCH --time=06:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --mem=80G

set -euo pipefail

: "${HARNESS_DIR:?HARNESS_DIR required}"
: "${MINIRAM:?MINIRAM required}"
: "${WORK:?WORK run directory required}"
: "${NML:?NML path required}"
: "${BIN_GPU:?BIN_GPU required}"

export CLUSTER="${CLUSTER:-stellar}"
export RUN_DIR="${RUN_DIR:-${HARNESS_DIR}/runs}"
cd "${WORK}"

source "${HARNESS_DIR}/bin/hackathon-env.sh"
source "${HARNESS_DIR}/hackathon_common.sh"
hackathon_load_modules || exit 2
unset NVCOMPILER_TERM
hackathon_load_fftw || exit 2
export LD_LIBRARY_PATH="${FFTW}/lib64:${FFTW}/lib:${LD_LIBRARY_PATH:-}"

export MHD_TURB_BZ="${MHD_TURB_BZ:-0.7792435587233456}"
export MHD_TURB_LEVEL="${MHD_TURB_LEVEL:-8}"
hackathon_ensure_mhd_turb_ics "${MHD_TURB_LEVEL}"
export IC_DIR
hackathon_stage_dmo_run_nml "${NML}" "${WORK}/input.nml"

echo "== job ${SLURM_JOB_ID} WORK=${WORK} NML=${NML} BIN=${BIN_GPU}"
ldd "${BIN_GPU}" | grep -E "cudafor|fftw|not found" || true
nvidia-smi || true
date
/usr/bin/time -f "wall_sec=%e" "${BIN_GPU}" input.nml 2>&1 | tee run.log
date
grep -E "emag|Run completed|Writing output|tout|Time=" run.log | tail -30
