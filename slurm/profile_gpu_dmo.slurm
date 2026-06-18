#!/bin/bash
#SBATCH --job-name=gpu_dmo_profile
#SBATCH --output=gpu_dmo_profile_%j.out
#SBATCH --error=gpu_dmo_profile_%j.err
#SBATCH --time=01:30:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
# Partition/gres/mem: CLUSTER_SBATCH_GPU_OPTS in hackathon_sbatch.

# Profile GPU DMO (nsys / ncu).
#
# Submit from ~/hackathon:
#   ./submit_profiles.sh nsys-l7
#   ./submit_profiles.sh ncu-cic
#   ./submit_profiles.sh nsys-amr
#
# Or directly:
#   BUILD_BINARIES=1 PROFILE=nsys sbatch --export=ALL profile_gpu_dmo_a100.slurm
#   PART_DEP_ALGO=2 ./submit_profiles.sh nsys-l7
#   BUILD_BINARIES=0 PROFILE=ncu NCU_KERNEL='regex:.*cic_part_medium_kernel.*' \
#     NCU_CASE_TAG=cic_part_medium PROFILE_NSTEPMAX=2 sbatch --export=ALL profile_gpu_dmo_a100.slurm

set -euo pipefail

# shellcheck source=hackathon_bootstrap.sh
source "${HARNESS_DIR:-${SLURM_SUBMIT_DIR:?submit from ~/hackathon}}/hackathon_bootstrap.sh"

PROFILE="${PROFILE:-nsys}"          # nsys | ncu | run
BUILD_BINARIES="${BUILD_BINARIES:-1}"
NML="${NML:-${HARNESS_DIR}/dm_pic_poisson_l7.nml}"
BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d}"
RUN_DIR="${RUN_DIR:-${HARNESS_DIR}}"

# Short runs for ncu (default 2 steps); override with PROFILE_NSTEPMAX=0 to use nml as-is
if [[ "${PROFILE}" == "ncu" && -z "${PROFILE_NSTEPMAX+x}" ]]; then
  export PROFILE_NSTEPMAX=2
fi

# Nsight Compute defaults (override via sbatch --export=ALL)
NCU_KERNEL="${NCU_KERNEL:-regex:.*cic_part_medium_kernel.*}"
NCU_CASE_TAG="${NCU_CASE_TAG:-}"
NCU_LAUNCH_SKIP="${NCU_LAUNCH_SKIP:-0}"
NCU_LAUNCH_COUNT="${NCU_LAUNCH_COUNT:-5}"
# speed-of-light often yields "No metrics to collect" on Stellar; full is slower but reliable.
NCU_SET="${NCU_SET:-full}"

case_name="$(basename "${NML}" .nml)"
workdir="${RUN_DIR}/profiles_${SLURM_JOB_ID}/${case_name}"
mkdir -p "${workdir}"
cd "${workdir}"

echo "== profile job ${SLURM_JOB_ID} PROFILE=${PROFILE} case=${case_name}"
echo "   harness=${HARNESS_DIR} miniram=${MINIRAM} ic=${IC_DIR}"
echo "   workdir=${workdir}"
echo "   PART_DEP_ALGO=${PART_DEP_ALGO:-<unset>} (namelist part_dep_algo patch)"

hackathon_load_modules

NSYS_BIN="${NSYS_BIN:-$(command -v nsys || true)}"
NCU_BIN="${NCU_BIN:-$(command -v ncu || true)}"
for candidate in \
    "/opt/nvidia/hpc_sdk/Linux_x86_64/25.5/compilers/bin/nsys" \
    "/opt/nvidia/hpc_sdk/Linux_x86_64/25.5/compilers/bin/ncu"; do
  if [[ -x "${candidate}" ]]; then
    [[ "${candidate}" == *nsys ]] && NSYS_BIN="${NSYS_BIN:-${candidate}}"
    [[ "${candidate}" == *ncu ]] && NCU_BIN="${NCU_BIN:-${candidate}}"
  fi
done

if [[ "${BUILD_BINARIES}" -eq 1 ]]; then
  hackathon_build_binary "${workdir}/build.log"
else
  echo "== skipping build (BUILD_BINARIES=0)"
fi

hackathon_validate_inputs

run_nml="$(hackathon_prepare_case_nml "${NML}" "${case_name}" "${workdir}")"
cp "${run_nml}" "${workdir}/input.nml"
hackathon_apply_part_dep_algo "${workdir}/input.nml"
echo "== namelist: ${workdir}/input.nml (from ${run_nml})"
grep -E 'nstepmax|foutput|tend|initfile|cosmo|part_dep_algo' "${workdir}/input.nml" || true
if [[ -n "${PART_DEP_ALGO:-}" ]]; then
  if ! grep -qE "^[[:space:]]*part_dep_algo=${PART_DEP_ALGO}([^0-9]|$)" "${workdir}/input.nml"; then
    echo "ERROR: expected part_dep_algo=${PART_DEP_ALGO} in ${workdir}/input.nml" >&2
    exit 2
  fi
fi

run_log="${workdir}/run.log"
trace_base="${workdir}/${case_name}"

case "${PROFILE}" in
  nsys)
    if [[ -z "${NSYS_BIN}" || ! -x "${NSYS_BIN}" ]]; then
      echo "ERROR: nsys not found" >&2
      exit 2
    fi
    echo "== nsys profile -> ${trace_base}.nsys-rep"
    "${NSYS_BIN}" profile --trace=cuda,nvtx,osrt \
      --sample=none --cpuctxsw=none \
      --output="${trace_base}" --force-overwrite=true \
      "${BIN_GPU}" input.nml 2>&1 | tee "${run_log}"
    hackathon_export_nsys_stats "${trace_base}.nsys-rep" "${workdir}/profile_exports"
    ;;
  ncu)
    if [[ -z "${NCU_BIN}" || ! -x "${NCU_BIN}" ]]; then
      echo "ERROR: ncu not found" >&2
      exit 2
    fi
    ncu_out="${workdir}/ncu_${NCU_CASE_TAG:-${case_name}}"
    echo "== ncu kernel=${NCU_KERNEL} skip=${NCU_LAUNCH_SKIP} count=${NCU_LAUNCH_COUNT} set=${NCU_SET}"
    if [[ "${NCU_IMPORT_SOURCE:-no}" == "yes" ]]; then
      hackathon_ncu_stage_source_lookup "${workdir}"
      echo "== NCU import-source=yes (LINEINFO build; default->${NCU_DEFAULT_SOURCE:-<unset>})"
    fi
    ncu_args=(
      --set "${NCU_SET}"
      --target-processes all
      --kernel-name-base demangled
      --launch-skip "${NCU_LAUNCH_SKIP}"
      --launch-count "${NCU_LAUNCH_COUNT}"
      --force-overwrite
      --export "${ncu_out}"
    )
    if [[ -n "${NCU_KERNEL}" ]]; then
      ncu_args+=(--kernel-name "${NCU_KERNEL}")
    fi
    hackathon_ncu_append_capture_source_args ncu_args "${workdir}"
    if ! "${NCU_BIN}" "${ncu_args[@]}" \
      "${BIN_GPU}" input.nml 2>&1 | tee "${run_log}"; then
      echo "ERROR: ncu exited non-zero (see ${run_log})" >&2
      grep -iE 'error|warn|no kernel|no metric' "${run_log}" | tail -20 >&2 || true
      exit 2
    fi
    ncu_rep="${ncu_out}.ncu-rep"
    if [[ ! -f "${ncu_rep}" ]]; then
      echo "ERROR: expected NCU report not found: ${ncu_rep}" >&2
      echo "       Common causes: kernel filter matched nothing (try NCU_KERNEL='regex:.*cic_part_medium_kernel.*', NCU_LAUNCH_SKIP=0)" >&2
      echo "       or NCU_SET produced no sections (try NCU_SET=full)." >&2
      grep -iE 'error|warn|no kernel|no metric|profiled' "${run_log}" | tail -30 >&2 || true
      exit 2
    fi
    echo "== NCU report: ${ncu_rep} ($(du -h "${ncu_rep}" | cut -f1))"
    hackathon_ncu_export_source_artifacts \
      "${ncu_rep}" "${workdir}/profile_exports" "${case_name}" \
      "${NCU_BIN}" "${workdir}" || true
    ;;
  run)
    echo "== plain run (no profiler)"
    "${BIN_GPU}" input.nml 2>&1 | tee "${run_log}"
    ;;
  *)
    echo "ERROR: unknown PROFILE=${PROFILE} (use nsys|ncu|run)" >&2
    exit 2
    ;;
esac

echo "== done. Outputs in ${workdir}"
ls -la "${workdir}"
