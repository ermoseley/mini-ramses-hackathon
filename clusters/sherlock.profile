# Sherlock (Stanford) — A100; scratch path TBD (fill HARNESS_DIR_DEFAULT before deploy)
export CLUSTER=sherlock
export CLUSTER_NAME="Sherlock (A100)"

# TODO: confirm scratch path (e.g. /scratch/users/$USER/hackathon)
export HARNESS_DIR_DEFAULT="${HARNESS_DIR_DEFAULT:-/scratch/users/${USER}/hackathon}"
export RUN_DIR_DEFAULT="${RUN_DIR_DEFAULT:-${HARNESS_DIR_DEFAULT}}"
export MINIRAM_DEFAULT="${HOME}/mini-ramses-dev"

export GPU_MAKEFILE="Makefile.a100"
export GPU_SLURM_TEST="slurm/test_gpu_dmo.slurm"
export GPU_SLURM_PROFILE="slurm/profile_gpu_dmo.slurm"
export GPU_CUDA_ARCH_DEFAULT="sm_80"
export GPU_TARGETS_DEFAULT="cc80"
export GPU_NPRE_DEFAULT="4"

CLUSTER_SBATCH_GPU_OPTS=(--partition=gpu -G 1 --mem=40G)
# Optional Brio-Wu GPU constraint (Sherlock): export BRIO_WU_GPU_CONSTRAINT=GPU_MEM:80GB
CLUSTER_SBATCH_CPU_OPTS=(--partition=normal --mem=64G)

export CLUSTER_GPU_MODULES="nvhpc/25.5"
export FFTW_MODULE_DEFAULT="fftw/nvhpc-21.5/3.3.9"

export CPU_GCC_MODULE="gcc/10.1.0"
export CPU_OPENMPI_MODULE="openmpi/4.1.0"

export OT_AMR_LEVELMAX_DEFAULT="8"
export OT_AMR_SLURM_TIME_DEFAULT="00:05:00"
export OT_AMR_NPRE_DEFAULT="4"
