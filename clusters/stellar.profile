# Stellar (Princeton) — A100, scratch harness at /scratch/gpfs/moseley/hackathon
export CLUSTER=stellar
export CLUSTER_NAME="Stellar (A100)"

export HARNESS_DIR_DEFAULT="/scratch/gpfs/moseley/hackathon"
export RUN_DIR_DEFAULT="/scratch/gpfs/moseley/hackathon"
export MINIRAM_DEFAULT="${HOME}/mini-ramses-dev"

export GPU_MAKEFILE="Makefile.a100"
export GPU_SLURM_TEST="slurm/test_gpu_dmo.slurm"
export GPU_SLURM_PROFILE="slurm/profile_gpu_dmo.slurm"
export GPU_CUDA_ARCH_DEFAULT="sm_80"
export GPU_NPRE_DEFAULT="4"

# Slurm resource flags (passed by hackathon_sbatch; not in #SBATCH headers)
CLUSTER_SBATCH_GPU_OPTS=(--partition=gpu --qos=gpu --gres=gpu:1 --mem=40G)
CLUSTER_SBATCH_CPU_OPTS=(--partition=pu --exclusive --mem=730G)

# Environment modules (space-separated for hackathon_load_modules)
export CLUSTER_GPU_MODULES="nvhpc/25.5"
export FFTW_MODULE_DEFAULT="fftw/nvhpc-21.5/3.3.9"

# CPU MPI (dmo-cpu, ot-cpu)
export CPU_GCC_MODULE="gcc-toolset/10"
export CPU_OPENMPI_MODULE="openmpi/gcc-toolset-10/4.1.0"

# Case-specific defaults
export OT_AMR_LEVELMAX_DEFAULT="8"
export OT_AMR_SLURM_TIME_DEFAULT="00:05:00"
export OT_AMR_NPRE_DEFAULT="4"
