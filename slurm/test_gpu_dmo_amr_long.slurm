#!/bin/bash
#SBATCH --job-name=gpu_dmo_amr_long
#SBATCH --output=gpu_dmo_amr_long_%j.out
#SBATCH --error=gpu_dmo_amr_long_%j.err
#SBATCH --time=02:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
# Partition/gres/mem: CLUSTER_SBATCH_GPU_OPTS in hackathon_sbatch.

# Long AMR-only GPU run (dm_pic_poisson_l7_amr_l8). Intended after Step-2 CIC
# speedup: ~250 coarse steps is ~3–5 min of GPU time plus snapshot I/O.
#
# Submit from harness directory:
#   ./submit_profiles.sh test-amr-long
#   BUILD_BINARIES=0 sbatch --export=ALL slurm/test_gpu_dmo_amr_long.slurm
#
# Overrides (sbatch --export=ALL): AMR_NSTEPMAX, AMR_FOUTPUT, AMR_TEND,
#   PART_DEP_ALGO, BUILD_BINARIES, MINIRAM, IC_DIR, DMO_WORK, BIN_GPU
#
# Example: PART_DEP_ALGO=2 ./submit_profiles.sh test-amr-long

set -euo pipefail

HARNESS="${SLURM_SUBMIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export HARNESS_DIR="${HARNESS}"

# shellcheck source=hackathon_bootstrap.sh
source "${HARNESS}/hackathon_bootstrap.sh"

export DM_NML="${DM_NML:-$(hackathon_nml dm_pic_poisson_l7_amr_l8.nml)}"
export PHYS_NSTEPMAX="${AMR_NSTEPMAX:-250}"
export PHYS_FOUTPUT="${AMR_FOUTPUT:-25}"
export PHYS_TEND="${AMR_TEND:-3.0}"
export PHYS_EXTEND=1
export BUILD_BINARIES="${BUILD_BINARIES:-1}"
export DMO_WORK="${DMO_WORK:-${HARNESS}/dmo_amr_long_${SLURM_JOB_ID:-manual}}"

exec bash "${HARNESS}/${GPU_SLURM_TEST:-slurm/test_gpu_dmo.slurm}"
