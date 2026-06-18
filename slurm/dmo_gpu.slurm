#!/bin/bash
#SBATCH --job-name=dmo_gpu
#SBATCH --output=dmo_gpu_%j.out
#SBATCH --error=dmo_gpu_%j.err
#SBATCH --time=00:15:00
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=1
# Partition/account/gres/mem: set via CLUSTER_SBATCH_GPU_OPTS in hackathon_sbatch.

# GPU run. Default: dmo.nml (cosmological DMO, levelmin=7 levelmax=15).
# Output via delta_aout/aend. Override aend with DMO_AEND at submit time.
# Plain run by default; set PROFILE=nsys to trace or PROFILE=sanitize for
# compute-sanitizer memcheck.
#
# Submit from ~/hackathon:
#   ./submit_profiles.sh dmo-gpu
#   sbatch dmo_gpu.slurm
#
# Overrides:
#   IC_DIR, IC_ZOOM_DIR (grafic_zoom cases), NML, BIN_GPU, RUN_DIR, MINIRAM, BUILD_BINARIES,
#   GPU_HYDRO (0|1; 1 -> HYDRO=1 build, default bin ramses3d.hydro),
#   GPU_NPRE (Makefile NPRE; 8=double, 4=single; default 4),
#   GPU_FASTMATH (0|1; default 0 — no -gpu=...,fastmath),
#   GPU_DEBUG (0|1; sanitizer defaults to 1),
#   PROFILE (run|nsys|ncu|sanitize), DMO_GPU_LAUNCH_BLOCKING,
#   NCU_KERNEL, NCU_LAUNCH_SKIP, NCU_LAUNCH_COUNT, NCU_SET (when PROFILE=ncu),
#   DMO_NSTEPMAX, DMO_FOUTPUT, DMO_TEND, DMO_NCACHEMAX (optional; else namelist value kept),
#   DMO_SLURM_TIME (sbatch --time override; cosmo-zoom default 12:00:00),
#   PART_DEP_ALGO (patch &POISSON_PARAMS part_dep_algo when set)
#   (rewrites the namelist in place when keys exist).

set -euo pipefail

# shellcheck source=hackathon_bootstrap.sh
source "${HARNESS_DIR:-${SLURM_SUBMIT_DIR:?submit from ~/hackathon}}/hackathon_bootstrap.sh"

PROFILE="${PROFILE:-run}"           # run | nsys | ncu | sanitize
NCU_KERNEL="${NCU_KERNEL:-}"
NCU_LAUNCH_SKIP="${NCU_LAUNCH_SKIP:-0}"
NCU_LAUNCH_COUNT="${NCU_LAUNCH_COUNT:-5}"
NCU_SET="${NCU_SET:-full}"
NML="${NML:-${HARNESS_DIR}/dmo.nml}"
DMO_NSTEPMAX="${DMO_NSTEPMAX:-1000}"
DMO_FOUTPUT="${DMO_FOUTPUT:-25}"
DMO_TEND="${DMO_TEND:-3.0}"
# When DMO_NO_DEFAULT_CAPS=1 (debug-cosmo), do not inject nstepmax/foutput/tend;
# keep the staged namelist OUTPUT_PARAMS / RUN_PARAMS unchanged (e.g. aout-only).
DMO_NO_DEFAULT_CAPS="${DMO_NO_DEFAULT_CAPS:-0}"
GPU_HYDRO="${GPU_HYDRO:-0}"
GPU_MHD="${GPU_MHD:-0}"
GPU_TURB="${GPU_TURB:-0}"
if [[ -z "${BIN_GPU:-}" ]]; then
  if [[ "${GPU_MHD}" == "1" ]]; then
    BIN_GPU="${MINIRAM}/bin/ramses3d.mhd"
  elif [[ "${GPU_HYDRO}" == "1" ]]; then
    BIN_GPU="${MINIRAM}/bin/ramses3d.hydro"
  else
    BIN_GPU="${MINIRAM}/bin/ramses3d"
  fi
fi
BUILD_BINARIES="${BUILD_BINARIES:-1}"
DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-0}"
if [[ "${PROFILE}" == "sanitize" && -z "${GPU_DEBUG+x}" ]]; then
  GPU_DEBUG=1
fi
export GPU_DEBUG="${GPU_DEBUG:-0}"

case_name="$(basename "${NML}" .nml)"
workdir="${RUN_DIR}/dmo_gpu_${SLURM_JOB_ID:-manual}/${case_name}"
mkdir -p "${workdir}"
cd "${workdir}"

echo "== dmo_gpu job ${SLURM_JOB_ID:-manual} PROFILE=${PROFILE} case=${case_name}"
echo "   harness=${HARNESS_DIR} miniram=${MINIRAM}"
echo "   workdir=${workdir}"
echo "   build=${BUILD_BINARIES} gpu_hydro=${GPU_HYDRO} gpu_mhd=${GPU_MHD} gpu_turb=${GPU_TURB} gpu_npre=${GPU_NPRE:-4} gpu_fastmath=${GPU_FASTMATH:-0} gpu_debug=${GPU_DEBUG} bin=${BIN_GPU}"
if grep -qE "filetype=['\"]grafic_zoom['\"]" "${NML}"; then
  echo "   ic_zoom=${IC_ZOOM_DIR:-${HARNESS_DIR}/ics_zoom}"
else
  echo "   ic=${IC_DIR}"
fi

hackathon_load_modules || exit 2
# trace traps show as SIGILL before run.log; cosmo debug needs clean startup.
unset NVCOMPILER_TERM
if [[ "${GPU_TURB}" == "1" ]]; then
  hackathon_load_fftw || exit 2
  export FFTW FFTW_VENDOR_INC FFTW_HEADER_DIR
  echo "== dmo_gpu TURB build: FFTW=${FFTW}${FFTW_VENDOR_INC:+ FFTW_VENDOR_INC=${FFTW_VENDOR_INC}}${FFTW_HEADER_DIR:+ FFTW_HEADER_DIR=${FFTW_HEADER_DIR}}"
fi
nvidia-smi || true

NSYS_BIN="${NSYS_BIN:-$(command -v nsys || true)}"
NCU_BIN="${NCU_BIN:-$(command -v ncu || true)}"
for candidate in \
    "/opt/nvidia/hpc_sdk/Linux_x86_64/25.5/compilers/bin/nsys" \
    "/opt/nvidia/hpc_sdk/Linux_x86_64/25.5/compilers/bin/ncu"; do
  [[ -x "${candidate}" && -z "${NSYS_BIN}" && "${candidate}" == *nsys ]] && NSYS_BIN="${candidate}"
  [[ -x "${candidate}" && -z "${NCU_BIN}" && "${candidate}" == *ncu ]] && NCU_BIN="${candidate}"
done
COMPUTE_SANITIZER_BIN="${COMPUTE_SANITIZER_BIN:-$(command -v compute-sanitizer || true)}"
for candidate in \
    "${NVHPC_CUDA_HOME:-}/bin/compute-sanitizer" \
    "/usr/local/cuda/bin/compute-sanitizer" \
    "/opt/nvidia/hpc_sdk/Linux_x86_64/25.5/cuda/bin/compute-sanitizer"; do
  [[ -x "${candidate}" && -z "${COMPUTE_SANITIZER_BIN}" ]] && COMPUTE_SANITIZER_BIN="${candidate}"
done

if [[ "${BUILD_BINARIES}" -eq 1 ]]; then
  hackathon_build_binary "${workdir}/build.log"
else
  echo "== skipping build (BUILD_BINARIES=0)"
fi

if [[ ! -e "${BIN_GPU}" ]]; then
  echo "ERROR: missing GPU binary: ${BIN_GPU}" >&2
  exit 2
fi
if [[ ! -e "${NML}" ]]; then
  echo "ERROR: missing namelist: ${NML}" >&2
  exit 2
fi

# Stage namelist; rewrite initfile paths and any optional caps.
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
  elif [[ "${key}" == "foutput" || "${key}" == "tend" || "${key}" == "aend" || "${key}" == "delta_tout" ]]; then
    sed -i.bak -E "/^[[:space:]]*&OUTPUT_PARAMS/a ${key}=${val}" "${file}"
    rm -f "${file}.bak"
  fi
}
if [[ "${DMO_NO_DEFAULT_CAPS}" == "1" ]]; then
  :
else
  apply_kv nstepmax "${DMO_NSTEPMAX}" "${run_nml}"
  apply_kv foutput  "${DMO_FOUTPUT}"  "${run_nml}"
  apply_kv tend     "${DMO_TEND}"     "${run_nml}"
fi
[[ -n "${DMO_DELTA_TOUT:-}" ]] && apply_kv delta_tout "${DMO_DELTA_TOUT}" "${run_nml}"
[[ -n "${DMO_NCACHEMAX:-}" ]] && apply_kv ncachemax "${DMO_NCACHEMAX}" "${run_nml}"
[[ -n "${DMO_AEND:-}" ]] && apply_kv aend "${DMO_AEND}" "${run_nml}"
[[ -n "${DMO_GPU_CIC_FAST_PATH:-}" ]] && apply_kv gpu_cic_fast_path "${DMO_GPU_CIC_FAST_PATH}" "${run_nml}"
hackathon_apply_part_dep_algo "${run_nml}"

echo "== namelist: ${run_nml}"
grep -E 'nstepmax|foutput|tend|delta_tout|aend|delta_aout|initfile|cosmo|levelmin|levelmax|ngridmax|ncachemax|npartmax|m_refine|gpu_cic_fast_path|part_dep_algo' "${run_nml}" || true

run_log="${workdir}/run.log"
trace_base="${workdir}/${case_name}"

if [[ "${DMO_GPU_LAUNCH_BLOCKING}" == "1" ]]; then
  export CUDA_LAUNCH_BLOCKING=1
  echo "== CUDA_LAUNCH_BLOCKING=1"
fi

case "${PROFILE}" in
  nsys)
    if [[ -z "${NSYS_BIN}" || ! -x "${NSYS_BIN}" ]]; then
      echo "WARNING: nsys not found; falling back to plain run." >&2
      "${BIN_GPU}" input.nml 2>&1 | tee "${run_log}"
    else
      echo "== nsys profile -> ${trace_base}.nsys-rep"
      "${NSYS_BIN}" profile --trace=cuda,nvtx,osrt \
        --sample=none --cpuctxsw=none \
        --output="${trace_base}" --force-overwrite=true \
        "${BIN_GPU}" input.nml 2>&1 | tee "${run_log}"
      hackathon_export_nsys_stats "${trace_base}.nsys-rep" "${workdir}/profile_exports"
    fi
    ;;
  run)
    echo "== plain run (no profiler)"
    "${BIN_GPU}" input.nml 2>&1 | tee "${run_log}"
    ;;
  ncu)
    if [[ -z "${NCU_BIN}" || ! -x "${NCU_BIN}" ]]; then
      echo "ERROR: ncu not found; set NCU_BIN" >&2
      exit 2
    fi
    if [[ -z "${NCU_KERNEL}" ]]; then
      echo "ERROR: PROFILE=ncu requires NCU_KERNEL (e.g. regex:.*mhd_integrator_kernel.*)" >&2
      exit 2
    fi
    ncu_out="${workdir}/ncu_${case_name}"
    echo "== ncu kernel=${NCU_KERNEL} skip=${NCU_LAUNCH_SKIP} count=${NCU_LAUNCH_COUNT} set=${NCU_SET}"
    echo "== ncu profile -> ${ncu_out}.ncu-rep"
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
      --kernel-name "${NCU_KERNEL}"
    )
    hackathon_ncu_append_capture_source_args ncu_args "${workdir}"
    # Metric capture only (--set full). Source page is exported post-capture from
    # the .ncu-rep; do not pass --page source here (conflicts with --set and
    # duplicated --kernel-name-base when combined with source-page helpers).
    if ! "${NCU_BIN}" "${ncu_args[@]}" \
      "${BIN_GPU}" input.nml 2>&1 | tee "${run_log}"; then
      echo "ERROR: ncu exited non-zero (see ${run_log})" >&2
      grep -iE 'error|warn|no kernel|no metric' "${run_log}" | tail -20 >&2 || true
      exit 2
    fi
    if [[ ! -f "${ncu_out}.ncu-rep" ]]; then
      echo "ERROR: expected NCU report not found: ${ncu_out}.ncu-rep" >&2
      echo "       Common causes: kernel filter matched nothing (try NCU_KERNEL='regex:.*mhd_integrator_kernel.*', NCU_LAUNCH_SKIP=0)" >&2
      grep -iE 'error|warn|no kernel|no metric|profiled' "${run_log}" | tail -30 >&2 || true
      exit 2
    fi
    echo "== NCU report: ${ncu_out}.ncu-rep ($(du -h "${ncu_out}.ncu-rep" | cut -f1))"
    hackathon_ncu_export_source_artifacts \
      "${ncu_out}.ncu-rep" "${workdir}/profile_exports" "${case_name}" \
      "${NCU_BIN}" "${workdir}" || true
    ;;
  sanitize)
    if [[ -z "${COMPUTE_SANITIZER_BIN}" || ! -x "${COMPUTE_SANITIZER_BIN}" ]]; then
      echo "ERROR: compute-sanitizer not found; set COMPUTE_SANITIZER_BIN" >&2
      exit 2
    fi
    export CUDA_LAUNCH_BLOCKING="${CUDA_LAUNCH_BLOCKING:-1}"
    echo "== compute-sanitizer memcheck -> ${run_log}"
    echo "== CUDA_LAUNCH_BLOCKING=${CUDA_LAUNCH_BLOCKING}"
    "${COMPUTE_SANITIZER_BIN}" --tool memcheck --leak-check no \
      --target-processes all --error-exitcode 86 \
      "${BIN_GPU}" input.nml 2>&1 | tee "${run_log}"
    ;;
  *)
    echo "ERROR: unknown PROFILE=${PROFILE} (use run|nsys|ncu|sanitize)" >&2
    exit 2
    ;;
esac

if [[ "${PROFILE}" != "ncu" ]] && ! compgen -G "${workdir}/output_*" >/dev/null; then
  echo "ERROR: no output_NNNNN/ directories produced in ${workdir}" >&2
  exit 4
fi

echo "== done. Outputs in ${workdir}"
ls -d "${workdir}"/output_* 2>/dev/null | sort
