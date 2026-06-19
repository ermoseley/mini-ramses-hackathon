#!/bin/bash
# Reference batch template for 256^3 MHD turb (mhd_turb_full_l8.nml).
# Prefer: ./submit_profiles.sh mhd-turb-l8-full
#SBATCH --job-name=mhd_turb_l8
#SBATCH --output=slurm_%j.out
#SBATCH --error=slurm_%j.err
#SBATCH --time=06:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
# Partition/gres/mem/account: hackathon_sbatch / CLUSTER_SBATCH_GPU_OPTS
