# Marlowe (Stanford H100) — scratch harness at /scratch/m000115/hackathon
export CLUSTER=marlowe
export CLUSTER_NAME="Marlowe (H100)"

export HARNESS_DIR_DEFAULT="/scratch/m000115/hackathon"
export RUN_DIR_DEFAULT="/scratch/m000115/hackathon"
export MINIRAM_DEFAULT="${HOME}/mini-ramses-dev"

export GPU_MAKEFILE="Makefile.h100"
export GPU_SLURM_TEST="slurm/test_gpu_dmo.slurm"
export GPU_SLURM_PROFILE="slurm/profile_gpu_dmo.slurm"
export GPU_CUDA_ARCH_DEFAULT="sm_90"
export GPU_TARGETS_DEFAULT="cc90,cuda12.5"
export GPU_NPRE_DEFAULT="8"
export NVHPC_MODULE="${NVHPC_MODULE:-nvhpc/24.7}"

export MARLOWE_ACCOUNT="${MARLOWE_ACCOUNT:-marlowe-m000115}"
export MARLOWE_PARTITION="${MARLOWE_PARTITION:-preempt}"
export MARLOWE_GPU_MEM="${MARLOWE_GPU_MEM:-80G}"

# Host FFTW for TURB=1 (no fftw module on Marlowe; user-built NVHPC prefix).
export MARLOWE_FFTW_PREFIX="${MARLOWE_FFTW_PREFIX:-/scratch/m000115/emoseley/fftw-nvhpc-3.3.10}"
export FFTW="${FFTW:-${MARLOWE_FFTW_PREFIX}}"

CLUSTER_SBATCH_GPU_OPTS=(--account="${MARLOWE_ACCOUNT}" --partition="${MARLOWE_PARTITION}" -G 1 --mem="${MARLOWE_GPU_MEM}")
# CPU parity on Marlowe not validated; use preempt + same MPI modules until tested
CLUSTER_SBATCH_CPU_OPTS=(--account="${MARLOWE_ACCOUNT}" --partition="${MARLOWE_PARTITION}" --mem=80G)

export CLUSTER_GPU_MODULES="slurm ${NVHPC_MODULE} cudnn/cuda12/9.3.0.75 gcc/64"
# Module unavailable on Marlowe; hackathon_load_fftw uses FFTW= prefix above when set.
export FFTW_MODULE_DEFAULT=""

export CPU_GCC_MODULE="gcc/64"
export CPU_OPENMPI_MODULE="openmpi"

export OT_AMR_LEVELMAX_DEFAULT="10"
export OT_AMR_SLURM_TIME_DEFAULT="02:00:00"
export OT_AMR_NPRE_DEFAULT="8"
