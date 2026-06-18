#!/bin/bash
#SBATCH --job-name=gpu_dmo_test
#SBATCH --output=gpu_dmo_test_%j.out
#SBATCH --error=gpu_dmo_test_%j.err
#SBATCH --time=00:45:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
# Partition/gres/mem: CLUSTER_SBATCH_GPU_OPTS in hackathon_sbatch.

# GPU DMO smoke test. CLUSTER profile sets Makefile/CUDA_ARCH.
# Harness scripts and namelists live alongside this file in
# ~/hackathon; RAMSES source defaults to ~/mini-ramses-dev (cluster layout).
# Override MINIRAM if your checkout lives elsewhere.
#
# Submit from the hackathon directory:
#   cd ~/hackathon && sbatch test_gpu_dmo_a100.slurm
#
# Overrides: IC_DIR, NML, DM_NML, DM_NMLS, BIN_GPU, BIN_CPU, RUN_DIR, MINIRAM,
#            HARNESS_DIR, COMPARE_SCRIPT, PLOT_SCRIPT, PART_RTOL, PART_ATOL,
#            MAX_BAD_FRAC, DMO_WORK, BUILD_BINARIES,
#            PHYS_NSTEPMAX, PHYS_FOUTPUT, PHYS_TEND, PHYS_EXTEND, AMR_NSTEPMAX,
#            AMR_FOUTPUT, AMR_TEND, PART_DEP_ALGO, SKIP_CPU_RUN,
#            SKIP_COMPARE, SKIP_PLOT, REQUIRE_LEVEL8
#
# Example: PART_DEP_ALGO=2 ./submit_profiles.sh test

set -euo pipefail

# --- Paths (relative to this harness unless overridden) -----------------------
# SLURM_SUBMIT_DIR / HARNESS_DIR point at ~/hackathon (not the spool copy of this script).
# shellcheck source=hackathon_bootstrap.sh
source "${HARNESS_DIR:-${SLURM_SUBMIT_DIR:?submit from ~/hackathon}}/hackathon_bootstrap.sh"
RUN_DIR="${RUN_DIR:-${HARNESS_DIR}}"

# Source checkout — not part of the hackathon bundle.
MINIRAM="${MINIRAM:-${HOME}/mini-ramses-dev}"

# Grafic ICs shipped in ics_ramses/ next to this script.
IC_DIR="${IC_DIR:-${HARNESS_DIR}/ics_ramses}"
# -----------------------------------------------------------------------------

mkdir -p "${RUN_DIR}"
cd "${RUN_DIR}"

COMPARE_SCRIPT="${COMPARE_SCRIPT:-${HARNESS_DIR}/compare_dmo_outputs.py}"
PLOT_SCRIPT="${PLOT_SCRIPT:-${HARNESS_DIR}/plot_dmo_compare.py}"
IO_SCRIPT="${IO_SCRIPT:-${HARNESS_DIR}/ramses_output_io.py}"

: "${BIN_GPU:=${MINIRAM}/bin/ramses3d}"
: "${BIN_CPU:=${MINIRAM}/bin/ramses3d.cpu}"
: "${PART_RTOL:=1e-4}"
: "${PART_ATOL:=1e-6}"
: "${MAX_BAD_FRAC:=1e-4}"
: "${DMO_WORK:=${RUN_DIR}/dmo_work_${SLURM_JOB_ID:-manual}}"
: "${BUILD_BINARIES:=1}"
# AMR case (dm_pic_poisson_l7_amr_l8) overrides via prepare_case_nml when
# PHYS_EXTEND=1. Post–Step-2 CIC, 50 steps ≈ 40 s GPU; 100 steps ≈ 80 s.
: "${PHYS_NSTEPMAX:=100}"
: "${PHYS_FOUTPUT:=20}"
: "${PHYS_TEND:=1.5}"
: "${PHYS_EXTEND:=1}"
: "${SKIP_CPU_RUN:=1}"
: "${SKIP_COMPARE:=1}"
: "${SKIP_PLOT:=1}"
: "${REQUIRE_LEVEL8:=0}"

DEFAULT_DM_NMLS_SUITE=(
  "${HARNESS_DIR}/dm_pic_poisson_l7.nml"
  "${HARNESS_DIR}/dm_pic_poisson_l7_amr_l8.nml"
)

if [[ -n "${NML:-}" ]]; then
  CASE_NMLS=("${NML}")
  APPLY_IC_OVERRIDE=0
elif [[ -n "${DM_NMLS:-}" ]]; then
  read -r -a CASE_NMLS <<< "${DM_NMLS}"
  APPLY_IC_OVERRIDE=1
elif [[ -n "${DM_NML:-}" ]]; then
  CASE_NMLS=("${DM_NML}")
  APPLY_IC_OVERRIDE=1
else
  CASE_NMLS=("${DEFAULT_DM_NMLS_SUITE[@]}")
  APPLY_IC_OVERRIDE=1
fi

# --- Modules (Stellar / Princeton defaults) ----------------------------------

module load nvhpc/25.5
# Use module-provided paths when available; only fall back if unset.
if [[ -z "${NVHPC_CUDA_HOME:-}" ]]; then
  for candidate in \
      "/opt/nvidia/hpc_sdk/Linux_x86_64/"*/cuda/* \
      "/cm/shared/apps/nvhpc/"*/Linux_x86_64/*/cuda/*; do
    if [[ -d "${candidate}" ]]; then
      export NVHPC_CUDA_HOME="${candidate}"
      break
    fi
  done
fi
# -----------------------------------------------------------------------------

export CUDA_VISIBLE_DEVICES=0
export NVCOMPILER_TERM=trace
export NVCOMPILER_FPE=

COMPILE_LOG="${RUN_DIR}/compile_log_a100.txt"
{
  echo ""
  echo "==== gpu_dmo_a100 job $(date -Is) ===="
  echo "SLURM_JOB_ID=${SLURM_JOB_ID:-}"
  echo "SCRIPT_DIR=${SCRIPT_DIR}"
  echo "RUN_DIR=${RUN_DIR}"
  echo "HARNESS_DIR=${HARNESS_DIR}"
  echo "MINIRAM=${MINIRAM}"
  echo "BIN_GPU=${BIN_GPU}"
  echo "IC_DIR=${IC_DIR}"
  echo "CASE_NMLS=${CASE_NMLS[*]}"
  echo "DMO_WORK=${DMO_WORK}"
  echo "PHYS_NSTEPMAX=${PHYS_NSTEPMAX} PHYS_FOUTPUT=${PHYS_FOUTPUT} PHYS_TEND=${PHYS_TEND}"
  echo "PHYS_EXTEND=${PHYS_EXTEND} SKIP_CPU_RUN=${SKIP_CPU_RUN} SKIP_COMPARE=${SKIP_COMPARE} SKIP_PLOT=${SKIP_PLOT}"
} >> "${COMPILE_LOG}"

nvidia-smi || true
echo "CUDA_VISIBLE_DEVICES=${CUDA_VISIBLE_DEVICES}"
nvfortran --version || true

if [[ "${BUILD_BINARIES}" -eq 1 ]]; then
  hackathon_build_binary "${RUN_DIR}/build_a100_${SLURM_JOB_ID:-manual}.log"

  if [[ "${SKIP_CPU_RUN}" -eq 0 && -e "${MINIRAM}/bin/Makefile.cpu" ]]; then
    (
      set -euo pipefail
      cd "${MINIRAM}/bin"
      make clean || rm -f ./*.o ./*.mod ./ramses3d.cpu
      make -f Makefile.cpu -j 1 DEBUG=0 NHILBERT=1 GRAV=1 HYDRO=0 NDIM=3 UNITS=COSMO ramses \
        2>&1 | tee "${RUN_DIR}/build_cpu_${SLURM_JOB_ID:-manual}.log"
      cp -f ramses3d "${BIN_CPU}"
    )
  fi
fi

for b in "${IO_SCRIPT}" "${COMPARE_SCRIPT}" "${PLOT_SCRIPT}"; do
  if [[ ! -e "${b}" ]]; then
    echo "ERROR: missing harness script: ${b}" >&2
    exit 2
  fi
done
if [[ "${SKIP_CPU_RUN}" -eq 0 && ! -e "${BIN_CPU}" ]]; then
  echo "ERROR: missing CPU binary: ${BIN_CPU}" >&2
  exit 2
fi
for b in "${BIN_GPU}" "${CASE_NMLS[@]}"; do
  if [[ ! -e "${b}" ]]; then
    echo "ERROR: missing: ${b}" >&2
    exit 2
  fi
done
if [[ ! -d "${IC_DIR}" ]]; then
  echo "ERROR: IC directory not found: ${IC_DIR}" >&2
  exit 2
fi

chmod +x "${COMPARE_SCRIPT}" "${PLOT_SCRIPT}" 2>/dev/null || true

SRUN_LAUNCHER=(srun -n 1 --cpus-per-task="${SLURM_CPUS_PER_TASK:-4}" --gres=gpu:1)
LAUNCHER_STR="${SRUN_LAUNCHER[*]}"

prepare_case_nml() {
  local template_nml="$1" case_index="$2" case_name="$3"
  local out_nml="${RUN_DIR}/run_dmo_auto_${case_index}_${case_name}.nml"
  local src="${template_nml}"

  if [[ "${APPLY_IC_OVERRIDE}" -eq 1 && -n "${IC_DIR}" ]]; then
    local ic_init
    ic_init="$(hackathon_grafic_ic_link_name)"
    sed "s|^ initfile(1)=.*| initfile(1)='${ic_init}'|" "${template_nml}" > "${out_nml}.ic"
    src="${out_nml}.ic"
  fi

  if [[ "${PHYS_EXTEND}" -eq 1 && "${case_name}" == *amr_l8* ]]; then
    sed -E \
      -e "s/^[[:space:]]*nstepmax=.*/ nstepmax=${PHYS_NSTEPMAX}/" \
      -e "s/^[[:space:]]*foutput=.*/ foutput=${PHYS_FOUTPUT}/" \
      -e "s/^[[:space:]]*tend=.*/ tend=${PHYS_TEND}/" \
      "${src}" > "${out_nml}"
  elif [[ "${src}" != "${template_nml}" ]]; then
    cp "${src}" "${out_nml}"
  elif [[ -n "${PART_DEP_ALGO:-}" ]]; then
    cp "${template_nml}" "${out_nml}"
  else
    echo "${template_nml}"
    return
  fi
  rm -f "${out_nml}.ic"
  hackathon_apply_part_dep_algo "${out_nml}"
  echo "${out_nml}"
}

run_one() {
  local label="$1" bin="$2" outdir="$3" case_nml="$4"
  local run_nml="input.nml"
  echo "== ${label} run: ${bin}"
  mkdir -p "${outdir}"
  if [[ "${APPLY_IC_OVERRIDE}" -eq 1 && -n "${IC_DIR}" ]]; then
    hackathon_stage_grafic_ic_symlink "${IC_DIR}" "${outdir}"
  fi
  cp "${case_nml}" "${outdir}/${run_nml}"
  pushd "${outdir}" >/dev/null
  # shellcheck disable=SC2086
  ${LAUNCHER_STR} "${bin}" "${run_nml}" 2>&1 | tee "${outdir}/run.log"
  popd >/dev/null
  if ! compgen -G "${outdir}/output_*" >/dev/null; then
    echo "ERROR: ${label} run produced no output_NNNNN/ directories in ${outdir}" >&2
    exit 4
  fi
}

case_index=0
n_case_fail=0
for template_nml in "${CASE_NMLS[@]}"; do
  case_index=$((case_index + 1))
  case_name="$(basename "${template_nml}" .nml)"
  case_work="${DMO_WORK}/${case_index}_${case_name}"
  case_nml="$(prepare_case_nml "${template_nml}" "${case_index}" "${case_name}")"

  echo "Starting DMO case ${case_index}: ${case_name}"
  echo "  template_nml=${template_nml}"
  echo "  case_nml=${case_nml}"
  echo "  case_work=${case_work}"
  if [[ -n "${PART_DEP_ALGO:-}" ]]; then
    echo "  PART_DEP_ALGO=${PART_DEP_ALGO}"
    grep -E '^[[:space:]]*part_dep_algo=' "${case_nml}" || true
  fi
  mkdir -p "${case_work}"

  if [[ "${SKIP_CPU_RUN}" -eq 0 ]]; then
    run_one "CPU" "${BIN_CPU}" "${case_work}/cpu_run" "${case_nml}"
  else
    echo "== skipping CPU run (SKIP_CPU_RUN=1)"
  fi
  run_one "GPU" "${BIN_GPU}" "${case_work}/gpu_run" "${case_nml}"

  echo "Commit/refinement summary for ${case_name}:"
  for log in "${case_work}/cpu_run/run.log" "${case_work}/gpu_run/run.log"; do
    [[ -f "${log}" ]] || continue
    echo "== ${log}"
    grep -E "last commit =|compile date =|compile command =|Level  7 has|Level  8 has|Run completed|econs=" "${log}" || true
  done

  if [[ "${SKIP_COMPARE}" -eq 0 && "${SKIP_CPU_RUN}" -eq 0 ]]; then
    echo "== comparing snapshot outputs (broad agreement)"
    if ! python3 "${COMPARE_SCRIPT}" \
      --cpu "${case_work}/cpu_run" \
      --gpu "${case_work}/gpu_run" \
      --rtol "${PART_RTOL}" \
      --atol "${PART_ATOL}" \
      --max-bad-frac "${MAX_BAD_FRAC}"; then
      n_case_fail=$((n_case_fail + 1))
      echo "ERROR: compare failed for case ${case_name}" >&2
    fi

    if [[ "${SKIP_PLOT}" -eq 0 ]]; then
      echo "== plotting last-snapshot diagnostics"
      python3 "${PLOT_SCRIPT}" \
        --cpu "${case_work}/cpu_run" \
        --gpu "${case_work}/gpu_run" \
        --outdir "${case_work}/compare_plots" || echo "WARNING: plot step failed (non-fatal)" >&2
    fi
  else
    echo "== skipping output compare/plot (SKIP_COMPARE=${SKIP_COMPARE}, SKIP_CPU_RUN=${SKIP_CPU_RUN})"
  fi

  echo "DMO case ${case_index} finished. Outputs under: ${case_work}"
done

if [[ "${n_case_fail}" -gt 0 ]]; then
  echo "FAIL: ${n_case_fail} case(s) outside broad-agreement limits" >&2
  exit 5
fi

echo "All DMO cases finished. Work tree: ${DMO_WORK}"
