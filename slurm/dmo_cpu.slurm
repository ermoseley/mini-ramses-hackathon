#!/bin/bash
#SBATCH --job-name=dmo_cpu
#SBATCH --output=dmo_cpu_%j.out
#SBATCH --error=dmo_cpu_%j.err
#SBATCH --time=01:00:00
#SBATCH --nodes=1
#SBATCH --ntasks=96
#SBATCH --cpus-per-task=1
# Partition/mem: CLUSTER_SBATCH_CPU_OPTS in hackathon_sbatch.

# CPU run on 96 MPI ranks. Default: dmo.nml (cosmological DMO, levelmin=7 levelmax=15).
# --exclusive --mem=730G: full pu node (~100G OOMs for levelmax=15). Override: DMO_SLURM_MEM=512G sbatch ...
# Output via delta_aout/aend. Override aend with DMO_AEND at submit time.
#
# Submit from ~/hackathon:
#   ./submit_profiles.sh dmo-cpu
#   sbatch dmo_cpu.slurm
#
# Overrides:
#   IC_DIR, NML, BIN_CPU, RUN_DIR, MINIRAM, BUILD_BINARIES (default 0),
#   CPU build is always serial make -j1 (Fortran .mod races under parallel make),
#   GCC_MODULE (default gcc-toolset/10), OPENMPI_MODULE (default openmpi/gcc-toolset-10/4.1.0),
#   OPENMPI_MODULES (optional space-separated module try list),
#   OPENMPI_USE_MODULES=0 only for /usr/local login-node install,
#   DMO_NSTEPMAX, DMO_FOUTPUT, DMO_TEND, PART_DEP_ALGO (rewrites namelist in place).

set -euo pipefail

# shellcheck source=hackathon_bootstrap.sh
source "${HARNESS_DIR:-${SLURM_SUBMIT_DIR:?submit from ~/hackathon}}/hackathon_bootstrap.sh"
hackathon_clear_stale_mpi_env

NML="${NML:-${HARNESS_DIR}/dmo.nml}"
DMO_NSTEPMAX="${DMO_NSTEPMAX:-1000}"
DMO_FOUTPUT="${DMO_FOUTPUT:-25}"
DMO_TEND="${DMO_TEND:-3.0}"
CPU_MHD="${CPU_MHD:-0}"
if [[ -z "${BIN_CPU:-}" ]]; then
  if [[ "${CPU_MHD}" == "1" ]]; then
    BIN_CPU="${MINIRAM}/bin/ramses3d.mhd.cpu"
  else
    BIN_CPU="${MINIRAM}/bin/ramses3d.cpu"
  fi
fi
BUILD_BINARIES="${BUILD_BINARIES:-0}"

case_name="$(basename "${NML}" .nml)"
workdir="${RUN_DIR}/dmo_cpu_${SLURM_JOB_ID:-manual}/${case_name}"
mkdir -p "${workdir}"
cd "${workdir}"

echo "== dmo_cpu job ${SLURM_JOB_ID:-manual} case=${case_name}"
echo "   harness=${HARNESS_DIR} miniram=${MINIRAM} ic=${IC_DIR}"
echo "   workdir=${workdir}  ntasks=${SLURM_NTASKS:-96}"

# Stellar pu: OpenMPI runtime only on compute. Use a pre-built ramses3d.cpu (BUILD_BINARIES=0).
OPENMPI_USE_MODULES="${OPENMPI_USE_MODULES:-1}"
GCC_MODULE="${GCC_MODULE:-gcc-toolset/10}"
OPENMPI_MODULE="${OPENMPI_MODULE:-openmpi/gcc-toolset-10/4.1.0}"
export OPENMPI_USE_MODULES GCC_MODULE OPENMPI_MODULE

if [[ "${BUILD_BINARIES}" -eq 1 ]]; then
  echo "WARNING: BUILD_BINARIES=1 on compute; pu nodes lack mpif90 — build on login instead." >&2
  hackathon_load_cpu_mpi
  export MPIF90 MPICC PATH LD_LIBRARY_PATH
else
  hackathon_load_cpu_mpi_runtime
  export PATH LD_LIBRARY_PATH
fi

if [[ "${BUILD_BINARIES}" -eq 1 ]]; then
  echo "== building CPU MPI binary from ${MINIRAM} (Makefile.cpu, MPI=1 COMPILER=GNU)"
  (
    set -euo pipefail
    export MPIF90 MPICC PATH LD_LIBRARY_PATH
    cd "${MINIRAM}/bin"
    echo "Checkout HEAD: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
    make clean || rm -f ./*.o ./*.mod ./ramses3d ./ramses3d.cpu
    make -f Makefile.cpu -j 1 \
         COMPILER=GNU MPI=1 MPIF90="${MPIF90}" DEBUG=0 NHILBERT=1 \
         GRAV="${CPU_GRAV:-$([[ "${CPU_MHD}" == "1" ]] && echo 0 || echo 1)}" \
         HYDRO="${CPU_HYDRO:-$([[ "${CPU_MHD}" == "1" ]] && echo 1 || echo 0)}" \
         MHD="${CPU_MHD}" NPSCAL="${CPU_NPSCAL:-0}" NPRE="${CPU_NPRE:-4}" NDIM=3 \
         ${CPU_UNITS:+UNITS="${CPU_UNITS}"} ramses \
      2>&1 | tee "${workdir}/build_cpu.log"
    if [[ -e ./ramses3d.cpu ]]; then
      [[ "$(readlink -f ./ramses3d.cpu)" != "$(readlink -f "${BIN_CPU}")" ]] && \
        cp -f ./ramses3d.cpu "${BIN_CPU}"
    elif [[ -e ./ramses3d ]]; then
      cp -f ./ramses3d "${BIN_CPU}"
    else
      echo "ERROR: no ramses3d.cpu or ramses3d after build" >&2
      exit 1
    fi
  )
else
  echo "== skipping build (BUILD_BINARIES=0)"
fi

if [[ ! -e "${BIN_CPU}" ]]; then
  echo "ERROR: missing CPU binary: ${BIN_CPU}" >&2
  exit 2
fi
if [[ ! -e "${NML}" ]]; then
  echo "ERROR: missing namelist: ${NML}" >&2
  exit 2
fi

# Stage a copy of the namelist into the work dir; rewrite initfile() and any
# optional caps so the harness nml template stays untouched.
run_nml="${workdir}/input.nml"
hackathon_stage_dmo_run_nml "${NML}" "${run_nml}"

apply_kv() {
  local key="$1" val="$2" file="$3"
  if grep -qE "^[[:space:]]*${key}=" "${file}"; then
    sed -i.bak -E "s/^[[:space:]]*${key}=.*/ ${key}=${val}/" "${file}"
    rm -f "${file}.bak"
  elif [[ "${key}" == "nstepmax" ]]; then
    sed -i.bak -E "/^[[:space:]]*&RUN_PARAMS/a ${key}=${val}" "${file}"
    rm -f "${file}.bak"
  elif [[ "${key}" == "foutput" || "${key}" == "tend" || "${key}" == "aend" ]]; then
    sed -i.bak -E "/^[[:space:]]*&OUTPUT_PARAMS/a ${key}=${val}" "${file}"
    rm -f "${file}.bak"
  fi
}
apply_kv nstepmax "${DMO_NSTEPMAX}" "${run_nml}"
apply_kv foutput  "${DMO_FOUTPUT}"  "${run_nml}"
apply_kv tend     "${DMO_TEND}"     "${run_nml}"
[[ -n "${DMO_AEND:-}" ]] && apply_kv aend "${DMO_AEND}" "${run_nml}"
hackathon_apply_part_dep_algo "${run_nml}"

echo "== namelist: ${run_nml}"
grep -E 'nstepmax|foutput|tend|delta_tout|aend|delta_aout|initfile|cosmo|levelmin|levelmax|ngridmax|ncachemax|m_refine|part_dep_algo' "${run_nml}" || true

run_log="${workdir}/run.log"
echo "== launching: srun -n ${SLURM_NTASKS:-96} ${BIN_CPU} input.nml"
srun -n "${SLURM_NTASKS:-96}" --cpus-per-task="${SLURM_CPUS_PER_TASK:-1}" \
     "${BIN_CPU}" input.nml 2>&1 | tee "${run_log}"

if ! compgen -G "${workdir}/output_*" >/dev/null; then
  echo "ERROR: no output_NNNNN/ directories produced in ${workdir}" >&2
  exit 4
fi

echo "== done. Outputs in ${workdir}"
ls -d "${workdir}"/output_* 2>/dev/null | sort
