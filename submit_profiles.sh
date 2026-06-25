#!/usr/bin/env bash
# Multi-cluster hackathon launcher. Set CLUSTER=stellar|marlowe|sherlock (or in ~/.bashrc).
#
# Usage (from $HARNESS_DIR on cluster scratch):
#   export CLUSTER=stellar
#   ./submit_profiles.sh test
#   ./submit_profiles.sh test-amr-long # AMR-only long run (250 steps)
#   ./submit_profiles.sh nsys-l7      # nsys timeline, level-7 (builds + profiles)
#   ./submit_profiles.sh ncu          # ncu on kick_drift_part_kernel + cic_part_medium_kernel (2-step nml)
#   ./submit_profiles.sh ncu-cic      # alias for ncu
#   ./submit_profiles.sh ncu-cic-localize  # ncu-cic + lineinfo + --import-source + source-page export
#   ./submit_profiles.sh nsys-amr     # nsys on AMR case (sparsity contrast)
#   ./submit_profiles.sh dmo-cpu      # cosmological DMO (dmo.nml), CPU MPI
#   ./submit_profiles.sh dmo-gpu      # cosmological DMO (dmo.nml), GPU
#   ./submit_profiles.sh cosmo-gpu    # cosmological DM+gas (cosmo.nml), GPU HYDRO=1
#   ./submit_profiles.sh debug-cosmo  # cosmo debug (Makefile.debug-cosmo, NPRE=8)
#   ./submit_profiles.sh debug-cosmo-cpu-unigrid  # 96-rank CPU unigrid parity smoke
#   ./submit_profiles.sh cosmo-zoom   # cosmological zoom DM+gas (cosmo_zoom.nml), GPU HYDRO=1
#   ./submit_profiles.sh brio-wu      # 3D Brio-Wu MHD shock tube (brio_wu.nml), GPU MHD=1 HLLD, 128^3 unigrid
#   ./submit_profiles.sh abc          # ABC-flow resistive MHD (abc.nml), INIT=ABC, 128^3, etamag=0.001
#   ./submit_profiles.sh pono         # Ponomarenko resistive MHD AMR (pono.nml), INIT=PONO, L5->L8
#   ./submit_profiles.sh mhd-turb     # 3D driven MHD turbulence (mhd_turb.nml), GPU MHD=1 TURB=1 HLLD, 64^3 unigrid, uniform IC Bz=4
#   ./submit_profiles.sh orszag-tang      # 3D Orszag-Tang MHD vortex (orszag_tang.nml), GPU MHD=1 HLLD, 256^3 unigrid (z-symmetry)
#   ./submit_profiles.sh ot-amr           # Orszag-Tang MHD AMR (orszag_tang_amr.nml), 32^3 base L5->L8, err_grad_p=0.15
#   ./submit_profiles.sh ot-pscal         # ot-amr + one passive scalar (checkerboard ic_pvar_00001), NPSCAL=1
#   ./submit_profiles.sh nsys-ot          # nsys profile of Orszag-Tang MHD vortex (128^3, NPRE=8, 5 timesteps)
#   ./submit_profiles.sh nsys-dust        # nsys: 256^3 decaying MHD turb + dust, 1 grain/cell, 10 steps
#   ./submit_profiles.sh nsys-dust-12     # nsys: same with 12 grains/cell
#   ./submit_profiles.sh nsys-dust-64     # nsys: same with 64 grains/cell
#   ./submit_profiles.sh ncu-dust-12      # ncu kick_drift_dust_kernel, 12 grains/cell (GPU_DUST_COOP_KICK=0|1)
#   ./submit_profiles.sh ncu-dust-64      # ncu kick_drift_dust_kernel, 64 grains/cell (coop sharing regime)
#   ./submit_profiles.sh ncu-dust-12-pair # ncu A/B scalar vs coop kick-drift (2 sequential jobs)
#   ./submit_profiles.sh nsys-oth         # same as nsys-ot but MHD=0 (hydro-only speed comparison)
#   ./submit_profiles.sh ncu-ot           # ncu profile of hydro_integrator_kernel (Orszag-Tang, 2 steps)
#   ./submit_profiles.sh ncu-ot-localize  # ncu-ot + lineinfo + --import-source + source-page export (128^3 default)
#   ./submit_profiles.sh ot-cpu           # Orszag-Tang MHD AMR CPU (orszag_tang_amr.nml), L5->L10, NPRE=8, 24h
#   ./submit_profiles.sh orszag-tang-cpu  # unigrid Orszag-Tang on CPU MPI (pu, 96 ranks, pre-built ramses3d.mhd.cpu)
#   ./submit_profiles.sh cosmo-gpu-sanitize  # cosmo-gpu under compute-sanitizer + lineinfo
#   ./submit_profiles.sh dmo-gpu-block     # dmo-gpu with CUDA_LAUNCH_BLOCKING=1
#   ./submit_profiles.sh dmo-gpu-sanitize  # dmo-gpu under compute-sanitizer memcheck
#   ./submit_profiles.sh dmo-gpu-nsys20    # nsys profile of dmo.nml for 20 steps
#   ./submit_profiles.sh dmo-gpu-cic-slow  # CIC slow path only (dmo_cic_slow.nml)
#   ./submit_profiles.sh export TRACE.nsys-rep   # text stats only (login node)
#
# GPU particle deposition (&POISSON_PARAMS part_dep_algo in ~/mini-ramses-dev):
#   PART_DEP_ALGO=3 ./submit_profiles.sh test    # 1=large, 2=medium, 3=small CIC
# GPU builds default NPRE=4 (single precision) and FASTMATH=0; override via GPU_NPRE / GPU_FASTMATH.
# Propagates via hackathon_sbatch (--export=ALL when set).

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
HARNESS="$(pwd)"
export HARNESS_DIR="${HARNESS}"
# shellcheck source=bin/hackathon-env.sh
source "${HARNESS}/bin/hackathon-env.sh"

if [[ -n "${PART_DEP_ALGO:-}" ]]; then
  export PART_DEP_ALGO
  echo "== PART_DEP_ALGO=${PART_DEP_ALGO} (will patch part_dep_algo in staged namelists)"
fi

export GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}"
echo "== GPU_KICK_COOP_GATHER=${GPU_KICK_COOP_GATHER} (warp-cooperative kick gather)"

export GPU_KICK_COOP_VALIDATE="${GPU_KICK_COOP_VALIDATE:-0}"
echo "== GPU_KICK_COOP_VALIDATE=${GPU_KICK_COOP_VALIDATE} (in-kernel coop-vs-scalar exact A/B; needs GPU_KICK_COOP_GATHER=1)"

export GPU_DUST_COOP_KICK="${GPU_DUST_COOP_KICK:-0}"
echo "== GPU_DUST_COOP_KICK=${GPU_DUST_COOP_KICK} (warp-cooperative charged-dust hydro/B kick gather)"

export GPU_NPRE="${GPU_NPRE:-4}"
export GPU_FASTMATH="${GPU_FASTMATH:-0}"
echo "== GPU_NPRE=${GPU_NPRE} GPU_FASTMATH=${GPU_FASTMATH} (test defaults: single precision, no fastmath)"

cmd="${1:-help}"
shift || true

hackathon_submit_ncu() {
  local kernel="$1"
  local build_binaries="${2:-0}"
  local dep="${3:-}"   # optional extra sbatch arg, e.g. --dependency=afterok:JOBID
  local ncu_tag="${4:-}"  # optional NCU report basename (ncu_${tag}.ncu-rep)
  NCU_CASE_TAG="${ncu_tag}" \
  BUILD_BINARIES="${build_binaries}" PROFILE=ncu GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER}" \
    PART_DEP_ALGO="${PART_DEP_ALGO:-2}" \
    NML="$(hackathon_nml dm_pic_poisson_l7_ncu.nml)" \
    NCU_KERNEL="${kernel}" \
    NCU_LAUNCH_SKIP=0 \
    NCU_LAUNCH_COUNT=5 \
    NCU_SET=full \
    hackathon_sbatch --parsable ${dep:+"${dep}"} profile_gpu_dmo.slurm
}

# Two-job NCU CIC path: kick_drift builds once, cic_part_medium depends on it.
hackathon_submit_ncu_cic_pair() {
  local localize="${1:-0}"
  profile_run_dir="${RUN_DIR:-${HARNESS}}"
  ncu_case='dm_pic_poisson_l7_ncu'
  # Build once in the kick job (arm set by GPU_KICK_COOP_GATHER, default 0 =
  # scalar; export GPU_KICK_COOP_GATHER=1 for the coop arm), then profile kick drift
  # and the medium-stencil CIC deposit (part_dep_algo=2 -> cic_part_medium_kernel).
  export PART_DEP_ALGO="${PART_DEP_ALGO:-2}"
  job_kd="$(hackathon_submit_ncu 'regex:.*kick_drift_part_kernel.*' 1 '' kick_drift)"
  job_medium="$(hackathon_submit_ncu 'regex:.*cic_part_medium_kernel.*' 0 "--dependency=afterok:${job_kd}" cic_part_medium)"
  echo "Submitted NCU profile jobs ${job_kd} (kick_drift_part_kernel, builds COOP_GATHER=${GPU_KICK_COOP_GATHER}), ${job_medium} (cic_part_medium_kernel, reuses)"
  echo "When they finish, reports should be at:"
  echo "  ${profile_run_dir}/profiles_${job_kd}/${ncu_case}/ncu_kick_drift.ncu-rep"
  echo "  ${profile_run_dir}/profiles_${job_medium}/${ncu_case}/ncu_cic_part_medium.ncu-rep"
  if [[ "${localize}" == "1" ]]; then
    echo "Source localization exports (both NCU jobs, after profile_gpu_dmo_a100 NCU_EXPORT_SOURCE hook):"
    echo "  ${profile_run_dir}/profiles_${job_kd}/${ncu_case}/profile_exports/ncu_${ncu_case}_source.csv"
    echo "  ${profile_run_dir}/profiles_${job_kd}/${ncu_case}/profile_exports/ncu_${ncu_case}_source_sass.txt"
    echo "  ${profile_run_dir}/profiles_${job_kd}/${ncu_case}/profile_exports/ncu_${ncu_case}_source_counters.txt"
    echo "  ${profile_run_dir}/profiles_${job_medium}/${ncu_case}/profile_exports/ncu_${ncu_case}_source.csv"
    echo "  ${profile_run_dir}/profiles_${job_medium}/${ncu_case}/profile_exports/ncu_${ncu_case}_source_sass.txt"
    echo "  ${profile_run_dir}/profiles_${job_medium}/${ncu_case}/profile_exports/ncu_${ncu_case}_source_counters.txt"
  fi
  echo "(RUN_DIR=${profile_run_dir}; override with RUN_DIR=... if your jobs write elsewhere)"
  echo "Job logs: ${HARNESS}/gpu_dmo_profile_${job_kd}.out ${HARNESS}/gpu_dmo_profile_${job_medium}.out"
}

# Orszag-Tang NCU profile of hydro_integrator_kernel (dmo_gpu.slurm).
hackathon_submit_ncu_ot() {
  local localize="${1:-0}"
  local ot_level ot_nml ot_case profile_run_dir job_id
  if [[ "${localize}" == "1" ]]; then
    ot_level="${ORSZAG_TANG_LEVEL:-7}"
    : "${BUILD_BINARIES:=1}"
    echo "== ncu-ot-localize: level=${ot_level} ($((2**ot_level))^3) GPU_LINEINFO=1 NCU_IMPORT_SOURCE=yes NCU_EXPORT_SOURCE=1 BUILD_BINARIES=${BUILD_BINARIES}"
  else
    ot_level="${ORSZAG_TANG_LEVEL:-8}"
  fi
  hackathon_ensure_orszag_tang_ics "${ot_level}"
  ot_nml="$(hackathon_nml orszag_tang.nml)"
  ot_case="$(basename "${ot_nml}" .nml)"
  if [[ "${ot_level}" != "8" ]]; then
    ot_nml="${HARNESS}/orszag_tang_l${ot_level}.nml"
    ot_case="$(basename "${ot_nml}" .nml)"
    sed -E "s/^[[:space:]]*levelmin=.*/ levelmin=${ot_level}/; s/^[[:space:]]*levelmax=.*/ levelmax=${ot_level}/" \
      "$(hackathon_nml orszag_tang.nml)" > "${ot_nml}"
  fi
  export GPU_HYDRO=1
  export GPU_MHD=1
  export GPU_NPSCAL="${GPU_NPSCAL:-0}"
  export GPU_GRAV=0
  export GPU_UNITS=
  export GPU_FASTMATH="${GPU_FASTMATH:-0}"
  export IC_DIR
  export DMO_TEND="${DMO_TEND:-0.5}"
  export DMO_FOUTPUT="${DMO_FOUTPUT:-2}"
  export DMO_NSTEPMAX="${DMO_NSTEPMAX:-2}"
  echo "== ncu-ot: level=${ot_level} ($((2**ot_level))^3 unigrid) kernel=hydro_integrator_kernel nstepmax=${DMO_NSTEPMAX} NVAR=$((5+GPU_NPSCAL)) NPRE=${GPU_NPRE}"
  echo "           IC_DIR=${IC_DIR} NML=${ot_nml} BUILD_BINARIES=${BUILD_BINARIES:-1} wall=${DMO_SLURM_TIME:-02:00:00}"
  job_id="$(
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_LINEINFO="${GPU_LINEINFO:-0}" \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd}" \
    NML="${ot_nml}" PROFILE=ncu \
    NCU_KERNEL="${NCU_KERNEL:-regex:.*hydro_integrator_kernel.*}" \
    NCU_LAUNCH_SKIP="${NCU_LAUNCH_SKIP:-0}" \
    NCU_LAUNCH_COUNT="${NCU_LAUNCH_COUNT:-5}" \
    NCU_SET="${NCU_SET:-full}" \
    NCU_IMPORT_SOURCE="${NCU_IMPORT_SOURCE:-no}" \
    NCU_EXPORT_SOURCE="${NCU_EXPORT_SOURCE:-0}" \
    NCU_DEFAULT_SOURCE="${NCU_DEFAULT_SOURCE:-}" \
    NCU_SOURCE_FOLDERS="${NCU_SOURCE_FOLDERS:-}" \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-0}" \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
      hackathon_sbatch --parsable --time="${DMO_SLURM_TIME:-02:00:00}" dmo_gpu.slurm
  )"
  profile_run_dir="${RUN_DIR:-${HARNESS}}"
  echo "Submitted NCU profile job ${job_id} (hydro_integrator_kernel)"
  echo "When it finishes, the report should be at:"
  echo "  ${profile_run_dir}/dmo_gpu_${job_id}/${ot_case}/ncu_${ot_case}.ncu-rep"
  if [[ "${localize}" == "1" ]]; then
    echo "Source localization exports (dmo_gpu NCU_EXPORT_SOURCE hook):"
    echo "  ${profile_run_dir}/dmo_gpu_${job_id}/${ot_case}/profile_exports/ncu_${ot_case}_source.csv"
    echo "  ${profile_run_dir}/dmo_gpu_${job_id}/${ot_case}/profile_exports/ncu_${ot_case}_source_sass.txt"
    echo "  ${profile_run_dir}/dmo_gpu_${job_id}/${ot_case}/profile_exports/ncu_${ot_case}_source_counters.txt"
  fi
  echo "(RUN_DIR=${profile_run_dir}; on Stellar this is often /scratch/gpfs/\$USER/hackathon, not ~/hackathon)"
  echo "Job log: ${HARNESS}/dmo_gpu_${job_id}.out"
  echo "Validate source before optimizing: ./validate_ncu_source.sh ${profile_run_dir}/dmo_gpu_${job_id}/${ot_case}/ncu_${ot_case}.ncu-rep ${profile_run_dir}/dmo_gpu_${job_id}/${ot_case}"
}

# NCU profile of kick_drift_dust_kernel on mhd_turb_dust_l8 (decaying MHD turb + dust).
# Returns job id on stdout (for ncu-dust-12-pair dependency wiring).
hackathon_submit_ncu_dust() {
  local dust_ppc="$1"
  local coop_kick="$2"
  local build_binaries="${3:-1}"
  local dep="${4:-${NCU_DUST_DEP:-}}"
  local mt_nml profile_run_dir job_id arm_label mt_case slurm_mem slurm_time dust_level

  export MINIRAM_EXPECTED_BRANCH="${MINIRAM_EXPECTED_BRANCH:-gpu_dust}"
  export MHD_TURB_DUST=1
  # L8 64 ppc (~1.07B grains) OOMs on 40GB A100; L7 128^3 keeps 64 ppc with fewer
  # total grains than L8 12 ppc. Override with MHD_TURB_DUST_LEVEL=8 if you have 80GB+.
  if [[ -n "${MHD_TURB_DUST_LEVEL:-}" ]]; then
    dust_level="${MHD_TURB_DUST_LEVEL}"
  elif (( dust_ppc >= 64 )); then
    dust_level=7
  else
    dust_level=8
  fi
  hackathon_ensure_mhd_turb_decay_ics "${dust_level}" >&2
  if [[ "${dust_level}" == "8" ]]; then
    mt_nml="$(hackathon_nml mhd_turb_dust_l8.nml)"
  else
    mt_nml="${HARNESS}/namelists/mhd_turb_dust_l${dust_level}.nml"
    sed -E \
      "s/^[[:space:]]*levelmin=.*/ levelmin=${dust_level}/; s/^[[:space:]]*levelmax=.*/ levelmax=${dust_level}/" \
      "$(hackathon_nml mhd_turb_dust_l8.nml)" > "${mt_nml}"
  fi
  mt_case="$(basename "${mt_nml}" .nml)"
  export GPU_HYDRO=1 GPU_MHD=1 GPU_TURB=0 GPU_NPSCAL="${GPU_NPSCAL:-0}" GPU_GRAV=0 GPU_UNITS=
  export GPU_FASTMATH="${GPU_FASTMATH:-0}"
  export GPU_NPRE="${GPU_NPRE:-4}"
  export GPU_ALWAYS_KIND8_POS="${GPU_ALWAYS_KIND8_POS:-1}"
  export GPU_DUST_COOP_KICK="${coop_kick}"
  export IC_DIR
  export DMO_TEND="${DMO_TEND:-0.5}"
  export DMO_FOUTPUT="${DMO_FOUTPUT:-1000000}"
  export DMO_NSTEPMAX="${DMO_NSTEPMAX:-3}"
  export DMO_NDUST_PER_CELL="${DMO_NDUST_PER_CELL:-${dust_ppc}}"
  arm_label="scalar"
  [[ "${coop_kick}" == "1" ]] && arm_label="coop"
  if (( dust_ppc >= 64 )); then
    slurm_mem="${DMO_SLURM_MEM:-120G}"
    slurm_time="${DMO_SLURM_TIME:-08:00:00}"
  else
    slurm_mem="${DMO_SLURM_MEM:-80G}"
    slurm_time="${DMO_SLURM_TIME:-04:00:00}"
  fi
  echo "== ncu-dust-${dust_ppc} (${arm_label}): kick_drift_dust_kernel level=${dust_level} ($((2**dust_level))^3) nstepmax=${DMO_NSTEPMAX} ppc=${DMO_NDUST_PER_CELL} DUST_COOP_KICK=${coop_kick} NPRE=${GPU_NPRE}" >&2
  if [[ -n "${DMO_NRESTART:-}" ]]; then
    echo "           restart nrestart=${DMO_NRESTART} backup=${DMO_RESTART_BACKUP_DIR:-<unset>} nstep_add=${DMO_NSTEP_ADD:-<unset>}" >&2
  fi
  echo "           NML=${mt_nml} IC_DIR=${IC_DIR} BUILD_BINARIES=${build_binaries} wall=${slurm_time} mem=${slurm_mem}" >&2
  job_id="$(
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_LINEINFO="${GPU_LINEINFO:-0}" \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    GPU_DUST_COOP_KICK="${coop_kick}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd.dust}" \
    NML="${mt_nml}" PROFILE=ncu \
    NCU_KERNEL="${NCU_KERNEL:-regex:.*kick_drift_dust_kernel.*}" \
    NCU_LAUNCH_SKIP="${NCU_LAUNCH_SKIP:-1}" \
    NCU_LAUNCH_COUNT="${NCU_LAUNCH_COUNT:-5}" \
    NCU_SET="${NCU_SET:-full}" \
    NCU_IMPORT_SOURCE="${NCU_IMPORT_SOURCE:-no}" \
    NCU_EXPORT_SOURCE="${NCU_EXPORT_SOURCE:-0}" \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-0}" \
    BUILD_BINARIES="${build_binaries}" \
      hackathon_sbatch --parsable ${dep:+"${dep}"} --time="${slurm_time}" --mem="${slurm_mem}" dmo_gpu.slurm
  )"
  profile_run_dir="${RUN_DIR:-${HARNESS}}"
  echo "Submitted NCU dust job ${job_id} (${arm_label}, kick_drift_dust_kernel)" >&2
  echo "  ${profile_run_dir}/dmo_gpu_${job_id}/${mt_case}/ncu_${mt_case}.ncu-rep" >&2
  echo "  log: ${HARNESS}/dmo_gpu_${job_id}.out" >&2
  echo "Export raw CSV: ncu --import ${profile_run_dir}/dmo_gpu_${job_id}/${mt_case}/ncu_${mt_case}.ncu-rep --csv --page raw > ncu_dust_${arm_label}_raw.csv" >&2
  printf '%s\n' "${job_id}"
}

# Plain GPU run: Orszag-Tang vortex + dust (orszag_tang_dust.nml). Returns job id.
hackathon_submit_ot_dust() {
  local dust_ppc="$1"
  local coop_kick="$2"
  local build_binaries="${3:-1}"
  local dep="${4:-}"
  local ot_level ot_nml job_id arm_label slurm_mem slurm_time

  export MINIRAM_EXPECTED_BRANCH="${MINIRAM_EXPECTED_BRANCH:-gpu_dust}"
  export ORSZAG_TANG_DUST=1
  ot_level="${ORSZAG_TANG_LEVEL:-8}"
  hackathon_ensure_orszag_tang_ics "${ot_level}" >&2
  if [[ "${ot_level}" == "8" ]]; then
    ot_nml="$(hackathon_nml orszag_tang_dust.nml)"
  else
    ot_nml="${HARNESS}/namelists/orszag_tang_dust_l${ot_level}.nml"
    sed -E \
      "s/^[[:space:]]*levelmin=.*/ levelmin=${ot_level}/; s/^[[:space:]]*levelmax=.*/ levelmax=${ot_level}/" \
      "$(hackathon_nml orszag_tang_dust.nml)" > "${ot_nml}"
  fi
  export GPU_HYDRO=1 GPU_MHD=1 GPU_TURB=0 GPU_NPSCAL="${GPU_NPSCAL:-0}" GPU_GRAV=0 GPU_UNITS=
  export GPU_FASTMATH="${GPU_FASTMATH:-0}"
  export GPU_NPRE="${GPU_NPRE:-4}"
  export GPU_ALWAYS_KIND8_POS="${GPU_ALWAYS_KIND8_POS:-1}"
  export GPU_DUST_COOP_KICK="${coop_kick}"
  export IC_DIR
  export DMO_TEND="${DMO_TEND:-0.5}"
  export DMO_FOUTPUT="${DMO_FOUTPUT:-1000000}"
  export DMO_NSTEPMAX="${DMO_NSTEPMAX:-100000}"
  export DMO_NDUST_PER_CELL="${DMO_NDUST_PER_CELL:-${dust_ppc}}"
  arm_label="scalar"
  [[ "${coop_kick}" == "1" ]] && arm_label="coop"
  slurm_mem="${DMO_SLURM_MEM:-80G}"
  slurm_time="${DMO_SLURM_TIME:-04:00:00}"
  echo "== orszag-tang-dust (${arm_label}): level=${ot_level} ($((2**ot_level))^3) ppc=${DMO_NDUST_PER_CELL} DUST_COOP_KICK=${coop_kick} NPRE=${GPU_NPRE} tend=${DMO_TEND}" >&2
  echo "           NML=${ot_nml} IC_DIR=${IC_DIR} BUILD_BINARIES=${build_binaries} wall=${slurm_time} mem=${slurm_mem}" >&2
  job_id="$(
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    GPU_DUST_COOP_KICK="${coop_kick}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd.dust}" \
    NML="${ot_nml}" PROFILE=run \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-0}" \
    BUILD_BINARIES="${build_binaries}" \
      hackathon_sbatch --parsable ${dep:+"${dep}"} --time="${slurm_time}" --mem="${slurm_mem}" dmo_gpu.slurm
  )"
  echo "Submitted orszag-tang-dust job ${job_id} (${arm_label})" >&2
  echo "  log: ${HARNESS}/dmo_gpu_${job_id}.out" >&2
  printf '%s\n' "${job_id}"
}

# Plain GPU run: decaying MHD turb + dust (mhd_turb_dust_l8.nml). Returns job id.
hackathon_submit_mhd_turb_dust() {
  local dust_ppc="$1"
  local coop_kick="$2"
  local build_binaries="${3:-1}"
  local dep="${4:-}"
  local mt_nml job_id arm_label slurm_mem slurm_time

  export MINIRAM_EXPECTED_BRANCH="${MINIRAM_EXPECTED_BRANCH:-gpu_dust}"
  export MHD_TURB_DUST=1
  hackathon_ensure_mhd_turb_decay_ics 8 >&2
  mt_nml="$(hackathon_nml mhd_turb_dust_l8.nml)"
  export GPU_HYDRO=1 GPU_MHD=1 GPU_TURB=0 GPU_NPSCAL="${GPU_NPSCAL:-0}" GPU_GRAV=0 GPU_UNITS=
  export GPU_FASTMATH="${GPU_FASTMATH:-0}"
  export GPU_NPRE="${GPU_NPRE:-4}"
  export GPU_ALWAYS_KIND8_POS="${GPU_ALWAYS_KIND8_POS:-1}"
  export GPU_DUST_COOP_KICK="${coop_kick}"
  export IC_DIR
  export DMO_TEND="${DMO_TEND:-0.5}"
  export DMO_FOUTPUT="${DMO_FOUTPUT:-1000000}"
  export DMO_NSTEPMAX="${DMO_NSTEPMAX:-100000}"
  export DMO_NDUST_PER_CELL="${DMO_NDUST_PER_CELL:-${dust_ppc}}"
  arm_label="scalar"
  [[ "${coop_kick}" == "1" ]] && arm_label="coop"
  slurm_mem="${DMO_SLURM_MEM:-80G}"
  slurm_time="${DMO_SLURM_TIME:-06:00:00}"
  echo "== mhd-turb-dust (${arm_label}): 256^3 decay ppc=${DMO_NDUST_PER_CELL} Bz=${MHD_TURB_BZ:-4} vrms=${MHD_TURB_VRMS:-2.0} beta_plasma=${MHD_TURB_PLASMA_BETA:-n/a} grain_size=${MHD_TURB_GRAIN_SIZE:-0.1} charge=${MHD_TURB_GRAIN_CHARGE:-100} DUST_COOP_KICK=${coop_kick} NPRE=${GPU_NPRE}" >&2
  echo "           NML=${mt_nml} IC_DIR=${IC_DIR} BUILD_BINARIES=${build_binaries} wall=${slurm_time} mem=${slurm_mem}" >&2
  job_id="$(
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    GPU_DUST_COOP_KICK="${coop_kick}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd.dust}" \
    NML="${mt_nml}" PROFILE=run \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-0}" \
    BUILD_BINARIES="${build_binaries}" \
      hackathon_sbatch --parsable ${dep:+"${dep}"} --time="${slurm_time}" --mem="${slurm_mem}" dmo_gpu.slurm
  )"
  echo "Submitted mhd-turb-dust job ${job_id} (${arm_label})" >&2
  echo "  log: ${HARNESS}/dmo_gpu_${job_id}.out" >&2
  printf '%s\n' "${job_id}"
}

case "${cmd}" in
  test)
    GPU_NPRE="${GPU_NPRE:-4}" hackathon_sbatch test_gpu_dmo.slurm
    ;;
  test-amr-long)
    hackathon_sbatch test_gpu_dmo_amr_long.slurm
    ;;
  nsys-l7)
    BUILD_BINARIES=1 PROFILE=nsys GPU_NPRE="${GPU_NPRE:-4}" GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER}" \
      NML="$(hackathon_nml dm_pic_poisson_l7.nml)" \
      ${PART_DEP_ALGO:+PART_DEP_ALGO="${PART_DEP_ALGO}"} \
      hackathon_sbatch profile_gpu_dmo.slurm
    ;;
  ncu|ncu-cic)
    hackathon_submit_ncu_cic_pair 0
    ;;
  ncu-cic-localize)
    # Same two-job dependency as ncu-cic; job 1 rebuilds with -gpu=lineinfo @ -O4.
    export GPU_LINEINFO=1
    export NCU_IMPORT_SOURCE=yes
    export NCU_EXPORT_SOURCE=1
    export NCU_DEFAULT_SOURCE="${NCU_DEFAULT_SOURCE:-gpu_part.cuf}"
    : "${BUILD_BINARIES:=1}"
    echo "== ncu-cic-localize: GPU_LINEINFO=1 NCU_IMPORT_SOURCE=yes NCU_EXPORT_SOURCE=1 NCU_DEFAULT_SOURCE=${NCU_DEFAULT_SOURCE} BUILD_BINARIES=${BUILD_BINARIES}"
    hackathon_submit_ncu_cic_pair 1
    ;;
  nsys-amr)
    BUILD_BINARIES=0 PROFILE=nsys \
      NML="$(hackathon_nml dm_pic_poisson_l7_amr_l8.nml)" \
      PHYS_NSTEPMAX=10 PHYS_FOUTPUT=5 PHYS_TEND=0.2 \
      ${PART_DEP_ALGO:+PART_DEP_ALGO="${PART_DEP_ALGO}"} \
      hackathon_sbatch profile_gpu_dmo.slurm
    ;;
  dmo-cpu)
    # Run-only on pu (BUILD_BINARIES=0). Uses pre-built ${MINIRAM}/bin/ramses3d.cpu.
    export GCC_MODULE="${GCC_MODULE:-gcc-toolset/10}"
    export OPENMPI_MODULE="${OPENMPI_MODULE:-openmpi/gcc-toolset-10/4.1.0}"
    export OPENMPI_USE_MODULES="${OPENMPI_USE_MODULES:-1}"
    BIN_CPU="${BIN_CPU:-${MINIRAM}/bin/ramses3d.cpu}"
    if [[ "${BUILD_CPU:-0}" == "1" ]]; then
      hackathon_build_cpu_binary || exit 1
    else
      if [[ ! -x "${BIN_CPU}" ]]; then
        echo "ERROR: pre-built CPU binary not found: ${BIN_CPU}" >&2
        echo "       Build elsewhere and install ramses3d.cpu there, or BUILD_CPU=1 to compile on login." >&2
        exit 1
      fi
      echo "== using pre-built CPU binary: ${BIN_CPU}"
      ls -la "${BIN_CPU}"
    fi
    BUILD_BINARIES=0 \
    BIN_CPU="${BIN_CPU}" \
    NML="$(hackathon_nml dmo.nml)" \
      hackathon_sbatch ${DMO_SLURM_MEM:+--mem="${DMO_SLURM_MEM}"} dmo_cpu.slurm
    ;;
  dmo-gpu)
    # Cosmological DMO (dmo.nml); aend/delta_aout; plain run (no nsys).
    # Requires ${MINIRAM} on develop (CUB sort + NPRE=4 alignment fix).
    echo "== dmo-gpu: GPU_NPRE=${GPU_NPRE:-4} BUILD_BINARIES=${BUILD_BINARIES:-1} MINIRAM=${MINIRAM:-${HOME}/mini-ramses-dev}"
    GPU_NPRE="${GPU_NPRE:-4}" \
    GPU_CUDA_ARCH="${GPU_CUDA_ARCH:-}" \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
    NML="$(hackathon_nml dmo.nml)" PROFILE=run \
      ${PART_DEP_ALGO:+PART_DEP_ALGO="${PART_DEP_ALGO}"} \
      hackathon_sbatch dmo_gpu.slurm
    ;;
  dmo-gpu-block)
    # Same case as dmo-gpu, but force synchronous CUDA errors so the log points
    # at the first failing kernel instead of a later host/device sync.
    NML="$(hackathon_nml dmo.nml)" PROFILE=run DMO_GPU_LAUNCH_BLOCKING=1 \
      ${PART_DEP_ALGO:+PART_DEP_ALGO="${PART_DEP_ALGO}"} \
      hackathon_sbatch dmo_gpu.slurm
    ;;
  dmo-gpu-sanitize)
    # Memcheck is slow, so default to enough steps to pass the observed step-24
    # failure while still allowing overrides from the submit environment. Build
    # with NVHPC debug/lineinfo flags unless GPU_DEBUG is explicitly provided.
    NML="$(hackathon_nml dmo.nml)" PROFILE=sanitize DMO_GPU_LAUNCH_BLOCKING=1 \
    GPU_DEBUG="${GPU_DEBUG:-1}" \
    DMO_NSTEPMAX="${DMO_NSTEPMAX:-40}" DMO_FOUTPUT="${DMO_FOUTPUT:-10}" \
      ${PART_DEP_ALGO:+PART_DEP_ALGO="${PART_DEP_ALGO}"} \
      hackathon_sbatch dmo_gpu.slurm
    ;;
  dmo-gpu-nsys20)
    # Nsight Systems profile of the cosmological DMO case, capped at 20 steps.
    NML="$(hackathon_nml dmo.nml)" PROFILE=nsys \
    DMO_NSTEPMAX="${DMO_NSTEPMAX:-20}" DMO_FOUTPUT="${DMO_FOUTPUT:-20}" \
      ${PART_DEP_ALGO:+PART_DEP_ALGO="${PART_DEP_ALGO}"} \
      hackathon_sbatch dmo_gpu.slurm
    ;;
  dmo-gpu-cic-slow)
    # Same DMO case with gpu_cic_fast_path=.false. (per-lane CIC only).
    # Rebuilds once so gpu_part.cuf picks up the namelist flag; no cpp toggles.
    # Default: 30 main steps for econs comparison vs dmo-cpu job 2794284.
    NML="$(hackathon_nml dmo_cic_slow.nml)" PROFILE=run \
    BUILD_BINARIES=1 \
    DMO_NSTEPMAX="${DMO_NSTEPMAX:-30}" DMO_FOUTPUT="${DMO_FOUTPUT:-30}" \
      ${PART_DEP_ALGO:+PART_DEP_ALGO="${PART_DEP_ALGO}"} \
      hackathon_sbatch dmo_gpu.slurm
    ;;
  cosmo-gpu)
    # Cosmological DM + isothermal gas (cosmo.nml). Builds HYDRO=1 into
    # ${MINIRAM}/bin/ramses3d.hydro (leaves ramses3d DMO binary untouched).
    # Uses cosmo.nml output caps: aend=1.0, delta_aout=0.1 (override: DMO_AEND=...).
    # Requires ${MINIRAM} on develop (CUB sort, part_dep_algo). Default NPRE=4.
    # Override: GPU_NPRE=8 ./submit_profiles.sh cosmo-gpu
    # CUDA_LAUNCH_BLOCKING defaults ON here so the multipole_upload diagnostic
    # prints flush in order and any residual fault is attributed to its kernel.
    # BUILD_BINARIES=1 (default) compiles the gpu_rho.cuf/gpu_runner.cuf guard;
    # make sure ${MINIRAM} on the cluster has those edits before submitting.
    echo "== cosmo-gpu: GPU_NPRE=${GPU_NPRE:-4} BUILD_BINARIES=${BUILD_BINARIES:-1} LAUNCH_BLOCKING=${DMO_GPU_LAUNCH_BLOCKING:-1}"
    # Optional step caps: export (not inline) so they reach the slurm env. A
    # ${VAR:+VAR=val} word is NOT parsed as an assignment, so when unset it
    # collapses and the next inline assignment (DMO_AEND=...) lands in command
    # position and bash runs it ("command not found"). Exporting avoids that.
    [[ -n "${DMO_NSTEPMAX:-}" ]] && export DMO_NSTEPMAX
    [[ -n "${DMO_FOUTPUT:-}" ]] && export DMO_FOUTPUT
    GPU_HYDRO=1 \
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_NPRE="${GPU_NPRE:-4}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.hydro}" \
    NML="$(hackathon_nml cosmo.nml)" PROFILE=run \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-1}" \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
      hackathon_sbatch dmo_gpu.slurm
    ;;
  debug-cosmo)
    # rteyssie develop cosmological debug: Makefile.debug-cosmo (harness copy of
    # Makefile.a100 with NPRE=8), not repo bin/Makefile. Isothermal HLLC nml.
    # Matches: make NDIM=3 COMPILER=NVHPC HYDRO=1 GRAV=1 UNITS=COSMO CUDA_ARCH=sm_80
    # ICs: Stellar scratch ics_ramses (not ~/hackathon/ics_ramses). Serial make only.
    # Requires nvhpc/25.5 (strict; no fallback to 21.1/generic nvhpc).
    echo "== debug-cosmo: Makefile.debug-cosmo serial NVHPC=${NVHPC_MODULE:-nvhpc/25.5} BUILD_BINARIES=${BUILD_BINARIES:-1}"
    export IC_DIR="${IC_DIR:-${HARNESS_DIR}/ics_ramses}"
    export NVHPC_MODULE=nvhpc/25.5
    export NVHPC_MODULE_STRICT=1
    export GPU_BUILD_MINIMAL=1
    export DMO_NO_DEFAULT_CAPS=1
    export GPU_HYDRO=1
    export GPU_GRAV=1
    export GPU_UNITS=COSMO
    export GPU_CUDA_ARCH="${GPU_CUDA_ARCH}"
    [[ -n "${DMO_NSTEPMAX:-}" ]] && export DMO_NSTEPMAX
    [[ -n "${DMO_FOUTPUT:-}" ]] && export DMO_FOUTPUT
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.hydro}" \
    NML="$(hackathon_nml debug_cosmo.nml)" PROFILE=run \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-0}" \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
      hackathon_sbatch --time="${DMO_SLURM_TIME:-06:00:00}" dmo_gpu.slurm
    ;;
  debug-cosmo-unigrid)
    # GPU unigrid L7 parity case (debug_cosmo_unigrid.nml, rteyssie caps).
    echo "== debug-cosmo-unigrid: Makefile.debug-cosmo NVHPC=${NVHPC_MODULE:-nvhpc/25.5}"
    export IC_DIR="${IC_DIR:-${HARNESS_DIR}/ics_ramses}"
    export NVHPC_MODULE=nvhpc/25.5
    export NVHPC_MODULE_STRICT=1
    export GPU_BUILD_MINIMAL=1
    export DMO_NO_DEFAULT_CAPS=1
    export GPU_HYDRO=1
    export GPU_GRAV=1
    export GPU_UNITS=COSMO
    export GPU_CUDA_ARCH="${GPU_CUDA_ARCH}"
    [[ -n "${DMO_NSTEPMAX:-}" ]] && export DMO_NSTEPMAX
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.hydro}" \
    NML="$(hackathon_nml debug_cosmo_unigrid.nml)" PROFILE=run \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-0}" \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
      hackathon_sbatch --time="${DMO_SLURM_TIME:-02:00:00}" dmo_gpu.slurm
    ;;
  debug-cosmo-cpu)
    # 96-rank MPI CPU baseline for debug-cosmo (HYDRO+GRAV+UNITS=COSMO, NPRE=8).
    # Full pu node via dmo_cpu.slurm. BUILD_CPU=1 builds on login before submit.
    export IC_DIR="${IC_DIR:-${HARNESS_DIR}/ics_ramses}"
    export CPU_HYDRO=1
    export CPU_GRAV=1
    export CPU_UNITS=COSMO
    export CPU_NPRE=8
    export DMO_NO_DEFAULT_CAPS=1
    export GCC_MODULE="${GCC_MODULE:-gcc-toolset/10}"
    export OPENMPI_MODULE="${OPENMPI_MODULE:-openmpi/gcc-toolset-10/4.1.0}"
    export OPENMPI_USE_MODULES="${OPENMPI_USE_MODULES:-1}"
    BIN_CPU="${BIN_CPU:-${MINIRAM}/bin/ramses3d.cpu}"
    cpu_nml="${DEBUG_COSMO_CPU_NML:-debug_cosmo_cpu.nml}"
    echo "== debug-cosmo-cpu: NML=${cpu_nml} BUILD_CPU=${BUILD_CPU:-1} NPRE=8"
    if [[ "${BUILD_CPU:-1}" == "1" ]]; then
      hackathon_build_cpu_binary || exit 1
    elif [[ ! -x "${BIN_CPU}" ]]; then
      echo "ERROR: pre-built CPU binary not found: ${BIN_CPU}" >&2
      echo "       BUILD_CPU=1 to compile on login." >&2
      exit 1
    fi
    BUILD_BINARIES=0 \
    BIN_CPU="${BIN_CPU}" \
    NML="$(hackathon_nml "${cpu_nml}")" \
      hackathon_sbatch ${DMO_SLURM_MEM:+--mem="${DMO_SLURM_MEM}"} \
        --time="${DMO_SLURM_TIME:-06:00:00}" dmo_cpu.slurm
    ;;
  debug-cosmo-cpu-unigrid)
    # CPU unigrid smoke: 50 main steps by default (override DMO_NSTEPMAX).
    export DMO_NSTEPMAX="${DMO_NSTEPMAX:-50}"
    DEBUG_COSMO_CPU_NML=debug_cosmo_unigrid_cpu.nml \
    DMO_SLURM_TIME="${DMO_SLURM_TIME:-02:00:00}" \
      "$0" debug-cosmo-cpu
    ;;
  cosmo-zoom)
    # Cosmological zoom-in DM + isothermal gas (cosmo_zoom.nml). Zoom ICs under
    # ${HARNESS}/ics_zoom (auto-download from tigress if level_007 is missing).
    # Defaults: NPRE=8, FASTMATH=1 (unlike other harness tests).
    hackathon_ensure_zoom_ics
    export GPU_NPRE=8
    export GPU_FASTMATH=1
    export GPU_HYDRO=1
    export IC_ZOOM_DIR
    [[ -n "${DMO_NSTEPMAX:-}" ]] && export DMO_NSTEPMAX
    [[ -n "${DMO_FOUTPUT:-}" ]] && export DMO_FOUTPUT
    echo "== cosmo-zoom: GPU_NPRE=${GPU_NPRE} GPU_FASTMATH=${GPU_FASTMATH} IC_ZOOM_DIR=${IC_ZOOM_DIR} BUILD_BINARIES=${BUILD_BINARIES:-1} LAUNCH_BLOCKING=${DMO_GPU_LAUNCH_BLOCKING:-1} wall=${DMO_SLURM_TIME:-12:00:00}"
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.hydro}" \
    NML="$(hackathon_nml cosmo_zoom.nml)" PROFILE=run \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-1}" \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
      hackathon_sbatch --time="${DMO_SLURM_TIME:-12:00:00}" dmo_gpu.slurm
    ;;
  brio-wu)
    # 3D Brio & Wu MHD shock tube on the GPU cube ("rock") integrator, HLLD by
    # default (riemann='hlld', riemann2d='hlld'). Default 128^3 unigrid, no AMR
    # (BRIO_WU_LEVEL=7 -> levelmin=levelmax=7). Periodic (GPU MHD is periodic-only).
    # ICs are checked under ${HARNESS}/ics_brio_wu and, if absent, generated on the
    # fly by mini-ramses-dev/utils/py/grafic/brio_wu.py (like cosmo-zoom ensures
    # its ICs). Builds ramses3d.mhd via bin/Makefile (serial), MHD=1 HYDRO=1,
    # NPSCAL=0 by default -> NVAR=5; B lives in bold/bnew, not passive-scalar slots.
    # No GRAV, no UNITS=COSMO (pure hydro+MHD test binary).
    #
    # GPU-memory ceiling: the cube corner-state scratch is ~162 KB/oct, so 128^3
    # needs ~44 GB (an 80 GB A100); use BRIO_WU_LEVEL=6 (64^3, ~6 GB) on a 40 GB
    # A100. The lazy alloc OOM-guards (clean error stop) if the GPU is too small.
    bw_level="${BRIO_WU_LEVEL:-7}"
    hackathon_ensure_brio_wu_ics "${bw_level}"   # sets+exports IC_DIR (generates ICs if missing)
    # Resolution follows BRIO_WU_LEVEL by patching levelmin/levelmax; the default
    # (7) uses brio_wu.nml unchanged.
    brio_nml="$(hackathon_nml brio_wu.nml)"
    if [[ "${bw_level}" != "7" ]]; then
      brio_nml="${HARNESS}/brio_wu_l${bw_level}.nml"
      sed -E "s/^[[:space:]]*levelmin=.*/ levelmin=${bw_level}/; s/^[[:space:]]*levelmax=.*/ levelmax=${bw_level}/" \
        "$(hackathon_nml brio_wu.nml)" > "${brio_nml}"
    fi
    export GPU_HYDRO=1
    export GPU_MHD=1
    export GPU_NPSCAL="${GPU_NPSCAL:-0}"          # NVAR = 5 + NPSCAL; tests default to no passive scalars
    export GPU_GRAV=0                             # no -DGRAV (not a cosmology/gravity test)
    export GPU_UNITS=                             # omit UNITS= (not UNITS=COSMO)
    export GPU_FASTMATH="${GPU_FASTMATH:-0}"
    export IC_DIR
    export DMO_TEND="${DMO_TEND:-0.1}"            # stop at t=0.1 -> one output (delta_tout defaults to tend)
    export DMO_FOUTPUT="${DMO_FOUTPUT:-1000000}"  # suppress step-based outputs; keep only the t=0.1 snapshot
    echo "== brio-wu: level=${bw_level} ($((2**bw_level))^3 unigrid) NVAR=$((5+GPU_NPSCAL)) NPRE=${GPU_NPRE} GRAV=0 riemann=hlld"
    echo "           IC_DIR=${IC_DIR} NML=${brio_nml} BUILD_BINARIES=${BUILD_BINARIES:-1} wall=${DMO_SLURM_TIME:-01:00:00}"
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd}" \
    NML="${brio_nml}" PROFILE=run \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-1}" \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
      hackathon_sbatch --time="${DMO_SLURM_TIME:-01:00:00}" dmo_gpu.slurm
    ;;
  abc)
    export MINIRAM_EXPECTED_BRANCH="${MINIRAM_EXPECTED_BRANCH:-gpu_ohm}"
    abc_nml="$(hackathon_nml abc.nml)"
    export GPU_HYDRO=1 GPU_MHD=1 GPU_NPSCAL="${GPU_NPSCAL:-0}" GPU_GRAV=0 GPU_UNITS=
    export GPU_INIT=ABC GPU_FASTMATH="${GPU_FASTMATH:-0}"
    export DMO_NO_DEFAULT_CAPS=1
    echo "== abc: 128^3 unigrid INIT=ABC induction etamag=0.001 NPRE=${GPU_NPRE} NML=${abc_nml}"
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd.abc}" \
    NML="${abc_nml}" PROFILE=run \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-1}" \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
      hackathon_sbatch --time="${DMO_SLURM_TIME:-08:00:00}" dmo_gpu.slurm
    ;;
  abc-l8)
    export MINIRAM_EXPECTED_BRANCH="${MINIRAM_EXPECTED_BRANCH:-gpu_ohm}"
    abc_nml="$(hackathon_nml abc_l8.nml)"
    export GPU_HYDRO=1 GPU_MHD=1 GPU_NPSCAL="${GPU_NPSCAL:-0}" GPU_GRAV=0 GPU_UNITS=
    export GPU_INIT=ABC GPU_FASTMATH="${GPU_FASTMATH:-0}"
    export DMO_NO_DEFAULT_CAPS=1
    echo "== abc-l8: 256^3 unigrid INIT=ABC induction etamag=0.001 tend=46 NPRE=${GPU_NPRE} NML=${abc_nml}"
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd.abc}" \
    NML="${abc_nml}" PROFILE=run \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-1}" \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
      hackathon_sbatch --time="${DMO_SLURM_TIME:-06:00:00}" dmo_gpu.slurm
    ;;
  pono)
    export MINIRAM_EXPECTED_BRANCH="${MINIRAM_EXPECTED_BRANCH:-gpu_ohm}"
    pono_nml="$(hackathon_nml pono.nml)"
    export GPU_HYDRO=1 GPU_MHD=1 GPU_NPSCAL="${GPU_NPSCAL:-0}" GPU_GRAV=0 GPU_UNITS=
    export GPU_INIT=PONO GPU_FASTMATH="${GPU_FASTMATH:-0}"
    export DMO_NO_DEFAULT_CAPS=1
    echo "== pono: AMR L5->L8 INIT=PONO induction etamag=0.0025 NPRE=${GPU_NPRE} NML=${pono_nml}"
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd.pono}" \
    NML="${pono_nml}" PROFILE=run \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-1}" \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
      hackathon_sbatch --time="${DMO_SLURM_TIME:-24:00:00}" dmo_gpu.slurm
    ;;
  mhd-turb)
    # Driven MHD turbulence on the GPU: host generates the turbulent acceleration
    # field (FFTW), the three turb_device kernels interpolate it onto the grid and
    # apply it as a source term. Same scalar-free MHD build as brio-wu/orszag-tang
    # but TURB=1 (MHD=1 HYDRO=1 TURB=1 NPSCAL=0 -> NVAR=5; FFTW linked for host
    # field generation). Uniform-box IC (uniform rho/p, zero velocity) threaded by
    # a uniform magnetic field Bz=4, written by utils/py/grafic/uniform.py.
    # Periodic (GPU MHD is periodic-only). Default 64^3 (MHD_TURB_LEVEL=6); the MHD
    # cube scratch is ~162 KB/oct, so raise the level only on a large-memory GPU.
    mt_level="${MHD_TURB_LEVEL:-6}"
    export MINIRAM_EXPECTED_BRANCH="${MINIRAM_EXPECTED_BRANCH:-gpu_turb}"
    hackathon_load_fftw || exit 1
    hackathon_ensure_mhd_turb_ics "${mt_level}"   # sets+exports IC_DIR (generates ICs if missing)
    mt_nml="$(hackathon_nml mhd_turb.nml)"
    if [[ "${mt_level}" != "6" ]]; then
      mt_nml="${HARNESS}/mhd_turb_l${mt_level}.nml"
      sed -E "s/^[[:space:]]*levelmin=.*/ levelmin=${mt_level}/; s/^[[:space:]]*levelmax=.*/ levelmax=${mt_level}/" \
        "$(hackathon_nml mhd_turb.nml)" > "${mt_nml}"
    fi
    export GPU_HYDRO=1
    export GPU_MHD=1
    export GPU_TURB=1                             # -DTURB: host field gen + GPU turb kernels; links FFTW
    export GPU_NPSCAL="${GPU_NPSCAL:-0}"          # NVAR = 5 + NPSCAL; no passive scalars
    export GPU_GRAV=0                             # no -DGRAV (not a cosmology/gravity test)
    export GPU_UNITS=                             # omit UNITS= (not UNITS=COSMO)
    export GPU_FASTMATH="${GPU_FASTMATH:-0}"
    export IC_DIR
    export DMO_TEND="${DMO_TEND:-0.5}"            # final time (outputs at 0.25, 0.5 via delta_tout)
    export DMO_FOUTPUT="${DMO_FOUTPUT:-1000000}"  # suppress step-based outputs; keep tout-scheduled dumps
    echo "== mhd-turb: level=${mt_level} ($((2**mt_level))^3 unigrid) NVAR=$((5+GPU_NPSCAL)) NPRE=${GPU_NPRE} GRAV=0 TURB=1 riemann=hlld IC Bz=4"
    echo "           IC_DIR=${IC_DIR} NML=${mt_nml} BUILD_BINARIES=${BUILD_BINARIES:-1} wall=${DMO_SLURM_TIME:-01:00:00}"
    echo "           FFTW=${FFTW} (module ${FFTW_MODULE:-fftw/nvhpc-21.5/3.3.9})${FFTW_VENDOR_INC:+ vendor_inc=${FFTW_VENDOR_INC}}"
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd.turb}" \
    NML="${mt_nml}" PROFILE=run \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-1}" \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
      hackathon_sbatch --time="${DMO_SLURM_TIME:-01:00:00}" dmo_gpu.slurm
    ;;
  mhd-turb-l8-full)
    # Full-box MHD turbulence (256^3) from namelists/mhd_turb_full_l8.nml
    # gpu_turb + FFTW required.
    case "${cmd}" in
      mhd-turb-l8-full) mt_level=8; mt_nml_name=mhd_turb_full_l8.nml; mt_label=l8_hlld ;;
    esac
    export MINIRAM_EXPECTED_BRANCH="${MINIRAM_EXPECTED_BRANCH:-gpu_turb}"
    hackathon_load_fftw || exit 1
    export MHD_TURB_BZ="${MHD_TURB_BZ:-0.7792435587233456}"
    hackathon_ensure_mhd_turb_ics "${mt_level}"
    mt_nml="$(hackathon_nml "${mt_nml_name}")"
    export GPU_HYDRO=1 GPU_MHD=1 GPU_TURB=1 GPU_NPSCAL="${GPU_NPSCAL:-0}" GPU_GRAV=0 GPU_UNITS=
    export GPU_FASTMATH="${GPU_FASTMATH:-0}"
    export GPU_NPRE="${GPU_NPRE:-4}"
    export IC_DIR
    export DMO_TEND="${DMO_TEND:-0.5}"
    export DMO_FOUTPUT="${DMO_FOUTPUT:-1000000}"
    export DMO_NSTEPMAX="${DMO_NSTEPMAX:-100000}"
    default_time="06:00:00"
    echo "== ${cmd}: level=${mt_level} ($((2**mt_level))^3) label=${mt_label} NPRE=${GPU_NPRE} NML=${mt_nml}"
    echo "           IC_DIR=${IC_DIR} BUILD_BINARIES=${BUILD_BINARIES:-1} wall=${DMO_SLURM_TIME:-${default_time}}"
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd.turb}" \
    NML="${mt_nml}" PROFILE=run \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-1}" \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
      hackathon_sbatch --time="${DMO_SLURM_TIME:-${default_time}}" dmo_gpu.slurm
    ;;
  mhd-turb-dust-l8)
    # 256^3 decaying MHD turbulence + GPU dust (turb.py ICs, turb=.false., Bz=4).
    # Requires gpu_dust branch, ALWAYS_KIND8_POS=1 (no TURB=1 / FFTW).
    # Debug interactively first: scripts/run_mhd_turb_dust_interactive.sh
    export MINIRAM_EXPECTED_BRANCH="${MINIRAM_EXPECTED_BRANCH:-gpu_dust}"
    export MHD_TURB_DUST=1
    hackathon_ensure_mhd_turb_decay_ics 8
    mt_nml="$(hackathon_nml mhd_turb_dust_l8.nml)"
    export GPU_HYDRO=1 GPU_MHD=1 GPU_TURB=0 GPU_NPSCAL="${GPU_NPSCAL:-0}" GPU_GRAV=0 GPU_UNITS=
    export GPU_FASTMATH="${GPU_FASTMATH:-0}"
    export GPU_NPRE="${GPU_NPRE:-4}"
    export GPU_ALWAYS_KIND8_POS="${GPU_ALWAYS_KIND8_POS:-1}"
    export IC_DIR
    export DMO_TEND="${DMO_TEND:-0.5}"
    export DMO_FOUTPUT="${DMO_FOUTPUT:-1000000}"
    export DMO_NSTEPMAX="${DMO_NSTEPMAX:-100000}"
    export DMO_NDUST_PER_CELL="${DMO_NDUST_PER_CELL:-1}"
    default_time="06:00:00"
    echo "== ${cmd}: 256^3 decaying MHD turb + dust ppc=${DMO_NDUST_PER_CELL} vrms=${MHD_TURB_VRMS:-2.0} NPRE=${GPU_NPRE} charge=100 size=0.1"
    echo "           NML=${mt_nml} IC_DIR=${IC_DIR} ALWAYS_KIND8_POS=${GPU_ALWAYS_KIND8_POS}"
    echo "           BUILD_BINARIES=${BUILD_BINARIES:-1} wall=${DMO_SLURM_TIME:-${default_time}}"
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    GPU_DUST_COOP_KICK="${GPU_DUST_COOP_KICK:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd.dust}" \
    NML="${mt_nml}" PROFILE=run \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-1}" \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
      hackathon_sbatch --time="${DMO_SLURM_TIME:-${default_time}}" --mem=80G dmo_gpu.slurm
    ;;
  mhd-turb-dust-12-beta-pair)
    # 256^3 decaying MHD turb + dust, 12 ppc, plasma beta=0.1 (Bz~0.779), grain 0.1 / charge 100.
    export MHD_TURB_PLASMA_BETA="${MHD_TURB_PLASMA_BETA:-0.1}"
    export MHD_TURB_BZ="${MHD_TURB_BZ:-0.7792435587233456}"
    export MHD_TURB_IC_ROOT="${MHD_TURB_IC_ROOT:-${HARNESS}/ics_mhd_turb_beta01}"
    export MHD_TURB_GRAIN_SIZE="${MHD_TURB_GRAIN_SIZE:-0.1}"
    export MHD_TURB_GRAIN_CHARGE="${MHD_TURB_GRAIN_CHARGE:-100}"
    job_scalar="$(hackathon_submit_mhd_turb_dust 12 0 1 | tail -1)"
    job_coop="$(hackathon_submit_mhd_turb_dust 12 1 1 "--dependency=afterok:${job_scalar}" | tail -1)"
    echo "Submitted mhd-turb-dust pair (12 ppc, beta=${MHD_TURB_PLASMA_BETA}): scalar=${job_scalar} coop=${job_coop}"
    ;;
  nsys-dust|nsys-dust-12|nsys-dust-64)
    # Nsight Systems profile: 256^3 decaying MHD turbulence + GPU dust (mhd_turb_dust_l8.nml).
    # Default 10 coarse steps; grains/cell via case name (1, 12, or 64).
    case "${cmd}" in
      nsys-dust) dust_ppc=1 ;;
      nsys-dust-12) dust_ppc=12 ;;
      nsys-dust-64) dust_ppc=64 ;;
    esac
    export MINIRAM_EXPECTED_BRANCH="${MINIRAM_EXPECTED_BRANCH:-gpu_dust}"
    export MHD_TURB_DUST=1
    hackathon_ensure_mhd_turb_decay_ics 8
    mt_nml="$(hackathon_nml mhd_turb_dust_l8.nml)"
    export GPU_HYDRO=1 GPU_MHD=1 GPU_TURB=0 GPU_NPSCAL="${GPU_NPSCAL:-0}" GPU_GRAV=0 GPU_UNITS=
    export GPU_FASTMATH="${GPU_FASTMATH:-0}"
    export GPU_NPRE="${GPU_NPRE:-4}"
    export GPU_ALWAYS_KIND8_POS="${GPU_ALWAYS_KIND8_POS:-1}"
    export IC_DIR
    export DMO_TEND="${DMO_TEND:-0.5}"
    export DMO_FOUTPUT="${DMO_FOUTPUT:-1000000}"
    export DMO_NSTEPMAX="${DMO_NSTEPMAX:-10}"
    export DMO_NDUST_PER_CELL="${DMO_NDUST_PER_CELL:-${dust_ppc}}"
    if (( dust_ppc >= 64 )); then
      dust_mem="${DMO_SLURM_MEM:-120G}"
      dust_time="${DMO_SLURM_TIME:-04:00:00}"
    else
      dust_mem="${DMO_SLURM_MEM:-80G}"
      dust_time="${DMO_SLURM_TIME:-02:00:00}"
    fi
    echo "== ${cmd}: 256^3 decaying MHD turb + dust PROFILE=nsys ppc=${DMO_NDUST_PER_CELL} nstepmax=${DMO_NSTEPMAX}"
    echo "           NML=${mt_nml} IC_DIR=${IC_DIR} BIN=${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd.dust}"
    echo "           BUILD_BINARIES=${BUILD_BINARIES:-0} wall=${dust_time} mem=${dust_mem}"
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    GPU_DUST_COOP_KICK="${GPU_DUST_COOP_KICK:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd.dust}" \
    NML="${mt_nml}" PROFILE=nsys \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-0}" \
    BUILD_BINARIES="${BUILD_BINARIES:-0}" \
      hackathon_sbatch --time="${dust_time}" --mem="${dust_mem}" dmo_gpu.slurm
    ;;
  ncu-dust|ncu-dust-12|ncu-dust-24|ncu-dust-64)
    # NCU full-set profile of kick_drift_dust_kernel (256^3 decaying MHD turb + dust).
    # grains/cell via case name (1, 12, 24, or 64). Override arm via GPU_DUST_COOP_KICK.
    case "${cmd}" in
      ncu-dust) dust_ppc=1 ;;
      ncu-dust-12) dust_ppc=12 ;;
      ncu-dust-24) dust_ppc=24 ;;
      ncu-dust-64) dust_ppc=64 ;;
    esac
    hackathon_submit_ncu_dust "${dust_ppc}" "${GPU_DUST_COOP_KICK:-0}" "${BUILD_BINARIES:-1}" "${NCU_DUST_DEP:-}"
    ;;
  ncu-dust-64-pair)
    job_scalar="$(hackathon_submit_ncu_dust 64 0 1 | tail -1)"
    job_coop="$(hackathon_submit_ncu_dust 64 1 1 "--dependency=afterok:${job_scalar}" | tail -1)"
    echo "Submitted NCU dust kick-drift pair (64 ppc): scalar=${job_scalar} coop=${job_coop} (coop waits for scalar)"
    ;;
  ncu-dust-24-pair)
    job_scalar="$(hackathon_submit_ncu_dust 24 0 1 | tail -1)"
    job_coop="$(hackathon_submit_ncu_dust 24 1 1 "--dependency=afterok:${job_scalar}" | tail -1)"
    echo "Submitted NCU dust kick-drift pair (24 ppc): scalar=${job_scalar} coop=${job_coop} (coop waits for scalar)"
    ;;
  ncu-dust-1-pair)
    job_scalar="$(hackathon_submit_ncu_dust 1 0 1 | tail -1)"
    job_coop="$(hackathon_submit_ncu_dust 1 1 1 "--dependency=afterok:${job_scalar}" | tail -1)"
    echo "Submitted NCU dust kick-drift pair (1 ppc): scalar=${job_scalar} coop=${job_coop} (coop waits for scalar)"
    ;;
  ncu-dust-12-pair)
    # A/B NCU: scalar (DUST_COOP_KICK=0) then coop (DUST_COOP_KICK=1); sequential build avoids binary race.
    job_scalar="$(hackathon_submit_ncu_dust 12 0 1 | tail -1)"
    job_coop="$(hackathon_submit_ncu_dust 12 1 1 "--dependency=afterok:${job_scalar}" | tail -1)"
    echo "Submitted NCU dust kick-drift pair: scalar=${job_scalar} coop=${job_coop} (coop waits for scalar)"
    ;;
  ncu-dust-12-restart-pair)
    # NCU A/B from backup_00002 (decaying MHD turb + dust, beta=0.1). Requires DMO_RESTART_BACKUP_DIR.
    export MHD_TURB_PLASMA_BETA="${MHD_TURB_PLASMA_BETA:-0.1}"
    export MHD_TURB_BZ="${MHD_TURB_BZ:-0.7792435587233456}"
    export MHD_TURB_IC_ROOT="${MHD_TURB_IC_ROOT:-${HARNESS}/ics_mhd_turb_beta01}"
    export MHD_TURB_GRAIN_SIZE="${MHD_TURB_GRAIN_SIZE:-0.1}"
    export MHD_TURB_GRAIN_CHARGE="${MHD_TURB_GRAIN_CHARGE:-100}"
    export DMO_NRESTART="${DMO_NRESTART:-2}"
    export DMO_RESTART_BACKUP_DIR="${DMO_RESTART_BACKUP_DIR:-/scratch/gpfs/moseley/hackathon/recent/dmo_gpu_2844352/mhd_turb_dust_l8/backup_00002}"
    export DMO_NSTEP_ADD="${DMO_NSTEP_ADD:-3}"
    export DMO_NSTEPMAX="${DMO_NSTEPMAX:-3}"
    export DMO_FOUTPUT="${DMO_FOUTPUT:-1000000}"
    export DMO_TEND="${DMO_TEND:-2.0}"
    job_scalar="$(hackathon_submit_ncu_dust 12 0 "${BUILD_BINARIES:-1}" | tail -1)"
    job_coop="$(hackathon_submit_ncu_dust 12 1 "${BUILD_BINARIES:-1}" "--dependency=afterok:${job_scalar}" | tail -1)"
    echo "Submitted NCU dust restart pair (backup_00002, t~0.804): scalar=${job_scalar} coop=${job_coop}"
    ;;
  orszag-tang-dust-12-pair)
    job_scalar="$(hackathon_submit_ot_dust 12 0 1 | tail -1)"
    job_coop="$(hackathon_submit_ot_dust 12 1 1 "--dependency=afterok:${job_scalar}" | tail -1)"
    echo "Submitted Orszag-Tang dust pair (12 ppc): scalar=${job_scalar} coop=${job_coop} (coop waits for scalar)"
    ;;
  orszag-tang-dust-32-pair)
    job_scalar="$(hackathon_submit_ot_dust 32 0 1 | tail -1)"
    job_coop="$(hackathon_submit_ot_dust 32 1 1 "--dependency=afterok:${job_scalar}" | tail -1)"
    echo "Submitted Orszag-Tang dust pair (32 ppc): scalar=${job_scalar} coop=${job_coop} (coop waits for scalar)"
    ;;
  orszag-tang)
    # Orszag-Tang vortex on the GPU cube ("rock") MHD integrator, HLLD by default
    # (riemann='hlld', riemann2d='hlld'). Same scalar-free MHD build as brio-wu
    # (MHD=1 HYDRO=1 NPSCAL=0 -> NVAR=5). The
    # vortex is a 2D (x,y) problem laid out in a 3D box uniform along z
    # (z-symmetry); default 256^3 unigrid, no AMR (ORSZAG_TANG_LEVEL=8).
    # Periodic boundaries (GPU MHD is periodic-only). Run to t=0.5 with outputs at
    # t=0.25 and t=0.5 (delta_tout=0.25 in orszag_tang.nml).
    # ICs are checked under ${HARNESS}/ics_orszag_tang and, if absent, generated on
    # the fly by mini-ramses-dev/utils/py/grafic/orszag_tang.py (like brio-wu).
    #
    # GPU-memory: 256^3 targets Fable scratch reductions; use ORSZAG_TANG_LEVEL=7
    # (128^3) or 6 (64^3) on smaller GPUs until the footprint work lands.
    ot_level="${ORSZAG_TANG_LEVEL:-8}"
    hackathon_ensure_orszag_tang_ics "${ot_level}"   # sets+exports IC_DIR (generates ICs if missing)
    ot_nml="$(hackathon_nml orszag_tang.nml)"
    if [[ "${ot_level}" != "8" ]]; then
      ot_nml="${HARNESS}/orszag_tang_l${ot_level}.nml"
      sed -E "s/^[[:space:]]*levelmin=.*/ levelmin=${ot_level}/; s/^[[:space:]]*levelmax=.*/ levelmax=${ot_level}/" \
        "$(hackathon_nml orszag_tang.nml)" > "${ot_nml}"
    fi
    export GPU_HYDRO=1
    export GPU_MHD=1
    export GPU_NPSCAL="${GPU_NPSCAL:-0}"          # NVAR = 5 + NPSCAL; tests default to no passive scalars
    export GPU_GRAV=0                             # no -DGRAV (not a cosmology/gravity test)
    export GPU_UNITS=                             # omit UNITS= (not UNITS=COSMO)
    export GPU_FASTMATH="${GPU_FASTMATH:-0}"
    export IC_DIR
    export DMO_TEND="${DMO_TEND:-0.5}"            # standard OT final time (outputs at 0.25, 0.5 via delta_tout)
    export DMO_FOUTPUT="${DMO_FOUTPUT:-1000000}"  # suppress step-based outputs; keep only tout-scheduled dumps
    echo "== orszag-tang: level=${ot_level} ($((2**ot_level))^3 unigrid, z-symmetry) NVAR=$((5+GPU_NPSCAL)) NPRE=${GPU_NPRE} GRAV=0 riemann=hlld"
    echo "           IC_DIR=${IC_DIR} NML=${ot_nml} BUILD_BINARIES=${BUILD_BINARIES:-1} wall=${DMO_SLURM_TIME:-01:00:00}"
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd}" \
    NML="${ot_nml}" PROFILE=run \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-1}" \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
      hackathon_sbatch --time="${DMO_SLURM_TIME:-01:00:00}" dmo_gpu.slurm
    ;;
  ot-amr)
    # Orszag-Tang MHD vortex with AMR (orszag_tang_amr.nml): levelmin=5 (32^3 base),
    # levelmax=8, pressure-gradient refinement (err_grad_p=0.15, interpol_var=0,
    # interpol_type=2). Same MHD build/IC generator as orszag-tang; ICs at levelmin.
    ot_levelmin="${OT_AMR_LEVELMIN:-5}"
    hackathon_ensure_orszag_tang_ics "${ot_levelmin}"
    ot_nml="$(hackathon_nml orszag_tang_amr.nml)"
    export GPU_HYDRO=1
    export GPU_MHD=1
    export GPU_NPRE="${OT_AMR_NPRE}"
    export GPU_NPSCAL="${GPU_NPSCAL:-0}"
    export GPU_GRAV=0
    export GPU_UNITS=
    export GPU_FASTMATH="${GPU_FASTMATH:-0}"
    export IC_DIR
    export DMO_TEND="${DMO_TEND:-0.5}"
    export DMO_FOUTPUT="${DMO_FOUTPUT:-1000000}"
    export DMO_NSTEPMAX="${DMO_NSTEPMAX:-10000}"
    echo "== ot-amr: levelmin=${ot_levelmin} ($((2**ot_levelmin))^3 base) levelmax=${OT_AMR_LEVELMAX} AMR err_grad_p=0.15 CUB_SORT_REFINE=1 nstepmax=${DMO_NSTEPMAX} NVAR=$((5+GPU_NPSCAL)) NPRE=${GPU_NPRE} GRAV=0 riemann=hlld"
    echo "           IC_DIR=${IC_DIR} NML=${ot_nml} BUILD_BINARIES=${BUILD_BINARIES:-1} wall=${DMO_SLURM_TIME:-${OT_AMR_SLURM_TIME}}"
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_CUDA_ARCH="${GPU_CUDA_ARCH}" \
    GPU_PAPER=0 \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd}" \
    NML="${ot_nml}" PROFILE=run \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-1}" \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
      hackathon_sbatch --time="${DMO_SLURM_TIME:-${OT_AMR_SLURM_TIME}}" dmo_gpu.slurm
    ;;
  ot-pscal)
    # Orszag-Tang MHD AMR with one passive scalar (orszag_tang_amr_pscal.nml).
    # Same grid/refinement as ot-amr; ICs add ic_pvar_00001 checkerboard (i even .or. j even).
    # Build: MHD=1 HYDRO=1 NPSCAL=1 -> NVAR=6; passive scalar is output variable 9.
    ot_levelmin="${OT_AMR_LEVELMIN:-5}"
    hackathon_ensure_ot_pscal_ics "${ot_levelmin}"
    ot_nml="$(hackathon_nml orszag_tang_amr_pscal.nml)"
    export GPU_HYDRO=1
    export GPU_MHD=1
    export GPU_NPSCAL=1
    export GPU_GRAV=0
    export GPU_UNITS=
    export GPU_FASTMATH="${GPU_FASTMATH:-0}"
    export IC_DIR
    export DMO_TEND="${DMO_TEND:-0.5}"
    export DMO_FOUTPUT="${DMO_FOUTPUT:-1000000}"
    export DMO_NSTEPMAX="${DMO_NSTEPMAX:-10000}"
    echo "== ot-pscal: levelmin=${ot_levelmin} ($((2**ot_levelmin))^3 base) levelmax=${OT_AMR_LEVELMAX} AMR err_grad_p=0.15 checkerboard pscal nstepmax=${DMO_NSTEPMAX} NVAR=$((5+GPU_NPSCAL)) NPRE=${GPU_NPRE} GRAV=0 riemann=hlld"
    echo "           IC_DIR=${IC_DIR} NML=${ot_nml} BUILD_BINARIES=${BUILD_BINARIES:-1} wall=${DMO_SLURM_TIME:-00:05:00}"
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd}" \
    NML="${ot_nml}" PROFILE=run \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-1}" \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
      hackathon_sbatch --time="${DMO_SLURM_TIME:-00:05:00}" dmo_gpu.slurm
    ;;
  nsys-ot)
    # Nsight Systems profile of the Orszag-Tang MHD vortex (same build/ICs as
    # orszag-tang), capped at 5 coarse timesteps for a short MHD integrator trace.
    # Default 128^3 (ORSZAG_TANG_LEVEL=7) and NPRE=8 (double precision).
    # Re-profile without recompiling: BUILD_BINARIES=0 ./submit_profiles.sh nsys-ot
    ot_level="${ORSZAG_TANG_LEVEL:-7}"
    hackathon_ensure_orszag_tang_ics "${ot_level}"
    ot_nml="$(hackathon_nml orszag_tang.nml)"
    if [[ "${ot_level}" != "8" ]]; then
      ot_nml="${HARNESS}/orszag_tang_l${ot_level}.nml"
      sed -E "s/^[[:space:]]*levelmin=.*/ levelmin=${ot_level}/; s/^[[:space:]]*levelmax=.*/ levelmax=${ot_level}/" \
        "$(hackathon_nml orszag_tang.nml)" > "${ot_nml}"
    fi
    export GPU_HYDRO=1
    export GPU_MHD=1
    export GPU_NPRE=8
    export GPU_NPSCAL="${GPU_NPSCAL:-0}"
    export GPU_GRAV=0
    export GPU_UNITS=
    export GPU_FASTMATH="${GPU_FASTMATH:-0}"
    export IC_DIR
    export DMO_TEND="${DMO_TEND:-0.5}"
    export DMO_FOUTPUT="${DMO_FOUTPUT:-5}"
    export DMO_NSTEPMAX="${DMO_NSTEPMAX:-5}"
    echo "== nsys-ot: level=${ot_level} ($((2**ot_level))^3 unigrid) PROFILE=nsys MHD=1 nstepmax=${DMO_NSTEPMAX} NVAR=$((5+GPU_NPSCAL)) NPRE=${GPU_NPRE} GRAV=0"
    echo "           IC_DIR=${IC_DIR} NML=${ot_nml} BUILD_BINARIES=${BUILD_BINARIES:-1} wall=${DMO_SLURM_TIME:-01:00:00}"
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_NPRE="${GPU_NPRE}" \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.mhd}" \
    NML="${ot_nml}" PROFILE=nsys \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-0}" \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
      hackathon_sbatch --time="${DMO_SLURM_TIME:-01:00:00}" dmo_gpu.slurm
    ;;
  nsys-oth)
    # Hydro-only counterpart to nsys-ot: same Orszag-Tang ICs/grid/step cap, but
    # MHD=0 (ramses3d.hydro). NPRE=8 (double precision). Namelist patches
    # mhd=.false. and riemann='hll' because hlld is MHD-only at compile time.
    # Re-profile without recompiling: BUILD_BINARIES=0 ./submit_profiles.sh nsys-oth
    ot_level="${ORSZAG_TANG_LEVEL:-7}"
    hackathon_ensure_orszag_tang_ics "${ot_level}"
    ot_nml="${HARNESS}/orszag_tang_l${ot_level}_hydro.nml"
    sed -E \
      -e "s/^[[:space:]]*levelmin=.*/ levelmin=${ot_level}/" \
      -e "s/^[[:space:]]*levelmax=.*/ levelmax=${ot_level}/" \
      -e "s/^[[:space:]]*mhd=.*/ mhd=.false./" \
      -e "s/^[[:space:]]*riemann=.*/ riemann='hll'/" \
      -e "s/^[[:space:]]*riemann2d=.*/ riemann2d='hll'/" \
      "$(hackathon_nml orszag_tang.nml)" > "${ot_nml}"
    export GPU_HYDRO=1
    export GPU_MHD=0
    export GPU_NPRE=8
    export GPU_NPSCAL="${GPU_NPSCAL:-0}"
    export GPU_GRAV=0
    export GPU_UNITS=
    export GPU_FASTMATH="${GPU_FASTMATH:-0}"
    export IC_DIR
    export DMO_TEND="${DMO_TEND:-0.5}"
    export DMO_FOUTPUT="${DMO_FOUTPUT:-5}"
    export DMO_NSTEPMAX="${DMO_NSTEPMAX:-5}"
    echo "== nsys-oth: level=${ot_level} ($((2**ot_level))^3 unigrid) PROFILE=nsys MHD=0 (hydro-only) nstepmax=${DMO_NSTEPMAX} NVAR=$((5+GPU_NPSCAL)) NPRE=${GPU_NPRE} GRAV=0"
    echo "           IC_DIR=${IC_DIR} NML=${ot_nml} BUILD_BINARIES=${BUILD_BINARIES:-1} wall=${DMO_SLURM_TIME:-01:00:00}"
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_NPRE="${GPU_NPRE}" \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.hydro}" \
    NML="${ot_nml}" PROFILE=nsys \
    DMO_GPU_LAUNCH_BLOCKING="${DMO_GPU_LAUNCH_BLOCKING:-0}" \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
      hackathon_sbatch --time="${DMO_SLURM_TIME:-01:00:00}" dmo_gpu.slurm
    ;;
  ncu-ot-localize)
    # Same submission as ncu-ot, but build with -gpu=lineinfo @ -O4 and export NCU source page.
    export GPU_LINEINFO=1
    export NCU_IMPORT_SOURCE=yes
    export NCU_EXPORT_SOURCE=1
    export NCU_DEFAULT_SOURCE="${NCU_DEFAULT_SOURCE:-gpu_hydro.cuf}"
    : "${ORSZAG_TANG_LEVEL:=7}"
    hackathon_submit_ncu_ot 1
    ;;
  ncu-ot)
    # Nsight Compute profile of the GPU cube integrator on the Orszag-Tang
    # vortex (same MHD build/ICs as orszag-tang / nsys-ot). NCU is slow, so the
    # run is capped at 2 coarse timesteps; profiles the first NCU_LAUNCH_COUNT
    # launches of hydro_integrator_kernel (default 5).
    # Re-profile without recompiling: BUILD_BINARIES=0 ./submit_profiles.sh ncu-ot
    hackathon_submit_ncu_ot 0
    ;;
  ot-cpu)
    # CPU MPI reference for Orszag-Tang MHD AMR — same physics as Marlowe ot-amr:
    # orszag_tang_amr.nml levelmin=5 (32^3 base), levelmax=8, err_grad_p=0.15,
    # NPRE=8 (double precision), ngridmax=30M, ncachemax=12M. dmo_cpu.slurm: pu,
    # 96 MPI ranks, --mem=80G (matches Marlowe ot-amr GPU host allocation).
    # Build on login: BUILD_CPU=1 ./submit_profiles.sh ot-cpu
    export GCC_MODULE="${GCC_MODULE:-gcc-toolset/10}"
    export OPENMPI_MODULE="${OPENMPI_MODULE:-openmpi/gcc-toolset-10/4.1.0}"
    export OPENMPI_USE_MODULES="${OPENMPI_USE_MODULES:-1}"
    ot_levelmin="${OT_AMR_LEVELMIN:-5}"
    hackathon_ensure_orszag_tang_ics "${ot_levelmin}"
    ot_nml="$(hackathon_nml orszag_tang_amr.nml)"
    export IC_DIR
    export CPU_MHD=1
    export CPU_HYDRO=1
    export CPU_GRAV=0
    export CPU_NPRE="${CPU_NPRE:-8}"
    export CPU_NPSCAL="${CPU_NPSCAL:-0}"
    export CPU_UNITS=
    export DMO_SLURM_MEM="${DMO_SLURM_MEM:-80G}"
    BIN_CPU="${BIN_CPU:-${MINIRAM}/bin/ramses3d.mhd.cpu}"
    if [[ "${BUILD_CPU:-0}" == "1" ]]; then
      hackathon_build_cpu_binary || exit 1
    else
      if [[ ! -x "${BIN_CPU}" ]]; then
        echo "ERROR: pre-built CPU MHD binary not found: ${BIN_CPU}" >&2
        echo "       Build on login: BUILD_CPU=1 ./submit_profiles.sh ot-cpu" >&2
        exit 1
      fi
      echo "== using pre-built CPU MHD binary: ${BIN_CPU}"
      ls -la "${BIN_CPU}"
    fi
    export DMO_TEND="${DMO_TEND:-0.5}"
    export DMO_FOUTPUT="${DMO_FOUTPUT:-1000000}"
    export DMO_NSTEPMAX="${DMO_NSTEPMAX:-10000}"
    echo "== ot-cpu: levelmin=${ot_levelmin} ($((2**ot_levelmin))^3 base) levelmax=${OT_AMR_LEVELMAX} AMR err_grad_p=0.15 nstepmax=${DMO_NSTEPMAX} NPRE=${CPU_NPRE} pu/96 MPI ranks mem=${DMO_SLURM_MEM}"
    echo "           IC_DIR=${IC_DIR} NML=${ot_nml} wall=${DMO_SLURM_TIME:-24:00:00}"
    BUILD_BINARIES=0 \
    BIN_CPU="${BIN_CPU}" \
    NML="${ot_nml}" \
      hackathon_sbatch --time="${DMO_SLURM_TIME:-24:00:00}" --mem="${DMO_SLURM_MEM}" dmo_cpu.slurm
    ;;
  orszag-tang-cpu)
    # CPU MPI reference for Orszag-Tang (same namelist/ICs as orszag-tang GPU).
    # dmo_cpu.slurm: 1 pu node, 96 MPI ranks, --exclusive --mem=730G.
    # Build on login: BUILD_CPU=1 ./submit_profiles.sh orszag-tang-cpu
    export GCC_MODULE="${GCC_MODULE:-gcc-toolset/10}"
    export OPENMPI_MODULE="${OPENMPI_MODULE:-openmpi/gcc-toolset-10/4.1.0}"
    export OPENMPI_USE_MODULES="${OPENMPI_USE_MODULES:-1}"
    ot_level="${ORSZAG_TANG_LEVEL:-8}"
    hackathon_ensure_orszag_tang_ics "${ot_level}"
    ot_nml="$(hackathon_nml orszag_tang.nml)"
    if [[ "${ot_level}" != "8" ]]; then
      ot_nml="${HARNESS}/orszag_tang_l${ot_level}.nml"
      sed -E "s/^[[:space:]]*levelmin=.*/ levelmin=${ot_level}/; s/^[[:space:]]*levelmax=.*/ levelmax=${ot_level}/" \
        "$(hackathon_nml orszag_tang.nml)" > "${ot_nml}"
    fi
    export IC_DIR
    export CPU_MHD=1
    export CPU_HYDRO=1
    export CPU_GRAV=0
    export CPU_NPRE="${CPU_NPRE:-4}"
    export CPU_NPSCAL="${CPU_NPSCAL:-0}"
    export CPU_UNITS=
    BIN_CPU="${BIN_CPU:-${MINIRAM}/bin/ramses3d.mhd.cpu}"
    if [[ "${BUILD_CPU:-0}" == "1" ]]; then
      hackathon_build_cpu_binary || exit 1
    else
      if [[ ! -x "${BIN_CPU}" ]]; then
        echo "ERROR: pre-built CPU MHD binary not found: ${BIN_CPU}" >&2
        echo "       Build on login: BUILD_CPU=1 ./submit_profiles.sh orszag-tang-cpu" >&2
        exit 1
      fi
      echo "== using pre-built CPU MHD binary: ${BIN_CPU}"
      ls -la "${BIN_CPU}"
    fi
    export DMO_TEND="${DMO_TEND:-0.5}"
    export DMO_FOUTPUT="${DMO_FOUTPUT:-1000000}"
    echo "== orszag-tang-cpu: level=${ot_level} ($((2**ot_level))^3 unigrid) NPRE=${CPU_NPRE} pu/96 MPI ranks"
    echo "           IC_DIR=${IC_DIR} NML=${ot_nml} wall=${DMO_SLURM_TIME:-00:30:00}"
    BUILD_BINARIES=0 \
    BIN_CPU="${BIN_CPU}" \
    NML="${ot_nml}" \
      hackathon_sbatch --time="${DMO_SLURM_TIME:-00:30:00}" dmo_cpu.slurm
    ;;
  cosmo-gpu-sanitize)
    # cosmo-gpu under compute-sanitizer memcheck. Defaults to the OPTIMIZED build
    # (GPU_DEBUG=0): memcheck still reports the faulting kernel + invalid access +
    # address/thread, and -- unlike GPU_DEBUG=1 on bin/Makefile -- it does NOT add
    # -Minit-real=snan, whose nvfortran+_CUDA host NaN-memset (__c_mset8_avx)
    # segfaults on the host before any device code runs.
    #
    # For device *source lines*, request the debug build AND the snan-free A100
    # makefile together:
    #   GPU_DEBUG=1 ./submit_profiles.sh cosmo-gpu-sanitize
    # Memcheck is slow; cap with DMO_NSTEPMAX=N to stop just past the first fault.
    echo "== cosmo-gpu-sanitize: GPU_NPRE=${GPU_NPRE:-4} GPU_DEBUG=${GPU_DEBUG:-0} (memcheck)"
    [[ -n "${DMO_NSTEPMAX:-}" ]] && export DMO_NSTEPMAX
    [[ -n "${DMO_FOUTPUT:-}" ]] && export DMO_FOUTPUT
    GPU_HYDRO=1 \
    GPU_DEBUG="${GPU_DEBUG:-0}" \
    GPU_NPRE="${GPU_NPRE:-4}" \
    GPU_CUDA_ARCH=${GPU_CUDA_ARCH} \
    GPU_PAPER=0 \
    GPU_KICK_COOP_GATHER="${GPU_KICK_COOP_GATHER:-0}" \
    BIN_GPU="${BIN_GPU:-${MINIRAM}/bin/ramses3d.hydro}" \
    NML="$(hackathon_nml cosmo.nml)" PROFILE=sanitize \
    DMO_GPU_LAUNCH_BLOCKING=1 \
    BUILD_BINARIES="${BUILD_BINARIES:-1}" \
    DMO_AEND="${DMO_AEND:-0.2}" \
      hackathon_sbatch dmo_gpu.slurm
    ;;
  export)
    if [[ $# -lt 1 ]]; then
      echo "Usage: $0 export PATH/to/trace.nsys-rep [OUT_DIR]" >&2
      exit 1
    fi
    ./export_nsys_stats.sh "$@"
    ;;
  help|*)
    cat <<EOF
Hackathon profile launcher (run from ${HARNESS})

  ./submit_profiles.sh test           validation: L7 (5 step) + AMR (100 step)
  ./submit_profiles.sh test-amr-long  AMR-only long run (250 step, 2 h wall)
  ./submit_profiles.sh nsys-l7        nsys profile, dm_pic_poisson_l7 (build + run)
  ./submit_profiles.sh ncu          ncu on kick_drift_part_kernel + cic_part_medium_kernel (2 steps, 2 jobs)
  ./submit_profiles.sh ncu-cic      alias for ncu
  ./submit_profiles.sh ncu-cic-localize  ncu-cic + lineinfo + source-page export (2 dependent NCU jobs)
  ./submit_profiles.sh nsys-amr    nsys on dm_pic_poisson_l7_amr_l8
  ./submit_profiles.sh dmo-cpu     dmo.nml cosmological DMO (pre-built ramses3d.cpu, pu)
  ./submit_profiles.sh dmo-gpu     dmo.nml cosmological DMO (no clumps, GPU)
  ./submit_profiles.sh dmo-gpu-block     dmo-gpu with CUDA_LAUNCH_BLOCKING=1
  ./submit_profiles.sh dmo-gpu-sanitize  dmo-gpu under compute-sanitizer memcheck
  ./submit_profiles.sh dmo-gpu-nsys20    nsys profile of dmo.nml for 20 steps
  ./submit_profiles.sh dmo-gpu-cic-slow  CIC slow path (dmo_cic_slow.nml, 30 steps)
  ./submit_profiles.sh cosmo-gpu     cosmo.nml DM+gas (HYDRO=1, ramses3d.hydro; LAUNCH_BLOCKING on)
  ./submit_profiles.sh debug-cosmo   debug_cosmo.nml cosmo (Makefile.debug-cosmo, NPRE=8, isothermal HLLC)
  ./submit_profiles.sh debug-cosmo-unigrid  debug_cosmo_unigrid.nml GPU unigrid L7 parity
  ./submit_profiles.sh debug-cosmo-cpu  debug_cosmo_cpu.nml 96-rank MPI (HYDRO+GRAV+UNITS=COSMO NPRE=8)
  ./submit_profiles.sh debug-cosmo-cpu-unigrid  unigrid CPU smoke (50 steps default)
  ./submit_profiles.sh cosmo-zoom    cosmo_zoom.nml zoom DM+gas (NPRE=8, FASTMATH=1, ngridmax=24M)
  ./submit_profiles.sh brio-wu       brio_wu.nml 3D Brio-Wu MHD shock tube (MHD=1, HLLD, 128^3 unigrid; auto ICs)
  ./submit_profiles.sh abc           abc.nml ABC-flow resistive MHD (INIT=ABC, 128^3 unigrid, etamag=0.001; gpu_ohm)
  ./submit_profiles.sh pono          pono.nml Ponomarenko resistive MHD AMR (INIT=PONO, L5->L8, etamag=0.0025; gpu_ohm)
  ./submit_profiles.sh mhd-turb-l8-full   mhd_turb_full_l8.nml (256^3 HLLD)
  ./submit_profiles.sh mhd-turb-dust-l8   mhd_turb_dust_l8.nml (256^3 decaying MHD turb + dust, turb.py ICs, ALWAYS_KIND8_POS=1)
  ./submit_profiles.sh nsys-dust          nsys profile decaying MHD turb + dust L8, 1 grain/cell, 10 steps
  ./submit_profiles.sh nsys-dust-12       nsys profile decaying MHD turb + dust L8, 12 grains/cell, 10 steps
  ./submit_profiles.sh nsys-dust-64       nsys profile decaying MHD turb + dust L8, 64 grains/cell, 10 steps
  ./submit_profiles.sh ncu-dust           ncu kick_drift_dust_kernel, 1 grain/cell, 3 steps (GPU_DUST_COOP_KICK=0|1)
  ./submit_profiles.sh ncu-dust-12        ncu kick_drift_dust_kernel, 12 grains/cell, 3 steps (GPU_DUST_COOP_KICK=0|1)
  ./submit_profiles.sh ncu-dust-64        ncu kick_drift_dust_kernel, 64 grains/cell, 3 steps (120G, 8h wall default)
  ./submit_profiles.sh ncu-dust-1-pair      ncu A/B: scalar then coop kick_drift_dust, 1 ppc L8 reference (2 sequential jobs)
  ./submit_profiles.sh ncu-dust-12-pair     ncu A/B: scalar then coop kick_drift_dust, 12 ppc (2 sequential jobs)
  ./submit_profiles.sh ncu-dust-24-pair     ncu A/B: scalar then coop kick_drift_dust, 24 ppc L8 (2 sequential jobs)
  ./submit_profiles.sh ncu-dust-64-pair     ncu A/B: scalar then coop kick_drift_dust, 64 ppc (2 sequential jobs)
  ./submit_profiles.sh mhd-turb      mhd_turb.nml 3D driven MHD turbulence (MHD=1 TURB=1, 64^3 unigrid, uniform IC Bz=4; gpu_turb)
  ./submit_profiles.sh orszag-tang      orszag_tang.nml 3D Orszag-Tang MHD vortex GPU (MHD=1, HLLD, 256^3 unigrid; auto ICs)
  ./submit_profiles.sh ot-amr           orszag_tang_amr.nml Orszag-Tang MHD AMR GPU (32^3 base L5->L8, err_grad_p=0.15; auto ICs)
  ./submit_profiles.sh ot-pscal         orszag_tang_amr_pscal.nml ot-amr + checkerboard passive scalar (NPSCAL=1; auto ICs)
  ./submit_profiles.sh ot-cpu           orszag_tang_amr.nml Orszag-Tang MHD AMR CPU (L5->L10, NPRE=8, 80G, 24h; auto ICs)
  ./submit_profiles.sh nsys-ot          nsys profile of Orszag-Tang MHD vortex (128^3, NPRE=8, 5 timesteps; auto ICs)
  ./submit_profiles.sh nsys-oth         nsys profile of Orszag-Tang hydro-only (128^3, NPRE=8, 5 timesteps; MHD=0)
  ./submit_profiles.sh ncu-ot           ncu profile of hydro_integrator_kernel on Orszag-Tang (2 steps; auto ICs)
  ./submit_profiles.sh ncu-ot-localize  ncu-ot + lineinfo + source-page export for shared bank conflicts (128^3 default)
  ./submit_profiles.sh orszag-tang-cpu  orszag_tang.nml unigrid Orszag-Tang MHD CPU MPI (pu, 96 ranks; auto ICs)
  ./submit_profiles.sh cosmo-gpu-sanitize  cosmo-gpu under compute-sanitizer memcheck + lineinfo
  ./submit_profiles.sh export TRACE.nsys-rep [OUT_DIR]

After jobs finish:
  ./export_nsys_stats.sh profiles_<jobid>/*/*.nsys-rep
  scp -r stellar-intel:~/hackathon/profiles_* ./   # optional: download traces

Environment (prefix or export before submit):
  MINIRAM=PATH      RAMSES checkout (default: ~/mini-ramses-dev on cluster)
  GPU_NPRE=4|8      Makefile NPRE (default 4; override e.g. GPU_NPRE=8)
  GPU_FASTMATH=0|1  NVHPC -gpu fastmath (default 0)
  GPU_KICK_COOP_GATHER=0|1  warp-cooperative kick gather (default 0; now also
                    controls ncu/ncu-cic and nsys-l7 -- no longer hardcoded 1 there)
  GPU_KICK_COOP_VALIDATE=0|1  in-kernel exact A/B vs scalar gather (default 0;
                    needs GPU_KICK_COOP_GATHER=1; correctness runs only)
  GPU_DUST_COOP_KICK=0|1  warp-cooperative charged-dust hydro/B kick gather
                    (default 0; use with nsys-dust / nsys-dust-12)
  IC_ZOOM_DIR=PATH  zoom grafic IC root (default: ~/hackathon/ics_zoom; auto-download)
  BRIO_WU_LEVEL=N   brio-wu resolution 2^N per axis (default 7=128^3; 6=64^3 fits a 40GB A100)
  MHD_TURB_LEVEL=N  mhd-turb resolution 2^N per axis (default 6=64^3; needs gpu_turb branch)
  FFTW_MODULE=MOD   FFTW Environment Modules name (default fftw/nvhpc-21.5/3.3.9; mhd-turb auto-loads)
  FFTW=PATH         FFTW install prefix override (skip module load if include/fftw3.h exists)
  MINIRAM_EXPECTED_BRANCH=BRANCH  checkout guard (mhd-turb sets gpu_turb; MHD cases default gpu_mhd)
  ORSZAG_TANG_LEVEL=N  orszag-tang resolution 2^N per axis (default 8=256^3; 7=128^3, 6=64^3 for smaller GPUs)
  OT_AMR_LEVELMIN=N    ot-amr / ot-pscal grafic IC / base-grid level (default 5=32^3)
  OT_PSCAL_IC_ROOT=PATH  ot-pscal IC root (default: ~/hackathon/ics_orszag_tang_pscal)
  CUB_SORT_REFINE=0|1  AMR Hilbert-key radix sort via CUB (bin/Makefile default 1)
  CUB_SCAN_REFINE=0|1  AMR refine prefix-sum via CUB inclusive scan (default 1)
  DMO_NO_DEFAULT_CAPS=0|1  skip default nstepmax/foutput/tend injection (debug-cosmo sets 1)
  NVHPC_MODULE=nvhpc/25.5  NVHPC module name (debug-cosmo pins this)
  NVHPC_MODULE_STRICT=0|1  fail if NVHPC_MODULE cannot load (debug-cosmo sets 1)
  DMO_SLURM_TIME=HH:MM:SS  sbatch walltime (cosmo-zoom default 12:00:00)
  DMO_GPU_LAUNCH_BLOCKING=0|1  CUDA_LAUNCH_BLOCKING (cosmo-gpu/zoom default 1)
  DMO_NSTEPMAX=N    coarse-step cap (dmo/cosmo default 1000; sanitize/nsys/ncu profiles override)
  NCU_KERNEL=FILTER ncu kernel filter (ncu-ot default: regex:.*hydro_integrator_kernel.*)
  NCU_LAUNCH_SKIP=N NCU_LAUNCH_COUNT=N  ncu launch window (ncu-ot default skip=0 count=5)
  NCU_SET=full|...  ncu metric set (ncu-ot default full)
  GPU_LINEINFO=1    CUDA_PROFILE=1 on bin/Makefile (ncu-*-localize sets this)
  NCU_IMPORT_SOURCE=yes  embed/resolve source at NCU capture (localize profiles)
  NCU_EXPORT_SOURCE=1    write profile_exports/*_source.csv after capture
  NCU_DEFAULT_SOURCE=F   NVFortran RDC "default" -> MINIRAM/gpu/F (gpu_hydro.cuf / gpu_part.cuf)
  DMO_AEND=A        override aend (cosmo-gpu uses cosmo.nml default aend=1.0)
  BUILD_BINARIES=1  rebuild GPU binary (dmo-gpu/cosmo-gpu default 1; set 0 to reuse)
  CLEAN=0|1         GPU make clean before build (default 1; CLEAN=0 incremental after one-file edits)
  BUILD_CPU=1       build ramses3d(.mhd).cpu on login before ot-cpu / orszag-tang-cpu / dmo-cpu submit
  CPU_NPRE=4|8      CPU build precision (default 4)
  BIN_CPU=PATH      CPU binary (ot-cpu / orszag-tang-cpu default: ramses3d.mhd.cpu)
  DMO_SLURM_MEM=G   ot-cpu Slurm --mem (default 80G, matches Marlowe ot-amr GPU host)
  PART_DEP_ALGO=N   patch part_dep_algo (1=large, 2=medium, 3=small GPU CIC)

See profiling_summary.md and CLUSTER.md for interpretation.
EOF
    ;;
esac
