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
export GPU_TARGETS_DEFAULT="cc90"
export GPU_NPRE_DEFAULT="8"

export MARLOWE_ACCOUNT="${MARLOWE_ACCOUNT:-marlowe-m000115}"
export MARLOWE_PARTITION="${MARLOWE_PARTITION:-preempt}"
export MARLOWE_GPU_MEM="${MARLOWE_GPU_MEM:-80G}"

CLUSTER_SBATCH_GPU_OPTS=(--account="${MARLOWE_ACCOUNT}" --partition="${MARLOWE_PARTITION}" -G 1 --mem="${MARLOWE_GPU_MEM}")
# CPU parity on Marlowe not validated; use preempt + same MPI modules until tested
CLUSTER_SBATCH_CPU_OPTS=(--account="${MARLOWE_ACCOUNT}" --partition="${MARLOWE_PARTITION}" --mem=80G)

export CLUSTER_GPU_MODULES="slurm nvhpc/25.5 cudnn/cuda12/9.3.0.75 gcc/64"
export FFTW_MODULE_DEFAULT="fftw/nvhpc-21.5/3.3.9"

export CPU_GCC_MODULE="gcc/64"
export CPU_OPENMPI_MODULE="openmpi"

export OT_AMR_LEVELMAX_DEFAULT="10"
export OT_AMR_SLURM_TIME_DEFAULT="02:00:00"
export OT_AMR_NPRE_DEFAULT="8"
