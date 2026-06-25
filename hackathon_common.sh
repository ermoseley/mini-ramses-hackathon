# Shared helpers for hackathon SLURM scripts.
# Batch jobs: source "${HARNESS_DIR:-${SLURM_SUBMIT_DIR}}/hackathon_bootstrap.sh"
#
# Cluster profiles: clusters/{stellar,marlowe,sherlock}.profile via bin/hackathon-env.sh

hackathon_repo_root() {
  if [[ -n "${HACKATHON_REPO_ROOT:-}" && -f "${HACKATHON_REPO_ROOT}/hackathon_common.sh" ]]; then
    printf '%s' "${HACKATHON_REPO_ROOT}"
    return 0
  fi
  local dir="${HARNESS_DIR:-${SLURM_SUBMIT_DIR:-${SCRIPT_DIR:-.}}}"
  if [[ -f "${dir}/hackathon_common.sh" ]]; then
    printf '%s' "${dir}"
    return 0
  fi
  if [[ -f "${dir}/../hackathon_common.sh" ]]; then
    cd "${dir}/.." && pwd
    return 0
  fi
  return 1
}

# Namelist path under namelists/ (repo layout).
hackathon_nml() {
  local base name="${1}"
  local root
  root="$(hackathon_repo_root 2>/dev/null || echo "${HARNESS_DIR:-.}")"
  if [[ -f "${root}/namelists/${name}" ]]; then
    printf '%s' "${root}/namelists/${name}"
  else
    printf '%s' "${root}/${name}"
  fi
}

# Resolve slurm script (slurm/ subdir or repo root).
hackathon_slurm_script() {
  local name="$1" root candidate
  root="$(hackathon_repo_root 2>/dev/null || echo "${HARNESS_DIR:-.}")"
  for candidate in \
      "${root}/${name}" \
      "${root}/slurm/${name}" \
      "${HARNESS_DIR}/${name}" \
      "${HARNESS_DIR}/slurm/${name}"; do
    if [[ -f "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  printf '%s' "${root}/slurm/${name}"
}

hackathon_setup_paths() {
  SCRIPT_DIR="${SCRIPT_DIR:-${HARNESS_DIR:-${SLURM_SUBMIT_DIR:-.}}}"
  HARNESS_DIR="${HARNESS_DIR:-${SCRIPT_DIR}}"
  RUN_DIR="${RUN_DIR:-${RUN_DIR_DEFAULT:-${HARNESS_DIR}}}"
  MINIRAM="${MINIRAM:-${MINIRAM_DEFAULT:-${HOME}/mini-ramses-dev}}"
  IC_DIR="${IC_DIR:-${HARNESS_DIR}/ics_ramses}"
  IC_ZOOM_DIR="${IC_ZOOM_DIR:-${HARNESS_DIR}/ics_zoom}"
  GPU_MAKEFILE="${GPU_MAKEFILE:-Makefile.a100}"
  GPU_SLURM_TEST="${GPU_SLURM_TEST:-slurm/test_gpu_dmo.slurm}"
  GPU_SLURM_PROFILE="${GPU_SLURM_PROFILE:-slurm/profile_gpu_dmo.slurm}"
  GPU_CUDA_ARCH="${GPU_CUDA_ARCH:-${GPU_CUDA_ARCH_DEFAULT:-sm_80}}"
  GPU_TARGETS="${GPU_TARGETS:-${GPU_TARGETS_DEFAULT:-}}"
  GPU_NPRE="${GPU_NPRE:-${GPU_NPRE_DEFAULT:-4}}"
  OT_AMR_LEVELMAX="${OT_AMR_LEVELMAX:-${OT_AMR_LEVELMAX_DEFAULT:-8}}"
  OT_AMR_SLURM_TIME="${OT_AMR_SLURM_TIME:-${OT_AMR_SLURM_TIME_DEFAULT:-00:05:00}}"
  OT_AMR_NPRE="${OT_AMR_NPRE:-${OT_AMR_NPRE_DEFAULT:-4}}"
  local _root
  _root="$(hackathon_repo_root 2>/dev/null || echo "${HARNESS_DIR}")"
  NAMELIST_DIR="${NAMELIST_DIR:-${_root}/namelists}"
  export HARNESS_DIR RUN_DIR MINIRAM IC_DIR IC_ZOOM_DIR GPU_MAKEFILE GPU_SLURM_TEST GPU_SLURM_PROFILE
  export GPU_CUDA_ARCH GPU_TARGETS GPU_NPRE OT_AMR_LEVELMAX OT_AMR_SLURM_TIME OT_AMR_NPRE NAMELIST_DIR
}

# Zoom-in grafic ICs for cosmo_zoom.nml (tigress tarball per load_zoom_ic.sh).
hackathon_ensure_zoom_ics() {
  hackathon_setup_paths
  local ic_root="${1:-${IC_ZOOM_DIR}}"
  local url="https://tigress-web.princeton.edu/~rt3504/DAT/ics_zoom/grafic.tar"
  if [[ -d "${ic_root}/level_007" ]]; then
    echo "== zoom ICs present: ${ic_root}/level_007"
    export IC_ZOOM_DIR="${ic_root}"
    return 0
  fi
  echo "== zoom ICs missing under ${ic_root}; downloading (see cosmo_zoom.nml / load_zoom_ic.sh)"
  mkdir -p "${ic_root}"
  local tar_path="${ic_root}/grafic.tar"
  if command -v curl >/dev/null 2>&1; then
    curl -fL "${url}" --output "${tar_path}"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "${tar_path}" "${url}"
  else
    echo "ERROR: need curl or wget to fetch zoom ICs from tigress" >&2
    return 1
  fi
  tar -xf "${tar_path}" -C "${ic_root}"
  rm -f "${tar_path}"
  if [[ ! -d "${ic_root}/level_007" ]]; then
    echo "ERROR: zoom IC extract failed; expected ${ic_root}/level_007" >&2
    ls -la "${ic_root}" >&2 || true
    return 1
  fi
  echo "== zoom ICs installed under ${ic_root}"
  export IC_ZOOM_DIR="${ic_root}"
}

# True when a grafic MHD IC set has hydro + all six face-B files (input_hydro_grafic.f90).
hackathon_grafic_mhd_ics_complete() {
  local ic_dir="$1"
  [[ -f "${ic_dir}/ic_d" && -f "${ic_dir}/ic_u" && -f "${ic_dir}/ic_v" &&
     -f "${ic_dir}/ic_w" && -f "${ic_dir}/ic_p" &&
     -f "${ic_dir}/ic_bxleft" && -f "${ic_dir}/ic_bxright" &&
     -f "${ic_dir}/ic_byleft" && -f "${ic_dir}/ic_byright" &&
     -f "${ic_dir}/ic_bzleft" && -f "${ic_dir}/ic_bzright" ]]
}

# MHD grafic IC set plus one passive scalar file (ic_pvar_00001; title.f90 padding).
hackathon_grafic_mhd_pscal_ics_complete() {
  local ic_dir="$1"
  hackathon_grafic_mhd_ics_complete "${ic_dir}" && [[ -f "${ic_dir}/ic_pvar_00001" ]]
}

# Legacy generators wrote ic_pvar_1; grafic reader expects ic_pvar_00001.
hackathon_fix_pscal_ic_name() {
  local ic_dir="$1"
  if [[ -f "${ic_dir}/ic_pvar_1" && ! -f "${ic_dir}/ic_pvar_00001" ]]; then
    ln -sf ic_pvar_1 "${ic_dir}/ic_pvar_00001"
    echo "== linked ${ic_dir}/ic_pvar_00001 -> ic_pvar_1 (grafic title.f90 naming)"
  fi
}

hackathon_file_size_bytes() {
  local f="$1"
  stat -c%s "${f}" 2>/dev/null || stat -f%z "${f}" 2>/dev/null || wc -c < "${f}"
}

# True when ic_velcx/cy/cz exist and match ic_u/v/w size (input_dust_grafic.f90).
hackathon_grafic_dust_vel_ics_complete() {
  local ic_dir="$1" u_size v_size w_size
  [[ -f "${ic_dir}/ic_u" && -f "${ic_dir}/ic_v" && -f "${ic_dir}/ic_w" &&
     -f "${ic_dir}/ic_velcx" && -f "${ic_dir}/ic_velcy" && -f "${ic_dir}/ic_velcz" ]] || return 1
  u_size="$(hackathon_file_size_bytes "${ic_dir}/ic_u")"
  v_size="$(hackathon_file_size_bytes "${ic_dir}/ic_v")"
  w_size="$(hackathon_file_size_bytes "${ic_dir}/ic_w")"
  [[ "${u_size}" -gt 0 && "${v_size}" -gt 0 && "${w_size}" -gt 0 &&
     "${u_size}" -eq "$(hackathon_file_size_bytes "${ic_dir}/ic_velcx")" &&
     "${v_size}" -eq "$(hackathon_file_size_bytes "${ic_dir}/ic_velcy")" &&
     "${w_size}" -eq "$(hackathon_file_size_bytes "${ic_dir}/ic_velcz")" ]]
}

# Dust grains read ic_velcx/cy/cz in input_dust_grafic.f90. Uniform turb ICs from
# uniform.py omit them; copy hydro velocities (ic_u/v/w) which match the gas flow.
hackathon_ensure_grafic_dust_vel_ics() {
  local ic_dir="$1"
  if hackathon_grafic_dust_vel_ics_complete "${ic_dir}"; then
    echo "== dust velocity ICs OK: ${ic_dir}/ic_velc{x,y,z}"
    return 0
  fi
  if [[ ! -f "${ic_dir}/ic_u" || ! -f "${ic_dir}/ic_v" || ! -f "${ic_dir}/ic_w" ]]; then
    echo "ERROR: cannot install dust velocity ICs; missing ic_u/ic_v/ic_w under ${ic_dir}" >&2
    return 1
  fi
  echo "== installing dust velocity ICs: ic_u/v/w -> ic_velcx/cy/cz in ${ic_dir}"
  cp -f "${ic_dir}/ic_u" "${ic_dir}/ic_velcx"
  cp -f "${ic_dir}/ic_v" "${ic_dir}/ic_velcy"
  cp -f "${ic_dir}/ic_w" "${ic_dir}/ic_velcz"
  if ! hackathon_grafic_dust_vel_ics_complete "${ic_dir}"; then
    echo "ERROR: dust velocity IC install failed under ${ic_dir}" >&2
    ls -la "${ic_dir}"/ic_velc* "${ic_dir}"/ic_u "${ic_dir}"/ic_v "${ic_dir}"/ic_w >&2 || true
    return 1
  fi
  echo "== dust velocity ICs installed ($(hackathon_file_size_bytes "${ic_dir}/ic_velcx") bytes each plane file)"
}

# Brio-Wu MHD shock-tube grafic ICs. Unlike the zoom ICs (downloaded), these are
# generated on the fly by mini-ramses-dev/utils/py/grafic/brio_wu.py if absent.
# Arg 1: refinement level (grid is 2^level along each axis; default 7 -> 128^3).
# Sets IC_DIR to the per-level IC directory.
hackathon_ensure_brio_wu_ics() {
  hackathon_setup_paths
  local level="${1:-7}"
  local n=$((2 ** level))
  local ic_root="${BRIO_WU_IC_ROOT:-${HARNESS_DIR}/ics_brio_wu}"
  local ic_dir="${ic_root}/ic_brio_wu_${level}_3d"
  local gen="${MINIRAM}/utils/py/grafic/brio_wu.py"
  if hackathon_grafic_mhd_ics_complete "${ic_dir}"; then
    echo "== brio-wu ICs present: ${ic_dir} (${n}^3)"
    export IC_DIR="${ic_dir}"
    return 0
  fi
  echo "== brio-wu ICs missing under ${ic_dir}; generating with brio_wu.py (level ${level} -> ${n}^3, 3D)"
  if [[ ! -f "${gen}" ]]; then
    echo "ERROR: brio_wu.py not found at ${gen}" >&2
    echo "       (sync mini-ramses-dev to ${MINIRAM}; it lives in utils/py/grafic/)" >&2
    return 1
  fi
  local py="${PYTHON:-python3}"
  mkdir -p "${ic_dir}"
  # brio_wu.py imports the sibling grafic.py, so run from its own directory;
  # --outdir accepts an absolute path (the script chdir's into it to write files).
  ( cd "$(dirname "${gen}")" && "${py}" "$(basename "${gen}")" "${level}" --ndim 3 --size 1.0 --outdir "${ic_dir}" )
  if [[ ! -f "${ic_dir}/ic_bxleft" ]]; then
    echo "ERROR: brio-wu IC generation failed; expected ${ic_dir}/ic_bxleft" >&2
    ls -la "${ic_dir}" >&2 || true
    return 1
  fi
  echo "== brio-wu ICs installed under ${ic_dir}"
  export IC_DIR="${ic_dir}"
}

# Driven MHD turbulence grafic ICs: a uniform box (uniform rho/p, zero velocity)
# threaded by a uniform magnetic field Bz = 4. Generated on the fly by
# mini-ramses-dev/utils/py/grafic/uniform.py if absent (--bz 4, with rho/p/size
# matching mhd_turb.nml). Arg 1: refinement level (grid is 2^level; default 6 -> 64^3).
# Sets IC_DIR to the per-level IC directory.
hackathon_ensure_mhd_turb_ics() {
  hackathon_setup_paths
  local level="${1:-6}"
  local n=$((2 ** level))
  local ic_root="${MHD_TURB_IC_ROOT:-${HARNESS_DIR}/ics_mhd_turb}"
  local ic_dir="${ic_root}/ic_mhd_turb_${level}_3d"
  local gen="${MINIRAM}/utils/py/grafic/uniform.py"
  # Box / state must match mhd_turb.nml (boxlen, d_region, p_region) and B = 4.
  local size="${MHD_TURB_SIZE:-4.0}"
  local rho="${MHD_TURB_RHO:-0.28954719470909174}"
  local p0="${MHD_TURB_P0:-0.030361026190591216}"
  local bz="${MHD_TURB_BZ:-4}"
  if hackathon_grafic_mhd_ics_complete "${ic_dir}"; then
    echo "== mhd-turb ICs present: ${ic_dir} (${n}^3, Bz=${bz})"
    export IC_DIR="${ic_dir}"
    if [[ "${MHD_TURB_DUST:-0}" == "1" ]]; then
      hackathon_ensure_grafic_dust_vel_ics "${ic_dir}" || return 1
    fi
    return 0
  fi
  echo "== mhd-turb ICs missing under ${ic_dir}; generating with uniform.py (level ${level} -> ${n}^3, 3D, Bz=${bz}, rho=${rho}, p=${p0}, size=${size})"
  if [[ ! -f "${gen}" ]]; then
    echo "ERROR: uniform.py not found at ${gen}" >&2
    echo "       (sync mini-ramses-dev to ${MINIRAM}; it lives in utils/py/grafic/)" >&2
    return 1
  fi
  local py="${PYTHON:-python3}"
  mkdir -p "${ic_dir}"
  # uniform.py imports the sibling grafic.py, so run from its own directory;
  # --outdir accepts an absolute path (the script chdir's into it to write files).
  ( cd "$(dirname "${gen}")" && "${py}" "$(basename "${gen}")" "${level}" --ndim 3 \
      --size "${size}" --rho "${rho}" --p0 "${p0}" --bz "${bz}" --outdir "${ic_dir}" )
  if ! hackathon_grafic_mhd_ics_complete "${ic_dir}"; then
    echo "ERROR: mhd-turb IC generation failed; expected the full grafic MHD set under ${ic_dir}" >&2
    ls -la "${ic_dir}" >&2 || true
    return 1
  fi
  echo "== mhd-turb ICs installed under ${ic_dir}"
  export IC_DIR="${ic_dir}"
  if [[ "${MHD_TURB_DUST:-0}" == "1" ]]; then
    hackathon_ensure_grafic_dust_vel_ics "${ic_dir}" || return 1
  fi
}

# Decaying MHD turbulence grafic ICs: band-limited turbulent velocity from turb.py
# (non-zero ic_u/v/w), uniform rho/p, uniform Bz. Use with turb=.false. in the
# namelist (no stochastic driving). Arg 1: refinement level (2^level cells/axis).
hackathon_ensure_mhd_turb_decay_ics() {
  hackathon_setup_paths
  local level="${1:-8}"
  local n=$((2 ** level))
  local ic_root="${MHD_TURB_IC_ROOT:-${HARNESS_DIR}/ics_mhd_turb}"
  local ic_dir="${ic_root}/ic_mhd_turb_decay_${level}_3d"
  local gen="${MINIRAM}/utils/py/grafic/turb.py"
  local size="${MHD_TURB_SIZE:-4.0}"
  local rho="${MHD_TURB_RHO:-0.28954719470909174}"
  local p0="${MHD_TURB_P0:-0.030361026190591216}"
  local bz="${MHD_TURB_BZ:-4}"
  local vrms="${MHD_TURB_VRMS:-2.0}"
  local kmin="${MHD_TURB_KMIN:-2}"
  local kmax="${MHD_TURB_KMAX:-$((n / 2))}"
  local alpha="${MHD_TURB_ALPHA:-0.5}"
  local spectrum="${MHD_TURB_SPECTRUM:-parabolic}"
  local seed="${MHD_TURB_SEED:-42}"
  if hackathon_grafic_mhd_ics_complete "${ic_dir}"; then
    echo "== mhd-turb-decay ICs present: ${ic_dir} (${n}^3, Bz=${bz}, vrms=${vrms})"
    export IC_DIR="${ic_dir}"
    if [[ "${MHD_TURB_DUST:-0}" == "1" ]]; then
      hackathon_ensure_grafic_dust_vel_ics "${ic_dir}" || return 1
    fi
    return 0
  fi
  echo "== mhd-turb-decay ICs missing under ${ic_dir}; generating with turb.py (level ${level} -> ${n}^3, Bz=${bz}, vrms=${vrms}, k=[${kmin},${kmax}], alpha=${alpha}, spectrum=${spectrum})"
  if [[ ! -f "${gen}" ]]; then
    echo "ERROR: turb.py not found at ${gen}" >&2
    echo "       (sync mini-ramses-dev to ${MINIRAM}; it lives in utils/py/grafic/)" >&2
    return 1
  fi
  local py="${PYTHON:-python3}"
  mkdir -p "${ic_dir}"
  ( cd "$(dirname "${gen}")" && "${py}" "$(basename "${gen}")" "${level}" --ndim 3 \
      --size "${size}" --rho "${rho}" --p0 "${p0}" --bz "${bz}" \
      --kmin "${kmin}" --kmax "${kmax}" --alpha "${alpha}" --vrms "${vrms}" \
      --spectrum "${spectrum}" --seed "${seed}" --outdir "${ic_dir}" )
  if ! hackathon_grafic_mhd_ics_complete "${ic_dir}"; then
    echo "ERROR: mhd-turb-decay IC generation failed; expected the full grafic MHD set under ${ic_dir}" >&2
    ls -la "${ic_dir}" >&2 || true
    return 1
  fi
  echo "== mhd-turb-decay ICs installed under ${ic_dir}"
  export IC_DIR="${ic_dir}"
  if [[ "${MHD_TURB_DUST:-0}" == "1" ]]; then
    hackathon_ensure_grafic_dust_vel_ics "${ic_dir}" || return 1
  fi
}

# Orszag-Tang vortex MHD grafic ICs. Like the brio-wu ICs, these are generated on
# the fly by mini-ramses-dev/utils/py/grafic/orszag_tang.py if absent. The vortex
# is a 2D (x,y) problem laid out in a 3D box uniform along z (z-symmetry).
# Arg 1: refinement level (grid is 2^level along each axis; default 8 -> 256^3).
# Sets IC_DIR to the per-level IC directory.
hackathon_ensure_orszag_tang_ics() {
  hackathon_setup_paths
  local level="${1:-8}"
  local n=$((2 ** level))
  local ic_root="${ORSZAG_TANG_IC_ROOT:-${HARNESS_DIR}/ics_orszag_tang}"
  local ic_dir="${ic_root}/ic_orszag_tang_${level}_3d"
  local gen="${MINIRAM}/utils/py/grafic/orszag_tang.py"
  if hackathon_grafic_mhd_ics_complete "${ic_dir}"; then
    echo "== orszag-tang ICs present: ${ic_dir} (${n}^3)"
    export IC_DIR="${ic_dir}"
    if [[ "${ORSZAG_TANG_DUST:-0}" == "1" ]]; then
      hackathon_ensure_grafic_dust_vel_ics "${ic_dir}" || return 1
    fi
    return 0
  fi
  if [[ -f "${ic_dir}/ic_d" ]]; then
    echo "== orszag-tang ICs under ${ic_dir} are incomplete (hydro-only/stale); regenerating MHD set (ic_bxleft ... ic_bzright)"
  else
    echo "== orszag-tang ICs missing under ${ic_dir}; generating with orszag_tang.py (level ${level} -> ${n}^3, 3D, z-symmetry)"
  fi
  if [[ ! -f "${gen}" ]]; then
    echo "ERROR: orszag_tang.py not found at ${gen}" >&2
    echo "       (sync mini-ramses-dev to ${MINIRAM}; it lives in utils/py/grafic/)" >&2
    return 1
  fi
  local py="${PYTHON:-python3}"
  local dust_flag=()
  if [[ "${ORSZAG_TANG_DUST:-0}" == "1" ]]; then
    dust_flag=(--dust)
    echo "== orszag-tang dust ICs: will write flow-coupled ic_velcx/cy/cz (set ORSZAG_TANG_DUST=0 to skip)"
  fi
  mkdir -p "${ic_dir}"
  # orszag_tang.py imports the sibling grafic.py, so run from its own directory;
  # --outdir accepts an absolute path (the script chdir's into it to write files).
  ( cd "$(dirname "${gen}")" && "${py}" "$(basename "${gen}")" "${level}" --ndim 3 --size 1.0 "${dust_flag[@]}" --outdir "${ic_dir}" )
  if [[ ! -f "${ic_dir}/ic_bxleft" ]]; then
    echo "ERROR: orszag-tang IC generation failed; expected ${ic_dir}/ic_bxleft" >&2
    ls -la "${ic_dir}" >&2 || true
    return 1
  fi
  echo "== orszag-tang ICs installed under ${ic_dir}"
  export IC_DIR="${ic_dir}"
  if [[ "${ORSZAG_TANG_DUST:-0}" == "1" ]]; then
    hackathon_ensure_grafic_dust_vel_ics "${ic_dir}" || return 1
  fi
}

# Orszag-Tang MHD grafic ICs with checkerboard passive scalar (ot-pscal). Generated
# by hackathon/orszag_tang_pscal.py if absent. Arg 1: level (default 5 for ot-amr base).
hackathon_ensure_ot_pscal_ics() {
  hackathon_setup_paths
  local level="${1:-5}"
  local n=$((2 ** level))
  local ic_root="${OT_PSCAL_IC_ROOT:-${HARNESS_DIR}/ics_orszag_tang_pscal}"
  local ic_dir="${ic_root}/ic_ot_pscal_${level}_3d"
  local gen="${HARNESS_DIR}/orszag_tang_pscal.py"
  hackathon_fix_pscal_ic_name "${ic_dir}"
  if hackathon_grafic_mhd_pscal_ics_complete "${ic_dir}"; then
    echo "== ot-pscal ICs present: ${ic_dir} (${n}^3)"
    export IC_DIR="${ic_dir}"
    return 0
  fi
  if [[ -f "${ic_dir}/ic_d" ]]; then
    echo "== ot-pscal ICs under ${ic_dir} are incomplete (missing ic_pvar_00001 or B files); regenerating"
  else
    echo "== ot-pscal ICs missing under ${ic_dir}; generating with orszag_tang_pscal.py (level ${level} -> ${n}^3, 3D)"
  fi
  if [[ ! -f "${gen}" ]]; then
    echo "ERROR: orszag_tang_pscal.py not found at ${gen}" >&2
    return 1
  fi
  local grafic_py="${MINIRAM}/utils/py/grafic/grafic.py"
  if [[ ! -f "${grafic_py}" ]]; then
    echo "ERROR: grafic.py not found at ${grafic_py}" >&2
    echo "       Sync mini-ramses-dev to MINIRAM=${MINIRAM} (or set MINIRAM= before submit)." >&2
    return 1
  fi
  local py="${PYTHON:-python3}"
  mkdir -p "${ic_dir}"
  export MINIRAM
  MINIRAM="${MINIRAM}" PYTHONPATH="${MINIRAM}/utils/py/grafic${PYTHONPATH:+:${PYTHONPATH}}" \
    "${py}" "${gen}" "${level}" --size 1.0 --outdir "${ic_dir}"
  if [[ ! -f "${ic_dir}/ic_pvar_00001" ]]; then
    echo "ERROR: ot-pscal IC generation failed; expected ${ic_dir}/ic_pvar_00001" >&2
    ls -la "${ic_dir}" >&2 || true
    return 1
  fi
  echo "== ot-pscal ICs installed under ${ic_dir}"
  export IC_DIR="${ic_dir}"
}

# RAMSES initfile is character*80; input_hydro_grafic.f90 appends suffixes like
# /ic_bxright (10 chars). Long absolute paths truncate silently (ic_bxleft -> ic_bxlef).
hackathon_grafic_ic_link_name() {
  echo "ic_grafic"
}

hackathon_stage_grafic_ic_symlink() {
  local ic_dir="$1"
  local workdir="$2"
  local link_name
  link_name="$(hackathon_grafic_ic_link_name)"
  local link_path="${workdir}/${link_name}"
  if [[ ! -d "${ic_dir}" ]]; then
    echo "ERROR: missing IC directory: ${ic_dir}" >&2
    return 1
  fi
  rm -f "${link_path}"
  ln -sfn "${ic_dir}" "${link_path}"
  echo "== grafic IC symlink: ${link_path} -> ${ic_dir}"
}

# Stage dmo_gpu input.nml: grafic (single initfile) or grafic_zoom (four levels).
hackathon_stage_dmo_run_nml() {
  local template_nml="$1" out_nml="$2"
  if grep -qE "filetype=['\"]grafic_zoom['\"]" "${template_nml}"; then
    hackathon_ensure_zoom_ics "${IC_ZOOM_DIR}"
    sed "s|__ZOOM_IC_DIR__|${IC_ZOOM_DIR}|g" "${template_nml}" > "${out_nml}"
  else
    local workdir ic_init
    workdir="$(dirname "${out_nml}")"
    hackathon_stage_grafic_ic_symlink "${IC_DIR}" "${workdir}"
    ic_init="$(hackathon_grafic_ic_link_name)"
    sed "s|^[[:space:]]*initfile(1)=.*| initfile(1)='${ic_init}'|" "${template_nml}" > "${out_nml}"
  fi
}

hackathon_load_modules() {
  hackathon_init_modules 2>/dev/null || true
  module unload cudatoolkit 2>/dev/null || true
  local mod nvhpc_mod="${NVHPC_MODULE:-nvhpc/25.5}"
  if [[ -n "${CLUSTER_GPU_MODULES:-}" ]]; then
    for mod in ${CLUSTER_GPU_MODULES}; do
      if ! module load "${mod}" 2>/dev/null; then
        if [[ "${mod}" == nvhpc/* || "${mod}" == nvhpc ]]; then
          echo "WARNING: module load ${mod} failed" >&2
        fi
      fi
    done
  elif [[ "${NVHPC_MODULE_STRICT:-0}" == "1" ]]; then
    unset LOADEDMODULES _LMFILES_ MPICC MPIF90 MPI_HOME 2>/dev/null || true
    module purge 2>/dev/null || true
    if ! module load "${nvhpc_mod}"; then
      echo "ERROR: required NVHPC module not loaded: ${nvhpc_mod}" >&2
      return 1
    fi
    echo "== NVHPC module (strict): ${nvhpc_mod}"
    nvfortran --version 2>/dev/null | head -1 || true
  elif ! module load nvhpc/25.5 2>/dev/null; then
    module load nvhpc/21.1 2>/dev/null || module load nvhpc 2>/dev/null || true
  fi
  if [[ -z "${NVHPC_CUDA_HOME:-}" ]]; then
    local candidate
    for candidate in \
        "/opt/nvidia/hpc_sdk/Linux_x86_64/"*/cuda/* \
        "/cm/shared/apps/nvhpc/"*/Linux_x86_64/*/cuda/*; do
      if [[ -d "${candidate}" ]]; then
        export NVHPC_CUDA_HOME="${candidate}"
        break
      fi
    done
  fi
  if [[ -n "${NVHPC_CUDA_HOME:-}" ]]; then
    local nvhpc_sdk_root nvhpc_math_lib
    nvhpc_sdk_root="$(cd "$(dirname "${NVHPC_CUDA_HOME}")/../.." && pwd)"
    nvhpc_math_lib="${nvhpc_sdk_root}/math_libs/lib64"
    if [[ -d "${nvhpc_math_lib}" ]]; then
      export NVHPC_MATH_LIB="${nvhpc_math_lib}"
      export LD_LIBRARY_PATH="${nvhpc_math_lib}:${NVHPC_CUDA_HOME}/lib64:${LD_LIBRARY_PATH:-}"
    fi
  fi
  export CUDA_VISIBLE_DEVICES=0
  export NVCOMPILER_TERM=trace
  export NVCOMPILER_FPE=
}

# Ensure Environment Modules works in non-interactive SLURM/bash shells.
# Do not skip init just because `module` is on PATH — batch jobs often inherit
# a broken stub without MODULEPATH (common cause of silent module load failures).
hackathon_init_modules() {
  local init sourced=0
  for init in \
      /usr/share/Modules/init/bash \
      /etc/profile.d/modules.sh \
      /usr/local/Modules/init/bash \
      /opt/apps/lmod/lmod/init/bash; do
    if [[ -f "${init}" ]]; then
      # shellcheck source=/dev/null
      source "${init}"
      sourced=1
      break
    fi
  done
  if [[ "${sourced}" -eq 0 ]] && ! command -v module >/dev/null 2>&1; then
    return 1
  fi
  if [[ -z "${MODULEPATH:-}" ]]; then
    export MODULEPATH="/usr/local/share/Modules/modulefiles:/usr/share/Modules/modulefiles"
  fi
  return 0
}

hackathon_modulecmd() {
  if [[ -n "${MODULESHOME:-}" && -x "${MODULESHOME}/bin/modulecmd" ]]; then
    echo "${MODULESHOME}/bin/modulecmd"
    return 0
  fi
  if [[ -x /usr/share/Modules/bin/modulecmd ]]; then
    echo /usr/share/Modules/bin/modulecmd
    return 0
  fi
  if command -v modulecmd >/dev/null 2>&1; then
    command -v modulecmd
    return 0
  fi
  return 1
}

# Apply module load/unload via modulecmd + eval (reliable under sbatch).
# Only stdout from modulecmd is shell code; stderr has "Loading ..." messages.
hackathon_eval_module() {
  local action="$1"
  shift
  local modcmd out err rc=0
  hackathon_init_modules || return 1
  modcmd="$(hackathon_modulecmd)" || return 1
  err="$(mktemp)"
  out="$("${modcmd}" bash "${action}" "$@" 2>"${err}")" || rc=$?
  if [[ "${rc}" -ne 0 ]]; then
    echo "WARNING: module ${action} $* failed (rc=${rc})" >&2
    sed -n '1,12p' "${err}" >&2 || true
    rm -f "${err}"
    return "${rc}"
  fi
  rm -f "${err}"
  if [[ -n "${out}" ]]; then
    eval "${out}"
  fi
  return 0
}

# Login-node module load (avoid modulecmd eval quirks when building).
hackathon_module_load() {
  hackathon_init_modules || return 1
  module load "$@"
}

# Paths that look like */include but are not FFTW (NVHPC comm_libs / nvshmem on CPATH).
hackathon_fftw_suspicious_prefix() {
  case "$1" in
    *nvshmem*|*/comm_libs/*|*/comm_libs|*/cudalib/*)
      return 0
      ;;
  esac
  return 1
}

# True when prefix has linkable libfftw3.
hackathon_fftw_has_libs() {
  local root="$1" libdir=""
  [[ -n "${root}" ]] || return 1
  for libdir in "${root}/lib64" "${root}/lib"; do
    [[ -d "${libdir}" ]] || continue
    compgen -G "${libdir}/libfftw3"*.so* >/dev/null 2>&1 && return 0
    compgen -G "${libdir}/libfftw3"*.a >/dev/null 2>&1 && return 0
    [[ -f "${libdir}/libfftw3.so" || -f "${libdir}/libfftw3.a" ]] && return 0
  done
  return 1
}

# True when root looks like an FFTW install prefix (headers and/or libfftw3).
hackathon_fftw_valid_prefix() {
  local root="$1"
  [[ -n "${root}" && -d "${root}/include" ]] || return 1
  hackathon_fftw_suspicious_prefix "${root}" && return 1
  [[ -f "${root}/include/fftw3.h" || -f "${root}/include/fftw3.f" ]] && return 0
  compgen -G "${root}/include/fftw3"*.h >/dev/null 2>&1 && return 0
  compgen -G "${root}/include/fftw3"*.f* >/dev/null 2>&1 && return 0
  hackathon_fftw_has_libs "${root}"
}

# Last whitespace-separated field on a module show line (the path).
hackathon_module_show_last_field() {
  local line="$1"
  line="${line#"${line%%[![:space:]]*}"}"
  printf '%s' "${line##*[[:space:]]}"
}

# Derive prefix from a lib/ or lib64/ directory that contains libfftw3.
hackathon_fftw_prefix_from_libdir() {
  local libdir="$1" root
  [[ -n "${libdir}" && -d "${libdir}" ]] || return 1
  if compgen -G "${libdir}/libfftw3"*.so* >/dev/null 2>&1 || \
     compgen -G "${libdir}/libfftw3"*.a >/dev/null 2>&1 || \
     [[ -f "${libdir}/libfftw3.so" || -f "${libdir}/libfftw3.a" ]]; then
    root="$(dirname "${libdir}")"
    hackathon_fftw_suspicious_prefix "${root}" && return 1
    if hackathon_fftw_valid_prefix "${root}"; then
      printf '%s' "${root}"
      return 0
    fi
  fi
  return 1
}

# Scan a colon-separated path list (CPATH, LD_LIBRARY_PATH, ...) for FFTW prefix.
hackathon_fftw_prefix_from_pathvar() {
  local _paths entry prefix="" parent=""
  [[ -n "$1" ]] || return 1
  IFS=':' read -ra _paths <<< "$1"
  for entry in "${_paths[@]}"; do
    [[ -z "${entry}" ]] && continue
    if [[ "${entry}" == */include && -d "${entry}" ]]; then
      parent="${entry%/include}"
      hackathon_fftw_suspicious_prefix "${parent}" && continue
      if hackathon_fftw_valid_prefix "${parent}"; then
        printf '%s' "${parent}"
        return 0
      fi
    fi
    if [[ -f "${entry}/fftw3.h" || -f "${entry}/fftw3.f" ]]; then
      prefix="$(dirname "${entry}")"
      if hackathon_fftw_valid_prefix "${prefix}"; then
        printf '%s' "${prefix}"
        return 0
      fi
    fi
    if prefix="$(hackathon_fftw_prefix_from_libdir "${entry}")"; then
      printf '%s' "${prefix}"
      return 0
    fi
  done
  return 1
}

# Resolve FFTW install prefix from environment after module load.
hackathon_fftw_prefix_from_env() {
  local root prefix
  for root in \
      "${FFTW:-}" "${FFTW3DIR:-}" "${FFTW_PATH:-}" \
      "${FFTW_ROOT:-}" "${FFTW_DIR:-}" "${FFTW_HOME:-}" "${EBROOTFFTW:-}"; do
    hackathon_fftw_suspicious_prefix "${root}" && continue
    if hackathon_fftw_valid_prefix "${root}"; then
      printf '%s' "${root}"
      return 0
    fi
    # Trust module-set FFTW3DIR/FFTW_PATH when libfftw3 is present.
    if [[ -n "${root}" && -d "${root}/include" ]] && hackathon_fftw_has_libs "${root}"; then
      if [[ "${root}" == "${FFTW3DIR:-}" || "${root}" == "${FFTW_PATH:-}" ]]; then
        printf '%s' "${root}"
        return 0
      fi
    fi
  done
  for prefix in \
      "$(hackathon_fftw_prefix_from_pathvar "${LIBRARY_PATH:-}")" \
      "$(hackathon_fftw_prefix_from_pathvar "${LD_LIBRARY_PATH:-}")" \
      "$(hackathon_fftw_prefix_from_pathvar "${CPATH:-}")" \
      "$(hackathon_fftw_prefix_from_pathvar "${C_INCLUDE_PATH:-}")" \
      "$(hackathon_fftw_prefix_from_pathvar "${INCLUDE:-}")"; do
    [[ -n "${prefix}" ]] || continue
    hackathon_fftw_suspicious_prefix "${prefix}" && continue
    if hackathon_fftw_valid_prefix "${prefix}" && hackathon_fftw_has_libs "${prefix}"; then
      printf '%s' "${prefix}"
      return 0
    fi
  done
  return 1
}

# After fftw module load: prefer module vars over CPATH (nvshmem false positives).
hackathon_fftw_prefix_after_module() {
  local loaded="$1" prefix=""
  if [[ -n "${FFTW3DIR:-}" && -d "${FFTW3DIR}/include" ]] && hackathon_fftw_has_libs "${FFTW3DIR}"; then
    printf '%s' "${FFTW3DIR}"
    return 0
  fi
  if [[ -n "${FFTW_PATH:-}" && -d "${FFTW_PATH}/include" ]] && hackathon_fftw_has_libs "${FFTW_PATH}"; then
    printf '%s' "${FFTW_PATH}"
    return 0
  fi
  if prefix="$(hackathon_fftw_prefix_from_module_show "${loaded}" 2>/dev/null || true)"; then
    [[ -n "${prefix}" ]] && printf '%s' "${prefix}" && return 0
  fi
  if prefix="$(hackathon_fftw_stellar_fallback_prefix 2>/dev/null || true)"; then
    [[ -n "${prefix}" ]] && printf '%s' "${prefix}" && return 0
  fi
  if prefix="$(hackathon_fftw_prefix_from_env)"; then
    [[ -n "${prefix}" ]] && printf '%s' "${prefix}" && return 0
  fi
  return 1
}

# Parse module show for FFTW paths when env vars are not set post-load.
hackathon_fftw_prefix_from_module_show() {
  local mod="$1" modcmd line val inc libdir prefix=""
  modcmd="$(hackathon_modulecmd)" || return 1
  while IFS= read -r line; do
    case "${line}" in
      *setenv*FFTW3DIR*|*setenv*FFTW_PATH*|\
      *setenv*FFTW_ROOT*|*setenv*FFTW_DIR*|*setenv*FFTW_HOME*|*setenv*EBROOTFFTW*)
        val="$(hackathon_module_show_last_field "${line}")"
        val="$(hackathon_module_strip_path "${val}")"
        if [[ -n "${val}" && -d "${val}/include" && ( -d "${val}/lib64" || -d "${val}/lib" ) ]]; then
          printf '%s' "${val}"
          return 0
        fi
        ;;
      *append-path*CPATH*|*prepend-path*CPATH*|\
      *append-path*C_INCLUDE_PATH*|*prepend-path*C_INCLUDE_PATH*|\
      *append-path*INCLUDE*|*prepend-path*INCLUDE*)
        inc="$(hackathon_module_show_last_field "${line}")"
        inc="$(hackathon_module_strip_path "${inc}")"
        if [[ "${inc}" == */include && -d "${inc}" ]]; then
          prefix="${inc%/include}"
          printf '%s' "${prefix}"
          return 0
        fi
        ;;
      *append-path*LD_LIBRARY_PATH*|*prepend-path*LD_LIBRARY_PATH*|\
      *append-path*LIBRARY_PATH*|*prepend-path*LIBRARY_PATH*)
        libdir="$(hackathon_module_show_last_field "${line}")"
        libdir="$(hackathon_module_strip_path "${libdir}")"
        if prefix="$(hackathon_fftw_prefix_from_libdir "${libdir}")"; then
          printf '%s' "${prefix}"
          return 0
        fi
        if [[ -n "${libdir}" && "${libdir}" == */lib64 ]]; then
          prefix="${libdir%/lib64}"
          [[ -d "${prefix}/include" ]] && printf '%s' "${prefix}" && return 0
        fi
        ;;
    esac
  done < <("${modcmd}" bash show "${mod}" 2>/dev/null || true)
  return 1
}

# Stellar/Princeton FFTW install roots (fallback after module load).
hackathon_fftw_stellar_fallback_prefix() {
  local candidate
  for candidate in \
      /usr/local/fftw/nvhpc-21.5/3.3.9 \
      /usr/local/fftw/gcc/3.3.9 \
      /usr/licensed/fftw/nvhpc-21.5/3.3.9 \
      /usr/local/fftw/nvhpc/3.3.9 \
      /usr/licensed/fftw/nvhpc/3.3.9 \
      /usr/local/fftw/gcc/3.3.9; do
    if [[ -d "${candidate}/include" && ( -d "${candidate}/lib64" || -d "${candidate}/lib" ) ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}

# Harness-shipped fftw3.f (FFTW 3.3.10 api/fftw3.f) when cluster module lacks Fortran headers.
hackathon_fftw_vendor_inc() {
  local d
  for d in \
      "${HARNESS_DIR:-}/vendor/fftw" \
      "${SLURM_SUBMIT_DIR:-}/vendor/fftw" \
      "${SCRIPT_DIR:-}/vendor/fftw"; do
    [[ -n "${d}" && -f "${d}/fftw3.f" ]] || continue
    printf '%s' "${d}"
    return 0
  done
  return 1
}

# Copy fftw3.f into MINIRAM/bin/.fftw_include (compute nodes may lack /usr/local/fftw headers).
hackathon_stage_fftw_header() {
  local fftw_prefix="$1" vendor_inc="${2:-}" dest src
  dest="${MINIRAM}/bin/.fftw_include"
  mkdir -p "${dest}"
  for src in \
      "${fftw_prefix}/include/fftw3.f" \
      "${vendor_inc:+${vendor_inc}/fftw3.f}" \
      "${HARNESS_DIR:-}/vendor/fftw/fftw3.f" \
      "${SLURM_SUBMIT_DIR:-}/vendor/fftw/fftw3.f" \
      "${HOME}/hackathon/vendor/fftw/fftw3.f" \
      /usr/local/fftw/nvhpc-21.5/3.3.9/include/fftw3.f \
      /usr/local/fftw/gcc/3.3.9/include/fftw3.f; do
    [[ -n "${src}" && -f "${src}" ]] || continue
    cp -f "${src}" "${dest}/fftw3.f"
    echo "== staged fftw3.f: ${src} -> ${dest}/fftw3.f" >&2
    printf '%s' "${dest}"
    return 0
  done
  echo "ERROR: could not find fftw3.f to stage (FFTW=${fftw_prefix} vendor=${vendor_inc:-unset})" >&2
  return 1
}

# True when dry-run output includes FFTW include paths (avoid grep -F: -I... looks like flags).
hackathon_dryrun_has_turb_inc() {
  local dry_run="$1" gpu_fftw="$2" gpu_fftw_vendor="$3" gpu_header_dir="${4:-}"
  [[ -n "${gpu_header_dir}" && "${dry_run}" == *"-I${gpu_header_dir}"* ]] && return 0
  [[ "${dry_run}" == *"-I${gpu_fftw}/include"* ]] && return 0
  [[ -n "${gpu_fftw_vendor}" && "${dry_run}" == *"-I${gpu_fftw_vendor}"* ]] && return 0
  return 1
}

# Pick an FFTW prefix for link/runtime; Fortran #include may use harness vendor/fftw3.f.
hackathon_fftw_finalize_prefix() {
  local prefix="$1" alt vendor link_prefix
  [[ -n "${prefix}" ]] || return 1
  link_prefix="${prefix}"
  unset FFTW_VENDOR_INC
  if hackathon_fftw_suspicious_prefix "${link_prefix}" || ! hackathon_fftw_has_libs "${link_prefix}"; then
    if alt="$(hackathon_fftw_stellar_fallback_prefix 2>/dev/null || true)"; then
      echo "WARNING: rejecting FFTW prefix ${link_prefix} (not libfftw3); using ${alt}" >&2
      link_prefix="${alt}"
    else
      echo "ERROR: FFTW prefix ${link_prefix} has no libfftw3 and no Stellar fallback found." >&2
      return 1
    fi
  fi
  if [[ -f "${link_prefix}/include/fftw3.f" ]]; then
    printf '%s' "${link_prefix}"
    return 0
  fi
  for alt in /usr/local/fftw/nvhpc-21.5/3.3.9 /usr/local/fftw/gcc/3.3.9; do
    if [[ -f "${alt}/include/fftw3.f" ]]; then
      if [[ "${alt}" != "${link_prefix}" ]]; then
        echo "== FFTW headers from ${alt}/include (link ${link_prefix})" >&2
        export FFTW_VENDOR_INC="${alt}/include"
      fi
      printf '%s' "${link_prefix}"
      return 0
    fi
  done
  if vendor="$(hackathon_fftw_vendor_inc)"; then
    export FFTW_VENDOR_INC="${vendor}"
    echo "== FFTW headers from harness ${vendor}/fftw3.f (link ${link_prefix}; module include not visible here)" >&2
    printf '%s' "${link_prefix}"
    return 0
  fi
  echo "ERROR: TURB=1 needs fftw3.f (Fortran FFTW interface)." >&2
  echo "       ls ${link_prefix}/include/fftw3*  # diagnose on login node" >&2
  echo "       Sync harness vendor/fftw/fftw3.f or try FFTW_MODULE=fftw/nvhpc-21.5/3.3.9" >&2
  return 1
}

# Load FFTW module and export FFTW= for TURB=1 Makefile builds + runtime.
# Override module name with FFTW_MODULE=; override prefix with FFTW= if already known.
hackathon_load_fftw() {
  local mod loaded="" prefix mods=()
  if [[ -n "${FFTW:-}" ]]; then
    if hackathon_fftw_suspicious_prefix "${FFTW}" || ! hackathon_fftw_has_libs "${FFTW}"; then
      echo "WARNING: ignoring invalid FFTW=${FFTW}; reloading via fftw module" >&2
      unset FFTW
    elif prefix="$(hackathon_fftw_finalize_prefix "${FFTW}")"; then
      export FFTW="${prefix}"
      echo "== FFTW prefix (existing env): ${FFTW}${FFTW_VENDOR_INC:+ (vendor inc ${FFTW_VENDOR_INC})}"
      return 0
    else
      unset FFTW
    fi
  fi

  if [[ -n "${FFTW_MODULE:-}" ]]; then
    mods+=("${FFTW_MODULE}")
  elif [[ -n "${FFTW_MODULE_DEFAULT:-}" ]]; then
    mods+=("${FFTW_MODULE_DEFAULT}")
  else
    mods+=("fftw/nvhpc-21.5/3.3.9" "fftw/gcc/3.3.9" "fftw/3.3.9" "fftw")
  fi

  for mod in "${mods[@]}"; do
    if hackathon_eval_module load "${mod}" 2>/dev/null || hackathon_module_load "${mod}" 2>/dev/null; then
      loaded="${mod}"
      break
    fi
  done

  if [[ -z "${loaded}" ]]; then
    echo "ERROR: TURB=1 needs FFTW; could not load module (tried: ${mods[*]})." >&2
    echo "       Run: module avail fftw" >&2
    echo "       Or:  FFTW=/path/to/fftw ./submit_profiles.sh mhd-turb" >&2
    return 1
  fi

  if prefix="$(hackathon_fftw_prefix_after_module "${loaded}")"; then
    prefix="$(hackathon_fftw_finalize_prefix "${prefix}")" || return 1
    export FFTW="${prefix}"
    echo "== FFTW: module ${loaded} -> FFTW=${FFTW}${FFTW_VENDOR_INC:+ (vendor inc ${FFTW_VENDOR_INC})}"
    return 0
  fi

  echo "ERROR: TURB=1 needs FFTW; module ${loaded} loaded but prefix unknown." >&2
  echo "       Debug: module show ${loaded}" >&2
  echo "       CPATH=${CPATH:-<unset>}" >&2
  echo "       LD_LIBRARY_PATH=${LD_LIBRARY_PATH:-<unset>}" >&2
  echo "       Or:  FFTW=/path/to/fftw ./submit_profiles.sh mhd-turb" >&2
  return 1
}

# Strip braces/quotes from modulefile paths: {/path/to/bin} -> /path/to/bin
hackathon_module_strip_path() {
  local p="$1"
  p="${p#\"}"
  p="${p%\"}"
  p="${p#\{}"
  p="${p%\}}"
  printf '%s' "${p}"
}

# Collect candidate OpenMPI bin dirs from module show + post-load env vars.
hackathon_openmpi_bindirs_from_module() {
  local mod="$1" modcmd line bindir val
  modcmd="$(hackathon_modulecmd)" || return 1
  while IFS= read -r line; do
    case "${line}" in
      *prepend-path*PATH*)
        bindir="${line#*PATH}"
        bindir="${bindir#"${bindir%%[![:space:]]*}"}"
        bindir="${bindir%%[[:space:]]*}"
        bindir="$(hackathon_module_strip_path "${bindir}")"
        [[ -n "${bindir}" ]] && printf '%s\n' "${bindir}"
        ;;
      *setenv*EBROOTOPENMPI*|*setenv*OPENMPI_ROOT*|*setenv*OMPI_HOME*|\
      *setenv*MPIHOME*|*setenv*MPI_HOME*|*setenv*OPENMPI_HOME*)
        val="${line#*setenv[[:space:]]}"
        val="${val#*[[:space:]]}"
        val="$(hackathon_module_strip_path "${val%%[[:space:]]*}")"
        [[ -n "${val}" ]] && printf '%s/bin\n' "${val}"
        ;;
    esac
  done < <("${modcmd}" bash show "${mod}" 2>/dev/null || module show "${mod}" 2>/dev/null || true)
}

hackathon_find_mpif90() {
  local strict=0 bindir path cand
  if [[ "${1:-}" == "--strict" ]]; then
    strict=1
    shift
  fi
  for bindir in "$@"; do
    [[ -z "${bindir}" ]] && continue
    bindir="$(hackathon_module_strip_path "${bindir}")"
    for path in "${bindir}/mpif90" "${bindir}/mpifort"; do
      if [[ -x "${path}" ]]; then
        echo "${path}"
        return 0
      fi
    done
  done
  for bindir in \
      "${EBROOTOPENMPI:-}/bin" "${EBROOTOPENMPI:-}/gcc/bin" \
      "${OPENMPI_ROOT:-}/bin" "${OPENMPI_ROOT:-}/gcc/bin" \
      "${OMPI_HOME:-}/bin" "${OMPI_HOME:-}/gcc/bin"; do
    [[ -z "${bindir}" || "${bindir}" == "/bin" || "${bindir}" == "/gcc/bin" ]] && continue
    for path in "${bindir}/mpif90" "${bindir}/mpifort"; do
      if [[ -x "${path}" ]]; then
        echo "${path}"
        return 0
      fi
    done
  done
  if [[ "${strict}" -eq 1 ]]; then
    return 1
  fi
  for cand in mpif90 mpifort; do
    if command -v "${cand}" >/dev/null 2>&1; then
      path="$(command -v "${cand}")"
      if [[ -x "${path}" ]]; then
        echo "${path}"
        return 0
      fi
    fi
  done
  return 1
}

hackathon_diag_openmpi_bindirs() {
  local mod="$1" bindir
  echo "== OpenMPI bindir probe for ${mod}:"
  while IFS= read -r bindir; do
    [[ -z "${bindir}" ]] && continue
    if [[ -d "${bindir}" ]]; then
      echo "   dir OK  ${bindir}: $(ls "${bindir}"/mpi* 2>/dev/null | tr '\n' ' ' || echo '(empty)')"
    else
      echo "   MISSING ${bindir}"
    fi
  done < <(hackathon_openmpi_bindirs_from_module "${mod}")
}

# Reset inherited GPU/login module state (LOADEDMODULES + nvhpc on PATH breaks CPU MPI).
hackathon_reset_cpu_job_env() {
  hackathon_init_modules || return 1
  unset LOADEDMODULES _LMFILES_ MODULES_LMALTNAME MODULES_LMPATH MODULES_LMCONFLICT
  export LOADEDMODULES=""
  export _LMFILES_=""
  hackathon_unload_openmpi_modules
  hackathon_eval_module purge 2>/dev/null || true
  hackathon_unload_openmpi_modules
  unset LOADEDMODULES _LMFILES_
  export LOADEDMODULES=""
  export _LMFILES_=""
  unset NVHPC_CUDA_HOME CUDA_HOME CUDACXX NVCOMPILER_TERM CRAY_LD_LIBRARY_PATH
  local p newpath=""
  IFS=':' read -ra parts <<< "${PATH:-}"
  for p in "${parts[@]}"; do
    [[ -z "${p}" ]] && continue
    case "${p}" in
      *nvhpc*|*NVHPC*|*cuda*|*/condabin*)
        continue
        ;;
    esac
    newpath="${newpath:+$newpath:}${p}"
  done
  PATH="${newpath}"
  export PATH
  hackathon_clear_stale_mpi_env
}

# Clear login-node OpenMPI env that breaks on Stellar compute (/usr/local not mounted).
hackathon_clear_stale_mpi_env() {
  local var val p newpath=""
  for var in MPICC MPIF90 MPIFORT MPI_HOME OPENMPI_HOME OPENMPI_PREFIX OMPI_HOME \
             EBROOTOPENMPI OPENMPI_DIR OPENMPI_ROOT; do
    val="${!var:-}"
    [[ -z "${val}" ]] && continue
    case "${val}" in
      /usr/local/openmpi/*)
        unset "${var}"
        ;;
      *)
        if [[ ! -x "${val}" && ! -d "${val}" ]]; then
          unset "${var}"
        fi
        ;;
    esac
  done
  if [[ "${PATH}" == *"/usr/local/openmpi/"* ]]; then
    IFS=':' read -ra _path_parts <<< "${PATH}"
    for p in "${_path_parts[@]}"; do
      [[ -z "${p}" ]] && continue
      case "${p}" in
        /usr/local/openmpi/*)
          if [[ ! -x "${p}/mpif90" && ! -x "${p}/mpicc" ]]; then
            continue
          fi
          ;;
      esac
      newpath="${newpath:+$newpath:}${p}"
    done
    PATH="${newpath}"
    export PATH
  fi
  if [[ "${LD_LIBRARY_PATH:-}" == *"/usr/local/openmpi/"* ]]; then
    newpath=""
    IFS=':' read -ra _ld_parts <<< "${LD_LIBRARY_PATH}"
    for p in "${_ld_parts[@]}"; do
      [[ -z "${p}" ]] && continue
      case "${p}" in
        /usr/local/openmpi/*)
          [[ -d "${p}" ]] || continue
          ;;
      esac
      newpath="${newpath:+$newpath:}${p}"
    done
    LD_LIBRARY_PATH="${newpath}"
    export LD_LIBRARY_PATH
  fi
}

hackathon_unload_openmpi_modules() {
  local mod n=0
  if ! command -v module >/dev/null 2>&1; then
    return 0
  fi
  hackathon_init_modules 2>/dev/null || true
  # Unload versioned stacks first (Stellar login often has openmpi/gcc/4.1.2
  # preloaded, which conflicts with openmpi/gcc-toolset-10/4.1.0 + gcc-toolset/10).
  for mod in \
      openmpi/gcc/4.1.2 \
      openmpi/gcc/4.1.6 \
      openmpi/gcc/4.1.0 \
      openmpi/gcc-toolset-10/4.1.0 \
      openmpi/gcc \
      openmpi/gcc-toolset-10 \
      openmpi; do
    while module unload "${mod}" 2>/dev/null; do
      n=$((n + 1))
      [[ "${n}" -ge 24 ]] && return 0
    done
  done
}

# Resolve mpif90/mpifort (full path). Honors MPIF90, MPICC, module-set env vars,
# OPENMPI_PREFIX, and /usr/local/openmpi (login nodes only on Stellar).
hackathon_resolve_mpif90() {
  local cand path bindir prefix

  for cand in "${MPIF90:-}" "${MPIFORT:-}" mpif90 mpifort; do
    if [[ -n "${cand}" ]]; then
      case "${cand}" in
        /usr/local/openmpi/*)
          [[ -x "${cand}" ]] || continue
          ;;
      esac
      if [[ -x "${cand}" ]]; then
        echo "${cand}"
        return 0
      fi
      if command -v "${cand}" >/dev/null 2>&1; then
        path="$(command -v "${cand}")"
        if [[ -x "${path}" ]]; then
          echo "${path}"
          return 0
        fi
      fi
    fi
  done

  for cand in "${MPICC:-}"; do
    [[ -z "${cand}" ]] && continue
    case "${cand}" in
      /usr/local/openmpi/*)
        [[ -x "${cand}" ]] || continue
        ;;
    esac
    if [[ -x "${cand}" ]]; then
      bindir="$(dirname "${cand}")"
      for path in "${bindir}/mpif90" "${bindir}/mpifort"; do
        if [[ -x "${path}" ]]; then
          echo "${path}"
          return 0
        fi
      done
    fi
  done

  for prefix in \
      "${EBROOTOPENMPI:-}" \
      "${OPENMPI_DIR:-}" \
      "${OMPI_HOME:-}" \
      "${MPI_HOME:-}" \
      "${OPENMPI_ROOT:-}" \
      "${OPENMPI_PREFIX:-}" \
      /usr/local/openmpi/4.1.0/gcc-toolset-10 \
      /usr/local/openmpi/4.1.0/gcc \
      /usr/local/openmpi/4.1.6/gcc \
      /usr/local/openmpi/4.1.2/gcc; do
    [[ -z "${prefix}" ]] && continue
    for path in "${prefix}/bin/mpif90" "${prefix}/bin/mpifort"; do
      if [[ -x "${path}" ]]; then
        echo "${path}"
        return 0
      fi
    done
  done
  return 1
}

hackathon_dump_mpi_env() {
  echo "== MPI-related environment:" >&2
  env | grep -iE '^(MPI|OMPI|OPENMPI|EBROOT|I_MPI|PMIX)' | sort >&2 || true
  echo "== which mpif90 mpifort mpicc:" >&2
  which mpif90 mpifort mpicc 2>&1 >&2 || true
}

hackathon_probe_openmpi_paths() {
  local prefix="${OPENMPI_PREFIX:-/usr/local/openmpi/4.1.2/gcc}"
  local path
  echo "== OpenMPI probe (OPENMPI_PREFIX=${prefix}):" >&2
  for path in \
      "${MPICC:-}" \
      "${MPIF90:-}" \
      "${EBROOTOPENMPI:-}/bin/mpif90" \
      "${prefix}/bin/mpicc" \
      "${prefix}/bin/mpif90" \
      "${prefix}/bin/mpifort"; do
    [[ -z "${path}" ]] && continue
    if [[ -x "${path}" ]]; then
      echo "   OK   ${path}" >&2
    elif [[ -e "${path}" ]]; then
      echo "   exists but not executable: ${path}" >&2
    else
      echo "   MISSING ${path}" >&2
    fi
  done
  hackathon_dump_mpi_env
}

hackathon_export_openmpi_env() {
  local mpipath="$1"
  local bindir mpicc
  export MPIF90="${mpipath}"
  bindir="$(dirname "${mpipath}")"
  export PATH="${bindir}:${PATH}"
  mpicc="${bindir}/mpicc"
  if [[ -x "${mpicc}" ]]; then
    export MPICC="${mpicc}"
  fi
  if [[ -z "${OPENMPI_PREFIX:-}" ]]; then
    export OPENMPI_PREFIX="$(dirname "${bindir}")"
  fi
}

# Load GNU OpenMPI for Makefile.cpu (MPI=1). Sets MPIF90 to a full path.
# Stellar compute nodes: load GCC toolset + openmpi modules (not /usr/local).
# Default stack: gcc-toolset/10 + openmpi/gcc-toolset-10/4.1.0 on Stellar compute.
# openmpi/gcc/4.1.0 pairs with system GCC 8, not gcc-toolset/10.
# Override: GCC_MODULE, OPENMPI_MODULE, OPENMPI_MODULES (space-separated try list),
# OPENMPI_USE_MODULES=0 for a pre-built login-node tree.
hackathon_load_cpu_mpi() {
  local mpipath="" mod gcc_mod tried="" modlist bindir

  hackathon_reset_cpu_job_env

  echo "== OpenMPI config: USE_MODULES=${OPENMPI_USE_MODULES:-1} GCC_MODULE=${GCC_MODULE:-unset} OPENMPI_MODULE=${OPENMPI_MODULE:-unset}"
  echo "== MODULEPATH=${MODULEPATH:-unset} SLURM_JOB_ID=${SLURM_JOB_ID:-unset}"
  echo "== LOADEDMODULES=${LOADEDMODULES:-empty}"

  if mpipath="$(hackathon_resolve_mpif90)"; then
    hackathon_export_openmpi_env "${mpipath}"
    echo "== MPI ready: MPIF90=${MPIF90}"
    [[ -n "${MPICC:-}" ]] && echo "== MPICC=${MPICC}"
    module list 2>&1 | head -15 || true
    "${MPIF90}" --version 2>&1 | head -1 || true
    return 0
  fi

  if [[ "${OPENMPI_USE_MODULES:-1}" != "1" ]]; then
    hackathon_probe_openmpi_paths
    echo "ERROR: OpenMPI wrappers not found (OPENMPI_USE_MODULES=0, /usr/local not on compute nodes?)." >&2
    return 1
  fi

  if ! hackathon_init_modules; then
    hackathon_probe_openmpi_paths
    echo "ERROR: Environment Modules init failed." >&2
    return 1
  fi

  gcc_mod="${GCC_MODULE:-gcc-toolset/10}"
  echo "== loading ${gcc_mod}"
  if ! hackathon_eval_module load "${gcc_mod}"; then
    echo "WARNING: module load ${gcc_mod} failed; trying openmpi without explicit gcc" >&2
  fi

  if [[ -n "${OPENMPI_MODULES:-}" ]]; then
    read -r -a modlist <<< "${OPENMPI_MODULES}"
  else
    modlist=(
      "${OPENMPI_MODULE:-openmpi/gcc-toolset-10/4.1.0}"
      openmpi/gcc-toolset-10/4.1.0
      openmpi/gcc/4.1.0
      openmpi/gcc/4.1.6
      openmpi/gcc/4.1.2
    )
  fi

  for mod in "${modlist[@]}"; do
    [[ -z "${mod}" ]] && continue
    [[ " ${tried} " == *" ${mod} "* ]] && continue
    tried="${tried} ${mod}"
    echo "== trying module ${mod}"
    hackathon_reset_cpu_job_env
    hackathon_eval_module load "${gcc_mod}" 2>/dev/null || true
    if ! hackathon_eval_module load "${mod}"; then
      continue
    fi
    echo "== module list after load ${mod}:"
    module list 2>&1 | head -15 || true
    mapfile -t _ompi_bindirs < <(hackathon_openmpi_bindirs_from_module "${mod}")
    if mpipath="$(hackathon_find_mpif90 "${_ompi_bindirs[@]}")"; then
      hackathon_export_openmpi_env "${mpipath}"
      echo "== MPI ready after modules (${mod})"
      echo "== MPIF90=${MPIF90}"
      [[ -n "${MPICC:-}" ]] && echo "== MPICC=${MPICC}"
      "${MPIF90}" --version 2>&1 | head -1 || true
      return 0
    fi
    echo "WARNING: ${mod} loaded but mpif90 not found on this node" >&2
    hackathon_diag_openmpi_bindirs "${mod}"
    module show "${mod}" 2>&1 | sed -n '1,25p' >&2 || true
    echo "== PATH=${PATH}" >&2
  done

  echo "== module avail openmpi (diagnostic):"
  module avail openmpi 2>&1 | head -20 || true
  hackathon_probe_openmpi_paths
  echo "ERROR: mpif90/mpifort not found after trying modules:${tried}" >&2
  echo "       Stellar -p pu nodes install OpenMPI *runtime* only under /usr/local/openmpi." >&2
  echo "       Expected wrappers at /usr/local/openmpi/4.1.0/gcc-toolset-10/bin/mpif90 are absent." >&2
  echo "       Workaround: build on login node (see CLUSTER.md), then BUILD_BINARIES=0 sbatch." >&2
  echo "       Or try Intel MPI: module avail intel-mpi" >&2
  return 1
}

# Strip /usr/local/openmpi/* from PATH (login nodes expose 4.1.2 wrappers that
# bypass the gcc-toolset/10 + openmpi/gcc-toolset-10 module stack).
hackathon_strip_login_openmpi_path() {
  local p newpath=""
  IFS=':' read -ra parts <<< "${PATH:-}"
  for p in "${parts[@]}"; do
    [[ -z "${p}" ]] && continue
    case "${p}" in
      /usr/local/openmpi/*)
        continue
        ;;
    esac
    newpath="${newpath:+$newpath:}${p}"
  done
  PATH="${newpath}"
  export PATH
}

# Login-node CPU build: force gcc-toolset/10 + openmpi/gcc-toolset-10/4.1.0.
# Unlike hackathon_load_cpu_mpi, never short-circuit on /usr/local/openmpi/4.1.2.
hackathon_load_cpu_mpi_for_build() {
  local gcc_mod="${GCC_MODULE:-gcc-toolset/10}"
  local ompi_mod="${OPENMPI_MODULE:-openmpi/gcc-toolset-10/4.1.0}"
  local mpipath=""

  hackathon_reset_cpu_job_env
  hackathon_strip_login_openmpi_path
  unset MPICC MPIF90 MPIFORT MPI_HOME OPENMPI_HOME OPENMPI_PREFIX EBROOTOPENMPI

  hackathon_init_modules || return 1
  hackathon_unload_openmpi_modules
  hackathon_eval_module purge 2>/dev/null || true
  hackathon_unload_openmpi_modules

  echo "== loading CPU build modules: ${gcc_mod} ${ompi_mod}"
  if ! hackathon_eval_module load "${gcc_mod}"; then
    echo "ERROR: module load ${gcc_mod} failed" >&2
    return 1
  fi
  if ! hackathon_eval_module load "${ompi_mod}"; then
    echo "ERROR: module load ${ompi_mod} failed" >&2
    echo "       Try: module unload openmpi/gcc/4.1.2 && module purge" >&2
    return 1
  fi

  mapfile -t _ompi_bindirs < <(hackathon_openmpi_bindirs_from_module "${ompi_mod}")
  [[ -n "${MPI_HOME:-}" ]] && _ompi_bindirs+=("${MPI_HOME}/bin")
  if ! mpipath="$(hackathon_find_mpif90 --strict "${_ompi_bindirs[@]}")"; then
    hackathon_diag_openmpi_bindirs "${ompi_mod}"
    echo "ERROR: mpif90 not found for ${ompi_mod} after module load" >&2
    return 1
  fi
  case "${mpipath}" in
    /usr/local/openmpi/4.1.2/*)
      echo "ERROR: refusing OpenMPI 4.1.2 wrappers (${mpipath}); load ${ompi_mod} first." >&2
      return 1
      ;;
  esac

  hackathon_export_openmpi_env "${mpipath}"
  echo "== MPI ready for CPU build: MPIF90=${MPIF90}"
  [[ -n "${MPICC:-}" ]] && echo "== MPICC=${MPICC}"
  module list 2>&1 | head -12 || true
  "${MPIF90}" --version 2>&1 | head -1 || true
  return 0
}

# Load OpenMPI modules on compute for srun (runtime libs only; mpif90 not required).
hackathon_load_cpu_mpi_runtime() {
  local gcc_mod="${GCC_MODULE:-gcc-toolset/10}"
  local ompi_mod="${OPENMPI_MODULE:-openmpi/gcc-toolset-10/4.1.0}"

  hackathon_reset_cpu_job_env
  hackathon_init_modules || return 1

  echo "== loading MPI runtime modules: ${gcc_mod} ${ompi_mod}"
  hackathon_eval_module load "${gcc_mod}" 2>/dev/null || \
    echo "WARNING: module load ${gcc_mod} failed" >&2
  if ! hackathon_eval_module load "${ompi_mod}"; then
    echo "ERROR: failed to load ${ompi_mod} for MPI runtime" >&2
    return 1
  fi
  echo "== MPI runtime ready (LD_LIBRARY_PATH for libmpi)"
  module list 2>&1 | head -10 || true
  return 0
}

# Build ramses3d.cpu on the login node (pu compute nodes have no mpif90 wrappers).
hackathon_build_cpu_binary() {
  local cpu_mhd="${CPU_MHD:-0}"
  local cpu_hydro="${CPU_HYDRO:-$([[ "${cpu_mhd}" == "1" ]] && echo 1 || echo 0)}"
  local cpu_grav="${CPU_GRAV:-$([[ "${cpu_mhd}" == "1" ]] && echo 0 || echo 1)}"
  local cpu_npre="${CPU_NPRE:-4}"
  local cpu_npscal="${CPU_NPSCAL:-0}"
  local bin="${BIN_CPU:-$([[ "${cpu_mhd}" == "1" ]] && echo "${MINIRAM}/bin/ramses3d.mhd.cpu" || echo "${MINIRAM}/bin/ramses3d.cpu")}"
  local log="${CPU_BUILD_LOG:-${HARNESS_DIR}/build_cpu.log}"
  local gcc_mod="${GCC_MODULE:-gcc-toolset/10}"
  local ompi_mod="${OPENMPI_MODULE:-openmpi/gcc-toolset-10/4.1.0}"

  if [[ -n "${SLURM_JOB_ID:-}" && "${ALLOW_SLURM_CPU_BUILD:-0}" != "1" ]]; then
    echo "ERROR: hackathon_build_cpu_binary must run on the login node, not inside sbatch." >&2
    echo "       Use BUILD_BINARIES=0 in dmo_cpu.slurm (default) and build before submit." >&2
    return 1
  fi

  echo "== CPU build: ${gcc_mod} + ${ompi_mod} -> ${bin} (MHD=${cpu_mhd} HYDRO=${cpu_hydro} GRAV=${cpu_grav} NPRE=${cpu_npre}; serial make)"
  if ! hackathon_load_cpu_mpi_for_build; then
    return 1
  fi

  if ! (
    set -euo pipefail
    set -o pipefail
    export MPIF90 MPICC PATH LD_LIBRARY_PATH
    cd "${MINIRAM}/bin"
    if [[ ! -e Makefile.cpu ]]; then
      if [[ -e "${HARNESS_DIR}/makefiles/Makefile.cpu" ]]; then
        echo "Copying Makefile.cpu from harness into ${MINIRAM}/bin"
        cp "${HARNESS_DIR}/makefiles/Makefile.cpu" Makefile.cpu
      elif [[ -e "${HARNESS_DIR}/Makefile.cpu" ]]; then
        echo "Copying Makefile.cpu from harness into ${MINIRAM}/bin"
        cp "${HARNESS_DIR}/Makefile.cpu" Makefile.cpu
      else
        echo "ERROR: Makefile.cpu not found in ${MINIRAM}/bin or ${HARNESS_DIR}/makefiles" >&2
        exit 2
      fi
    fi
    echo "Checkout HEAD: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
    rm -f "${bin}" ./ramses3d ./ramses3d.cpu
    make clean || rm -f ./*.o ./*.mod ./ramses3d ./ramses3d.cpu
    make -f Makefile.cpu -j 1 \
         COMPILER=GNU MPI=1 MPIF90="${MPIF90}" DEBUG=0 NHILBERT=1 \
         GRAV="${cpu_grav}" HYDRO="${cpu_hydro}" MHD="${cpu_mhd}" NPSCAL="${cpu_npscal}" \
         NPRE="${cpu_npre}" NDIM=3 \
         ${CPU_UNITS:+UNITS="${CPU_UNITS}"} ramses \
      2>&1 | tee "${log}"
    if [[ ! -e ./ramses3d && ! -e ./ramses3d.cpu ]]; then
      echo "ERROR: make finished but neither ramses3d nor ramses3d.cpu found in ${MINIRAM}/bin" >&2
      exit 1
    fi
    mkdir -p "$(dirname "${bin}")"
    if [[ -e ./ramses3d.cpu ]]; then
      cp -f ./ramses3d.cpu "${bin}"
    else
      cp -f ./ramses3d "${bin}"
    fi
  ); then
    echo "ERROR: CPU build failed (see ${log:-build log})" >&2
    return 1
  fi
  echo "== CPU binary installed: ${bin}"
  ls -la "${bin}"
  return 0
}

# True when Makefile.a100 has harness TURB/FFTW -I wiring (not stale repo copy).
hackathon_makefile_a100_has_turb_fftw() {
  local mf="$1"
  [[ -f "${mf}" ]] || return 1
  grep -qE 'TURB=1 requires FFTW=install_prefix|TURB_INC.*FFTW|FFTW_LIBDIR' "${mf}" 2>/dev/null
}

# Pick GPU Makefile from harness makefiles/ (cluster profile sets GPU_MAKEFILE).
hackathon_resolve_gpu_makefile() {
  local mf_name="${GPU_MAKEFILE:-Makefile.a100}" candidate resolved="" root
  root="$(hackathon_repo_root 2>/dev/null || echo "${HARNESS_DIR:-.}")"
  for candidate in \
      "${root}/makefiles/${mf_name}" \
      "${HARNESS_DIR}/makefiles/${mf_name}" \
      "${HARNESS_DIR}/${mf_name}" \
      "${HOME}/hackathon/makefiles/${mf_name}" \
      "${MINIRAM}/bin/${mf_name}"; do
    [[ -f "${candidate}" ]] || continue
    if hackathon_makefile_a100_has_turb_fftw "${candidate}" 2>/dev/null || [[ "${mf_name}" != Makefile.a100* ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
    [[ -z "${resolved}" ]] && resolved="${candidate}"
  done
  [[ -n "${resolved}" ]] && printf '%s' "${resolved}"
  [[ -n "${resolved}" ]]
}

# Legacy alias
hackathon_resolve_makefile_a100() {
  hackathon_resolve_gpu_makefile
}

hackathon_verify_miniram() {
  if [[ ! -d "${MINIRAM}" ]]; then
    echo "ERROR: MINIRAM not found: ${MINIRAM}" >&2
    exit 2
  fi
  if [[ -d "${MINIRAM}/.git" ]]; then
    local branch head expected_branch
    expected_branch="${MINIRAM_EXPECTED_BRANCH:-gpu_mhd}"
    branch="$(git -C "${MINIRAM}" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    branch="${branch:-$(git -C "${MINIRAM}" branch --show-current 2>/dev/null || true)}"
    branch="${branch:-unknown}"
    head="$(git -C "${MINIRAM}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "== MINIRAM checkout: ${MINIRAM} branch=${branch} HEAD=${head}"
    if [[ "${branch}" != "${expected_branch}" ]]; then
      echo "WARNING: expected ${expected_branch}; got branch=${branch}" >&2
    fi
  fi
  if [[ ! -f "${MINIRAM}/bin/${GPU_MAKEFILE:-Makefile.a100}" && ! -f "${HARNESS_DIR}/makefiles/${GPU_MAKEFILE:-Makefile.a100}" ]]; then
    echo "ERROR: ${GPU_MAKEFILE:-Makefile.a100} not found in ${MINIRAM}/bin or ${HARNESS_DIR}/makefiles" >&2
    exit 2
  fi
}

# Minimal GPU build for debug-cosmo: ${HARNESS_DIR}/Makefile.debug-cosmo
# (cluster-safe NVHPC link; NPRE=8 default). Not bin/Makefile.
hackathon_build_binary_repo_minimal() {
  local build_log="$1"
  hackathon_verify_miniram
  hackathon_setup_paths
  hackathon_load_modules || exit 2
  local makefile="" root
  root="$(hackathon_repo_root 2>/dev/null || echo "${HARNESS_DIR:-.}")"
  for candidate in \
      "${root}/makefiles/Makefile.debug-cosmo" \
      "${HARNESS_DIR}/makefiles/Makefile.debug-cosmo" \
      "${HARNESS_DIR}/Makefile.debug-cosmo"; do
    if [[ -f "${candidate}" ]]; then
      makefile="${candidate}"
      break
    fi
  done
  if [[ -z "${makefile}" ]]; then
    echo "ERROR: Makefile.debug-cosmo not found under ${HARNESS_DIR}/makefiles (git pull harness repo)" >&2
    return 1
  fi
  local gpu_cuda_arch="${GPU_CUDA_ARCH:-${GPU_CUDA_ARCH_DEFAULT:-sm_80}}"
  local gpu_hydro="${GPU_HYDRO:-1}"
  local gpu_grav="${GPU_GRAV:-1}"
  local gpu_units="${GPU_UNITS-COSMO}"
  local bin_gpu="${BIN_GPU:-}"
  if [[ -z "${bin_gpu}" ]]; then
    if [[ "${gpu_hydro}" == "1" ]]; then
      bin_gpu="${MINIRAM}/bin/ramses3d.hydro"
    else
      bin_gpu="${MINIRAM}/bin/ramses3d"
    fi
  fi
  export BIN_GPU="${bin_gpu}"
  local gpu_clean="${CLEAN:-1}"
  local -a make_jobs=()
  if [[ -n "${GPU_MAKE_JOBS:-}" ]]; then
    if [[ "${GPU_MAKE_JOBS}" == "j" ]]; then
      make_jobs=(-j)
    else
      make_jobs=(-j "${GPU_MAKE_JOBS}")
    fi
  fi
  local -a make_args=(
    -f "${makefile}"
    "${make_jobs[@]}"
    NVHPC_CUDA_HOME="${NVHPC_CUDA_HOME:-}"
    NVHPC_MATH_LIB="${NVHPC_MATH_LIB:-}"
    NDIM=3 COMPILER=NVHPC HYDRO="${gpu_hydro}" GRAV="${gpu_grav}"
    CUDA_ARCH="${gpu_cuda_arch}"
  )
  if [[ -n "${gpu_units}" ]]; then
    make_args+=(UNITS="${gpu_units}")
  fi
  echo "== debug-cosmo build from ${MINIRAM}/bin (Makefile=${makefile}, CUDA_ARCH=${gpu_cuda_arch} HYDRO=${gpu_hydro} GRAV=${gpu_grav}${gpu_units:+ UNITS=${gpu_units}})"
  echo "== make ${make_args[*]} ramses"
  echo "== install target: ${BIN_GPU}"
  (
    set -euo pipefail
    cd "${MINIRAM}"
    echo "Checkout HEAD: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
    cd bin
    echo "== build started $(date -Iseconds) (CLEAN=${gpu_clean})"
    if [[ "${gpu_clean}" == "1" ]]; then
      make "${make_args[@]}" clean || rm -f ./*.o ./*.mod ./ramses3d ./ramses3d.cpu
    else
      echo "== incremental build: skipping make clean (CLEAN=0)"
    fi
    make "${make_args[@]}" ramses \
      2>&1 | tee "${build_log}"
    echo "== build finished $(date -Iseconds)"
    mkdir -p "$(dirname "${BIN_GPU}")"
    if [[ -e "${BIN_GPU}" && "$(readlink -f ramses3d)" == "$(readlink -f "${BIN_GPU}")" ]]; then
      :
    else
      cp -f ramses3d "${BIN_GPU}"
    fi
  )
}

hackathon_build_binary() {
  local build_log="$1"
  if [[ "${GPU_BUILD_MINIMAL:-0}" == "1" ]]; then
    hackathon_build_binary_repo_minimal "${build_log}"
    return $?
  fi
  hackathon_verify_miniram
  hackathon_setup_paths
  local gpu_debug="${GPU_DEBUG:-0}"
  local gpu_hydro="${GPU_HYDRO:-0}"
  local gpu_npre="${GPU_NPRE:-4}"
  local gpu_fastmath="${GPU_FASTMATH:-0}"
  local gpu_cuda_arch="${GPU_CUDA_ARCH}"
  local gpu_paper="${GPU_PAPER:-0}"
  local gpu_mhd="${GPU_MHD:-0}"
  local gpu_turb="${GPU_TURB:-0}"       # turbulent driving (TURB=1 links FFTW for host field gen)
  local gpu_fftw="${FFTW:-}"            # FFTW prefix for TURB=1 builds (Makefile -I/-L); from $FFTW
  local gpu_fftw_vendor=""
  local gpu_fftw_header=""
  if [[ "${gpu_turb}" == "1" ]]; then
    hackathon_load_fftw || return 1
    gpu_fftw="${FFTW}"
    gpu_fftw_vendor="${FFTW_VENDOR_INC:-}"
  fi
  local gpu_npscal="${GPU_NPSCAL:-0}"   # extra passive scalars; MHD tests default to NHYDRO=5, NPSCAL=0
  local gpu_grav="${GPU_GRAV:-1}"       # MHD shock/vortex tests set GPU_GRAV=0 (no -DGRAV)
  local gpu_units="${GPU_UNITS-COSMO}"  # MHD shock/vortex tests set GPU_UNITS= (omit UNITS=)
  local gpu_kick_coop_gather="${GPU_KICK_COOP_GATHER:-0}"
  local gpu_kick_coop_validate="${GPU_KICK_COOP_VALIDATE:-0}"
  local gpu_dust_coop_kick="${GPU_DUST_COOP_KICK:-0}"
  local dust_kick_blocks_per_sm="${GPU_DUST_KICK_BLOCKS_PER_SM:-6}"
  local cub_sort_part="${CUB_SORT_PART:-1}"
  local cub_sort_refine="${CUB_SORT_REFINE:-1}"
  local cub_scan_refine="${CUB_SCAN_REFINE:-1}"
  local cuda_profile=0
  if [[ "${GPU_LINEINFO:-0}" == "1" ]]; then
    cuda_profile=1
  fi
  local makefile=""
  if ! makefile="$(hackathon_resolve_gpu_makefile)"; then
    echo "ERROR: ${GPU_MAKEFILE:-Makefile.a100} not found (HARNESS_DIR=${HARNESS_DIR} MINIRAM=${MINIRAM})" >&2
    return 1
  fi
  if [[ "${gpu_turb}" == "1" ]] && ! hackathon_makefile_a100_has_turb_fftw "${makefile}"; then
    echo "ERROR: ${makefile} lacks TURB/FFTW -I wiring; sync harness Makefile.a100" >&2
    echo "       rsync -av ~/hackathon/Makefile.a100 ~/hackathon/hackathon_common.sh \${HARNESS_DIR:-~/hackathon}/" >&2
    return 1
  fi
  local bin_gpu="${BIN_GPU:-}"
  if [[ -z "${bin_gpu}" ]]; then
    if [[ "${gpu_mhd}" == "1" ]]; then
      bin_gpu="${MINIRAM}/bin/ramses3d.mhd"
    elif [[ "${gpu_hydro}" == "1" ]]; then
      bin_gpu="${MINIRAM}/bin/ramses3d.hydro"
    else
      bin_gpu="${MINIRAM}/bin/ramses3d"
    fi
  fi
  export BIN_GPU="${bin_gpu}"
  echo "== building GPU binary from ${MINIRAM}/bin (Makefile=${makefile}, CUDA_ARCH=${gpu_cuda_arch} PAPER=${gpu_paper} MHD=${gpu_mhd} NPSCAL=${gpu_npscal} KICK_COOP_GATHER=${gpu_kick_coop_gather} KICK_COOP_VALIDATE=${gpu_kick_coop_validate} DUST_COOP_KICK=${gpu_dust_coop_kick} DUST_KICK_BLOCKS_PER_SM=${dust_kick_blocks_per_sm} CUB_SORT_REFINE=${cub_sort_refine} CUB_SCAN_REFINE=${cub_scan_refine} FASTMATH=${gpu_fastmath})"
  echo "== GPU build: COMPILER=NVHPC DEBUG=${gpu_debug} NHILBERT=1 GRAV=${gpu_grav} HYDRO=${gpu_hydro} MHD=${gpu_mhd} TURB=${gpu_turb} NPSCAL=${gpu_npscal} NPRE=${gpu_npre} FASTMATH=${gpu_fastmath} ALWAYS_KIND8_POS=${GPU_ALWAYS_KIND8_POS:-0} NDIM=3${gpu_units:+ UNITS=${gpu_units}}${gpu_fftw:+ FFTW=${gpu_fftw}}${gpu_fftw_vendor:+ FFTW_VENDOR_INC=${gpu_fftw_vendor}}${gpu_fftw_header:+ FFTW_HEADER_DIR=${gpu_fftw_header}}"
  echo "== install target: ${BIN_GPU}"
  local gpu_clean="${CLEAN:-1}"
  if [[ "${gpu_turb}" == "1" && -z "${gpu_fftw}" ]]; then
    echo "ERROR: TURB=1 build but FFTW prefix is empty after hackathon_load_fftw" >&2
    return 1
  fi
  if [[ "${gpu_turb}" == "1" && -n "${gpu_fftw_vendor}" && ! -f "${gpu_fftw_vendor}/fftw3.f" ]]; then
    # vendor_inc may be .../include with fftw3.f inside
    if [[ ! -f "${gpu_fftw_vendor%/}/fftw3.f" ]]; then
      echo "WARNING: FFTW_VENDOR_INC=${gpu_fftw_vendor} has no fftw3.f; will stage from other paths" >&2
    fi
  fi
  if [[ "${gpu_turb}" == "1" ]]; then
    echo "== TURB/FFTW diagnostics: harness=${HARNESS_DIR} makefile=${makefile}"
    echo "== FFTW=${gpu_fftw} FFTW_VENDOR_INC=${gpu_fftw_vendor:-<unset>}"
    if [[ -f "${gpu_fftw}/include/fftw3.f" ]]; then
      echo "== fftw3.f: ${gpu_fftw}/include/fftw3.f (OK)"
    elif [[ -n "${gpu_fftw_vendor}" && -f "${gpu_fftw_vendor}/fftw3.f" ]]; then
      echo "== fftw3.f: ${gpu_fftw_vendor}/fftw3.f (vendor OK)"
    else
      echo "WARNING: fftw3.f not found under ${gpu_fftw}/include or vendor ${gpu_fftw_vendor:-<unset>}" >&2
    fi
    if [[ -d "${gpu_fftw}/lib64" ]]; then
      echo "== FFTW libdir: ${gpu_fftw}/lib64"
    elif [[ -d "${gpu_fftw}/lib" ]]; then
      echo "== FFTW libdir: ${gpu_fftw}/lib"
    fi
  fi
  local -a make_args=(
    -f "${makefile}"
    NVHPC_CUDA_HOME="${NVHPC_CUDA_HOME:-}"
    NVHPC_MATH_LIB="${NVHPC_MATH_LIB:-}"
    CUDA_ARCH="${gpu_cuda_arch}" PAPER="${gpu_paper}"
    KICK_COOP_GATHER="${gpu_kick_coop_gather}" KICK_COOP_VALIDATE="${gpu_kick_coop_validate}"
    DUST_COOP_KICK="${gpu_dust_coop_kick}"
    DUST_KICK_BLOCKS_PER_SM="${dust_kick_blocks_per_sm}"
    CUB_SORT_PART="${cub_sort_part}" CUB_SORT_REFINE="${cub_sort_refine}" CUB_SCAN_REFINE="${cub_scan_refine}"
    FASTMATH="${gpu_fastmath}"
    CUDA_PROFILE="${cuda_profile}"
    COMPILER=NVHPC DEBUG="${gpu_debug}" NHILBERT=1 GRAV="${gpu_grav}" HYDRO="${gpu_hydro}"
    MHD="${gpu_mhd}" TURB="${gpu_turb}" NPSCAL="${gpu_npscal}"
    FFTW="${gpu_fftw}"
    NPRE="${gpu_npre}" NDIM=3
  )
  if [[ -n "${GPU_TARGETS:-}" ]]; then
    make_args+=(GPU_TARGETS="${GPU_TARGETS}")
  fi
  if [[ -n "${gpu_fftw_vendor}" ]]; then
    make_args+=(FFTW_VENDOR_INC="${gpu_fftw_vendor}")
  fi
  if [[ -n "${gpu_units}" ]]; then
    make_args+=(UNITS="${gpu_units}")
  fi
  if [[ "${GPU_ALWAYS_KIND8_POS:-0}" == "1" ]]; then
    make_args+=(ALWAYS_KIND8_POS=1)
  fi
  if [[ -n "${GPU_INIT:-}" ]]; then
    make_args+=(INIT="${GPU_INIT}")
  fi
  (
    set -euo pipefail
    cd "${MINIRAM}"
    echo "Checkout HEAD: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
    cd bin
    local staged="${MINIRAM}/bin/${GPU_MAKEFILE:-Makefile.a100}"
    if [[ "${makefile}" != "${staged}" ]] || [[ "${gpu_turb}" == "1" ]]; then
      echo "== staging ${makefile} -> ${staged}"
      cp -f "${makefile}" "${staged}"
    fi
    makefile="${staged}"
    if [[ "${gpu_turb}" == "1" ]]; then
      gpu_fftw_header="$(hackathon_stage_fftw_header "${gpu_fftw}" "${gpu_fftw_vendor}")" || exit 2
      export FFTW_HEADER_DIR="${gpu_fftw_header}"
      make_args+=(FFTW_HEADER_DIR="${gpu_fftw_header}")
      echo "== dry-run turb_commons.o (expect -I${gpu_fftw_header} and -DTURB):"
      rm -f turb_commons.o
      local dry_run
      dry_run="$(make "${make_args[@]}" -n turb_commons.o 2>&1 || true)"
      printf '%s\n' "${dry_run}" | head -3 || true
      if ! hackathon_dryrun_has_turb_inc "${dry_run}" "${gpu_fftw}" "${gpu_fftw_vendor}" "${gpu_fftw_header}"; then
        echo "ERROR: make -n turb_commons.o lacks FFTW -I (FFTW_HEADER_DIR=${gpu_fftw_header})" >&2
        printf '%s\n' "${dry_run}" | head -5 >&2
        exit 2
      fi
    fi
    # Serial make only: the RAMSES Makefile does not encode Fortran module
    # dependencies, so parallel make races consumers before producer .mod files
    # exist (e.g. amr_parameters.mod). Do NOT add -j here.
    echo "== build started $(date -Iseconds) (serial make -f ${makefile}, CLEAN=${gpu_clean})"
    if [[ "${gpu_clean}" == "1" ]]; then
      make "${make_args[@]}" clean || rm -f ./*.o ./*.mod ./ramses3d ./ramses3d.cpu
    else
      echo "== incremental build: skipping make clean (CLEAN=0)"
    fi
    make "${make_args[@]}" ramses \
      2>&1 | tee "${build_log}"
    echo "== build finished $(date -Iseconds)"
    if [[ "${gpu_turb}" == "1" ]]; then
      echo "== turb_commons compile line from build.log:"
      grep -E 'turb_commons\.f90' "${build_log}" | head -1 || echo "   (not found — search build.log manually)"
    fi
    mkdir -p "$(dirname "${BIN_GPU}")"
    if [[ -e "${BIN_GPU}" && "$(readlink -f ramses3d)" == "$(readlink -f "${BIN_GPU}")" ]]; then
      :
    else
      cp -f ramses3d "${BIN_GPU}"
    fi
  )
}

# Apply KEY=VAL to a Fortran namelist file (in-place). No-op if val is empty.
hackathon_apply_nml_kv() {
  local key="$1" val="$2" file="$3"
  [[ -z "${val}" ]] && return 0
  if grep -qE "^[[:space:]]*${key}=" "${file}"; then
    sed -i.bak -E "s/^[[:space:]]*${key}=.*/ ${key}=${val}/" "${file}"
    rm -f "${file}.bak"
  fi
}

# Override part_dep_algo only when the namelist already defines it (no insert;
# older develop and cosmo.nml omit this key).
hackathon_apply_part_dep_algo() {
  local file="$1"
  [[ -z "${PART_DEP_ALGO:-}" ]] && return 0
  hackathon_apply_nml_kv part_dep_algo "${PART_DEP_ALGO}" "${file}"
}

# Set ndust_per_cell and recompute ndusttot/ndustmax from levelmin (2^(3*levelmin) cells).
hackathon_apply_ndust_ppc() {
  local file="$1" ppc="$2"
  [[ -z "${ppc}" ]] && return 0
  local levelmin n_cells ndusttot
  levelmin="$(grep -E '^[[:space:]]*levelmin=' "${file}" | sed -E 's/.*=[[:space:]]*([0-9]+).*/\1/' | head -1)"
  levelmin="${levelmin:-8}"
  n_cells=$((2 ** (3 * levelmin)))
  ndusttot=$((n_cells * ppc))
  hackathon_apply_nml_kv ndust_per_cell "${ppc}" "${file}"
  hackathon_apply_nml_kv ndusttot "${ndusttot}" "${file}"
  hackathon_apply_nml_kv ndustmax "${ndusttot}" "${file}"
  echo "== ndust ppc=${ppc} levelmin=${levelmin} cells=${n_cells} ndusttot=${ndusttot}"
}

# Comma-separated search paths for NCU --source-folders (capture + post-export).
# workdir is the job case directory (on Stellar: under RUN_DIR, e.g.
# /scratch/gpfs/$USER/hackathon/dmo_gpu_JOBID/orszag_tang_l7) where we stage
# default -> gpu_hydro.cuf symlinks. MINIRAM stays under $HOME (~/mini-ramses-dev).
hackathon_ncu_source_folders() {
  local workdir="${1:-}"
  hackathon_setup_paths
  local -a folders=()
  local IFS=,
  if [[ -n "${workdir}" && -d "${workdir}" ]]; then
    folders+=("${workdir}")
  fi
  if [[ -d "${MINIRAM}/gpu" ]]; then
    folders+=("${MINIRAM}/gpu")
  fi
  if [[ -d "${MINIRAM}" ]]; then
    folders+=("${MINIRAM}")
  fi
  if ((${#folders[@]} == 0)); then
    return 1
  fi
  IFS=,
  printf '%s' "${folders[*]}"
}

# Ensure scratch workdir is in NCU_SOURCE_FOLDERS even when preset at submit time
# (submit cannot know dmo_gpu_JOBID/orszag_tang_l7 yet).
hackathon_ncu_resolve_source_folders() {
  local workdir="${1:-}"
  hackathon_setup_paths
  local merged preset="${NCU_SOURCE_FOLDERS:-}"
  merged="$(hackathon_ncu_source_folders "${workdir}")" || merged=""
  if [[ -z "${merged}" ]]; then
    printf '%s' "${preset}"
    return 0
  fi
  if [[ -z "${preset}" ]]; then
    printf '%s' "${merged}"
    return 0
  fi
  local IFS=,
  local entry
  for entry in ${preset}; do
    [[ -n "${entry}" && ",${merged}," != *",${entry},"* ]] && merged="${entry},${merged}"
  done
  printf '%s' "${merged}"
}

# NVFortran RDC device link may record lineinfo source as filename "default".
# Symlink CUF sources (and optional NCU_DEFAULT_SOURCE -> default) into workdir.
hackathon_ncu_stage_source_lookup() {
  local workdir="$1"
  hackathon_setup_paths
  local gpu_dir="${MINIRAM}/gpu"
  if [[ ! -d "${gpu_dir}" ]]; then
    echo "WARNING: NCU source lookup: ${gpu_dir} not found" >&2
    return 0
  fi
  local cuf base count=0
  for cuf in "${gpu_dir}"/*.cuf; do
    [[ -f "${cuf}" ]] || continue
    base="$(basename "${cuf}")"
    ln -sfn "${cuf}" "${workdir}/${base}"
    count=$((count + 1))
  done
  if [[ -n "${NCU_DEFAULT_SOURCE:-}" ]]; then
    local primary="${gpu_dir}/${NCU_DEFAULT_SOURCE}"
    if [[ -f "${primary}" ]]; then
      ln -sfn "${primary}" "${workdir}/default"
      echo "== NCU source lookup: ${workdir}/default -> ${primary}"
    else
      echo "WARNING: NCU_DEFAULT_SOURCE not found: ${primary}" >&2
    fi
  fi
  echo "== NCU source lookup: ${count} CUF symlinks in ${workdir}"
}

# Append --import-source / --source-folders to an NCU capture argv array.
hackathon_ncu_append_capture_source_args() {
  local -n _args=$1
  local workdir="${2:-}"
  [[ "${NCU_IMPORT_SOURCE:-no}" == "yes" ]] || return 0
  _args+=(--import-source yes)
  local folders
  folders="$(hackathon_ncu_resolve_source_folders "${workdir}")" || folders=""
  if [[ -n "${folders}" ]]; then
    _args+=(--source-folders "${folders}")
    export NCU_SOURCE_FOLDERS="${folders}"
    echo "== NCU --source-folders ${folders}"
  fi
}

# Return 0 if NAME already appears in the nameref argv array.
hackathon_ncu_argv_has() {
  local -n _haystack=$1
  local needle="$2"
  local x
  for x in "${_haystack[@]}"; do
    [[ "${x}" == "${needle}" ]] && return 0
  done
  return 1
}

# Kernel filter for NCU (capture + replay). Skips if capture argv already set it.
hackathon_ncu_source_kernel_args() {
  local -n _args=$1
  local kernel="${NCU_KERNEL:-regex:.*hydro_integrator_kernel.*}"
  hackathon_ncu_argv_has _args --kernel-name-base && return 0
  _args+=(--kernel-name-base demangled --kernel-name "${kernel}")
}

# High-level source view (replay export only — not used during metric capture).
hackathon_ncu_source_print_args() {
  local -n _args=$1
  hackathon_ncu_argv_has _args --print-source && return 0
  _args+=(--print-source cuda,sass)
}

# Replay export: kernel filter + cuda,sass (capture already sets kernel flags separately).
hackathon_ncu_source_page_args() {
  local -n _args=$1
  hackathon_ncu_source_kernel_args _args
  hackathon_ncu_source_print_args _args
}

# True if PATH looks like a usable NCU --page source CSV (high-level lines, not SASS-only).
hackathon_ncu_source_csv_ok() {
  local csv="$1"
  [[ -f "${csv}" ]] || return 1
  grep -q '^==ERROR==' "${csv}" && return 1
  head -1 "${csv}" | grep -qiE 'File|Line|Address|derived__|Source' || return 1
  # Prefer File/Line or .cuf paths; reject SASS-only export (no high-level source).
  if head -1 "${csv}" | grep -qiE 'File|Line'; then
    grep -qiE '\.cuf|\.cu|\.f90' "${csv}" || return 1
  elif grep -qiE '\.cuf|\.cu|\.f90' "${csv}"; then
    :
  else
    # SASS-only: "Source" column holds instructions like SHF.R.U32 — not sufficient.
    grep -qE 'SHF\.|BSSY|LDG\.|STS\.' "${csv}" && return 1
    return 1
  fi
  awk -F, 'NR>1 && $0 !~ /^==/ {found=1} END{exit !found}' "${csv}" || return 1
  return 0
}

# Replay export: Stellar NCU cannot combine --import + --import-source + --source-folders
# (errors both ways). Source-folders is capture-only; replay uses embedded rep source
# and/or --resolve-source-file without --source-folders.
hackathon_ncu_write_source_csv() {
  local ncu_bin="$1"
  local rep="$2"
  local csv="$3"
  local workdir="$4"
  local primary strategy tmp err

  primary="${MINIRAM}/gpu/${NCU_DEFAULT_SOURCE:-gpu_hydro.cuf}"

  try_write() {
    local tag="$1"
    shift
    tmp="$(mktemp)"
    err="$(mktemp)"
    if ! "${ncu_bin}" "$@" --csv > "${tmp}" 2>"${err}"; then
      echo "   ${tag}: exit non-zero: $(head -1 "${err}")" >&2
      rm -f "${tmp}" "${err}"
      return 1
    fi
    if grep -q '^==ERROR==' "${tmp}"; then
      echo "   ${tag}: $(head -1 "${tmp}")" >&2
      rm -f "${tmp}" "${err}"
      return 1
    fi
    if ! head -1 "${tmp}" | grep -qiE 'File|Line|Address|derived__'; then
      echo "   ${tag}: unexpected header: $(head -1 "${tmp}")" >&2
      rm -f "${tmp}" "${err}"
      return 1
    fi
    rm -f "${err}"
    mv "${tmp}" "${csv}"
    strategy="${tag}"
    return 0
  }

  local -a page_args=(--import "${rep}" --page source)
  hackathon_ncu_source_page_args page_args

  if try_write cuda-sass "${page_args[@]}"; then
    printf '%s' "${strategy}"
    return 0
  fi
  if [[ -f "${primary}" ]] && try_write resolve \
      --import "${rep}" --page source --print-source cuda,sass \
      --kernel-name-base demangled --kernel-name "${NCU_KERNEL:-regex:.*hydro_integrator_kernel.*}" \
      --resolve-source-file "${primary}"; then
    printf '%s' "${strategy}"
    return 0
  fi
  # Last resort: SASS view (has L1 Conflicts columns but no .cuf lines).
  if try_write sass-only --import "${rep}" --page source --print-source sass \
      --kernel-name-base demangled --kernel-name "${NCU_KERNEL:-regex:.*hydro_integrator_kernel.*}"; then
    echo "WARNING: NCU source CSV is SASS-only (no gpu_hydro.cuf lines)" >&2
    printf '%s' "${strategy}"
    return 0
  fi
  return 1
}

# Path for capture-time source CSV (--import-source valid during capture, not replay).
hackathon_ncu_capture_source_csv_path() {
  local workdir="$1"
  local case_name="$2"
  printf '%s/profile_exports/ncu_%s_source.csv' "${workdir}" "${case_name}"
}

# Post-export source page CSV/SASS/counters.
hackathon_ncu_export_source_artifacts() {
  local rep="$1"
  local export_dir="$2"
  local case_name="$3"
  local ncu_bin="$4"
  local workdir="${5:-$(dirname "${rep}")}"
  local folders strategy src_args csv sass counters primary

  if [[ "${NCU_EXPORT_SOURCE:-0}" != "1" ]]; then
    return 0
  fi

  mkdir -p "${export_dir}"
  hackathon_setup_paths
  # Re-stage symlinks before export (scratch workdir holds default -> gpu_hydro.cuf).
  if [[ "${NCU_IMPORT_SOURCE:-no}" == "yes" ]]; then
    hackathon_ncu_stage_source_lookup "${workdir}"
  fi
  folders="$(hackathon_ncu_resolve_source_folders "${workdir}")" || folders=""
  primary="${MINIRAM}/gpu/${NCU_DEFAULT_SOURCE:-gpu_hydro.cuf}"

  csv="${export_dir}/ncu_${case_name}_source.csv"
  sass="${export_dir}/ncu_${case_name}_source_sass.txt"
  counters="${export_dir}/ncu_${case_name}_source_counters.txt"

  echo "== NCU source replay export (--import rep --page source)"
  echo "== NCU source CSV -> ${csv}"
  if ! strategy="$(hackathon_ncu_write_source_csv "${ncu_bin}" "${rep}" "${csv}" "${workdir}")"; then
    echo "WARNING: NCU source CSV export failed (rep still usable in ncu-ui)" >&2
    strategy=""
  elif hackathon_ncu_source_csv_ok "${csv}"; then
    echo "== NCU source CSV ok (strategy=${strategy})"
  else
    echo "WARNING: NCU source CSV has no resolved .cuf paths (rep still ok)" >&2
    head -5 "${csv}" 2>/dev/null >&2 || true
    strategy=""
  fi

  if [[ -n "${strategy}" ]]; then
    src_args=(--import "${rep}" --page source)
    hackathon_ncu_source_page_args src_args
    if [[ "${strategy}" == resolve ]]; then
      src_args+=(--resolve-source-file "${primary}")
    elif [[ "${strategy}" == sass-only ]]; then
      src_args=(--import "${rep}" --page source --print-source sass)
      hackathon_ncu_source_kernel_args src_args
    fi

    echo "== NCU source SASS -> ${sass}"
    "${ncu_bin}" "${src_args[@]}" > "${sass}" 2>/dev/null || true
  fi

  echo "== NCU source counters -> ${counters}"
  "${ncu_bin}" --import "${rep}" --print-details SourceCounters > "${counters}" 2>/dev/null || true
}

# Slurm --export string: pass PART_DEP_ALGO with an explicit value (ALL alone is
# unreliable on some clusters when the var is only exported, not on the sbatch line).
hackathon_sbatch_export() {
  local flags="ALL"
  local harness="${HARNESS_DIR:-${HARNESS:-}}"
  if [[ -n "${harness}" ]]; then
    flags="${flags},HARNESS_DIR=${harness}"
  fi
  if [[ -n "${PART_DEP_ALGO:-}" ]]; then
    flags="${flags},PART_DEP_ALGO=${PART_DEP_ALGO}"
  fi
  hackathon_setup_paths
  if [[ -n "${GPU_NPRE:-}" ]]; then
    flags="${flags},GPU_NPRE=${GPU_NPRE}"
  fi
  if [[ -n "${GPU_FASTMATH:-}" ]]; then
    flags="${flags},GPU_FASTMATH=${GPU_FASTMATH}"
  fi
  if [[ -n "${GPU_KICK_COOP_GATHER:-}" ]]; then
    flags="${flags},GPU_KICK_COOP_GATHER=${GPU_KICK_COOP_GATHER}"
  fi
  if [[ -n "${GPU_KICK_COOP_VALIDATE:-}" ]]; then
    flags="${flags},GPU_KICK_COOP_VALIDATE=${GPU_KICK_COOP_VALIDATE}"
  fi
  if [[ -n "${GPU_DUST_COOP_KICK:-}" ]]; then
    flags="${flags},GPU_DUST_COOP_KICK=${GPU_DUST_COOP_KICK}"
  fi
  if [[ -n "${GPU_DUST_KICK_BLOCKS_PER_SM:-}" ]]; then
    flags="${flags},GPU_DUST_KICK_BLOCKS_PER_SM=${GPU_DUST_KICK_BLOCKS_PER_SM}"
  fi
  if [[ -n "${GPU_HYDRO:-}" ]]; then
    flags="${flags},GPU_HYDRO=${GPU_HYDRO}"
  fi
  if [[ -n "${GPU_MHD:-}" ]]; then
    flags="${flags},GPU_MHD=${GPU_MHD}"
  fi
  if [[ -n "${GPU_TURB:-}" ]]; then
    flags="${flags},GPU_TURB=${GPU_TURB}"
  fi
  if [[ -n "${FFTW:-}" ]]; then
    flags="${flags},FFTW=${FFTW}"
  fi
  if [[ -n "${FFTW_HEADER_DIR:-}" ]]; then
    flags="${flags},FFTW_HEADER_DIR=${FFTW_HEADER_DIR}"
  fi
  if [[ -n "${FFTW_VENDOR_INC:-}" ]]; then
    flags="${flags},FFTW_VENDOR_INC=${FFTW_VENDOR_INC}"
  fi
  if [[ -n "${FFTW_MODULE:-}" ]]; then
    flags="${flags},FFTW_MODULE=${FFTW_MODULE}"
  fi
  if [[ -n "${GPU_NPSCAL:-}" ]]; then
    flags="${flags},GPU_NPSCAL=${GPU_NPSCAL}"
  fi
  if [[ -n "${GPU_GRAV:-}" ]]; then
    flags="${flags},GPU_GRAV=${GPU_GRAV}"
  fi
  if [[ -n "${GPU_CUDA_ARCH:-}" ]]; then
    flags="${flags},GPU_CUDA_ARCH=${GPU_CUDA_ARCH}"
  fi
  if [[ -n "${GPU_TARGETS:-}" ]]; then
    flags="${flags},GPU_TARGETS=${GPU_TARGETS}"
  fi
  if [[ -n "${CLUSTER:-}" ]]; then
    flags="${flags},CLUSTER=${CLUSTER}"
  fi
  if [[ -n "${GPU_PAPER:-}" ]]; then
    flags="${flags},GPU_PAPER=${GPU_PAPER}"
  fi
  # GPU_UNITS may be empty (omit UNITS= for pure-hydro/MHD tests); pass explicitly.
  if [[ -n "${GPU_UNITS+set}" ]]; then
    flags="${flags},GPU_UNITS=${GPU_UNITS}"
  fi
  if [[ -n "${BIN_GPU:-}" ]]; then
    flags="${flags},BIN_GPU=${BIN_GPU}"
  fi
  if [[ -n "${BUILD_BINARIES:-}" ]]; then
    flags="${flags},BUILD_BINARIES=${BUILD_BINARIES}"
  fi
  if [[ -n "${CLEAN:-}" ]]; then
    flags="${flags},CLEAN=${CLEAN}"
  fi
  if [[ -n "${GPU_BUILD_MINIMAL:-}" ]]; then
    flags="${flags},GPU_BUILD_MINIMAL=${GPU_BUILD_MINIMAL}"
  fi
  if [[ -n "${NVHPC_MODULE:-}" ]]; then
    flags="${flags},NVHPC_MODULE=${NVHPC_MODULE}"
  fi
  if [[ -n "${NVHPC_MODULE_STRICT:-}" ]]; then
    flags="${flags},NVHPC_MODULE_STRICT=${NVHPC_MODULE_STRICT}"
  fi
  if [[ -n "${GPU_MAKE_JOBS:-}" ]]; then
    flags="${flags},GPU_MAKE_JOBS=${GPU_MAKE_JOBS}"
  fi
  if [[ -n "${DMO_NO_DEFAULT_CAPS:-}" ]]; then
    flags="${flags},DMO_NO_DEFAULT_CAPS=${DMO_NO_DEFAULT_CAPS}"
  fi
  if [[ -n "${DMO_GPU_LAUNCH_BLOCKING:-}" ]]; then
    flags="${flags},DMO_GPU_LAUNCH_BLOCKING=${DMO_GPU_LAUNCH_BLOCKING}"
  fi
  if [[ -n "${IC_ZOOM_DIR:-}" ]]; then
    flags="${flags},IC_ZOOM_DIR=${IC_ZOOM_DIR}"
  fi
  if [[ -n "${IC_DIR:-}" ]]; then
    flags="${flags},IC_DIR=${IC_DIR}"
  fi
  # Pass the run caps explicitly (not just via ALL): a dropped DMO_TEND would make
  # dmo_gpu.slurm fall back to its cosmo default tend=3.0 (e.g. a periodic Brio-Wu
  # would run ~30x too long). Each is guarded so it is only added when set.
  if [[ -n "${DMO_TEND:-}" ]]; then
    flags="${flags},DMO_TEND=${DMO_TEND}"
  fi
  if [[ -n "${DMO_FOUTPUT:-}" ]]; then
    flags="${flags},DMO_FOUTPUT=${DMO_FOUTPUT}"
  fi
  if [[ -n "${DMO_NCACHEMAX:-}" ]]; then
    flags="${flags},DMO_NCACHEMAX=${DMO_NCACHEMAX}"
  fi
  if [[ -n "${DMO_NSTEPMAX:-}" ]]; then
    flags="${flags},DMO_NSTEPMAX=${DMO_NSTEPMAX}"
  fi
  if [[ -n "${DMO_NDUST_PER_CELL:-}" ]]; then
    flags="${flags},DMO_NDUST_PER_CELL=${DMO_NDUST_PER_CELL}"
  fi
  if [[ -n "${PROFILE:-}" ]]; then
    flags="${flags},PROFILE=${PROFILE}"
  fi
  if [[ -n "${NML:-}" ]]; then
    flags="${flags},NML=${NML}"
  fi
  if [[ -n "${GPU_LINEINFO:-}" ]]; then
    flags="${flags},GPU_LINEINFO=${GPU_LINEINFO}"
  fi
  if [[ -n "${NCU_KERNEL:-}" ]]; then
    flags="${flags},NCU_KERNEL=${NCU_KERNEL}"
  fi
  if [[ -n "${NCU_LAUNCH_SKIP:-}" ]]; then
    flags="${flags},NCU_LAUNCH_SKIP=${NCU_LAUNCH_SKIP}"
  fi
  if [[ -n "${NCU_LAUNCH_COUNT:-}" ]]; then
    flags="${flags},NCU_LAUNCH_COUNT=${NCU_LAUNCH_COUNT}"
  fi
  if [[ -n "${NCU_SET:-}" ]]; then
    flags="${flags},NCU_SET=${NCU_SET}"
  fi
  if [[ -n "${NCU_IMPORT_SOURCE:-}" ]]; then
    flags="${flags},NCU_IMPORT_SOURCE=${NCU_IMPORT_SOURCE}"
  fi
  if [[ -n "${NCU_EXPORT_SOURCE:-}" ]]; then
    flags="${flags},NCU_EXPORT_SOURCE=${NCU_EXPORT_SOURCE}"
  fi
  if [[ -n "${NCU_DEFAULT_SOURCE:-}" ]]; then
    flags="${flags},NCU_DEFAULT_SOURCE=${NCU_DEFAULT_SOURCE}"
  fi
  if [[ -n "${NCU_SOURCE_FOLDERS:-}" ]]; then
    flags="${flags},NCU_SOURCE_FOLDERS=${NCU_SOURCE_FOLDERS}"
  fi
  if [[ -n "${NCU_CASE_TAG:-}" ]]; then
    flags="${flags},NCU_CASE_TAG=${NCU_CASE_TAG}"
  fi
  printf '%s' "${flags}"
}

# hackathon_sbatch [sbatch-options...] job.slurm
hackathon_sbatch() {
  if (("$#" < 1)); then
    echo "ERROR: hackathon_sbatch: missing job script" >&2
    return 2
  fi
  hackathon_setup_paths
  local script="${!#}" script_base cluster_opts=()
  if [[ "${script}" != */* ]]; then
    script="$(hackathon_slurm_script "${script}")"
  fi
  script_base="$(basename "${script}")"
  if [[ "${script_base}" == dmo_cpu.slurm ]]; then
    cluster_opts=("${CLUSTER_SBATCH_CPU_OPTS[@]:-}")
  else
    cluster_opts=("${CLUSTER_SBATCH_GPU_OPTS[@]:-}")
  fi
  if (("$#" == 1)); then
    if ((${#cluster_opts[@]})); then
      sbatch --export="$(hackathon_sbatch_export)" "${cluster_opts[@]}" "${script}"
    else
      sbatch --export="$(hackathon_sbatch_export)" "${script}"
    fi
  else
    if ((${#cluster_opts[@]})); then
      sbatch --export="$(hackathon_sbatch_export)" "${cluster_opts[@]}" "${@:1:$#-1}" "${script}"
    else
      sbatch --export="$(hackathon_sbatch_export)" "${@:1:$#-1}" "${script}"
    fi
  fi
}

# prepare_case_nml TEMPLATE_NML CASE_NAME OUT_DIR
# Uses IC_DIR; optional PROFILE_NSTEPMAX (any case) and PHYS_* + PHYS_EXTEND (amr_l8).
# Optional PART_DEP_ALGO overrides part_dep_algo in the staged namelist.
hackathon_prepare_case_nml() {
  local template_nml="$1" case_name="$2" out_dir="$3"
  local out_nml="${out_dir}/run_profile_${case_name}.nml"
  local src="${template_nml}"
  local ic_init

  hackathon_stage_grafic_ic_symlink "${IC_DIR}" "${out_dir}"
  ic_init="$(hackathon_grafic_ic_link_name)"
  sed "s|^ initfile(1)=.*| initfile(1)='${ic_init}'|" "${template_nml}" > "${out_nml}.ic"
  src="${out_nml}.ic"

  if [[ -n "${PROFILE_NSTEPMAX:-}" ]]; then
    sed -E \
      -e "s/^[[:space:]]*nstepmax=.*/ nstepmax=${PROFILE_NSTEPMAX}/" \
      -e "s/^[[:space:]]*foutput=.*/ foutput=${PROFILE_FOUTPUT:-${PROFILE_NSTEPMAX}}/" \
      -e "s/^[[:space:]]*tend=.*/ tend=${PROFILE_TEND:-0.1}/" \
      "${src}" > "${out_nml}"
  elif [[ "${PHYS_EXTEND:-1}" -eq 1 && "${case_name}" == *amr_l8* ]]; then
    sed -E \
      -e "s/^[[:space:]]*nstepmax=.*/ nstepmax=${PHYS_NSTEPMAX:-50}/" \
      -e "s/^[[:space:]]*foutput=.*/ foutput=${PHYS_FOUTPUT:-10}/" \
      -e "s/^[[:space:]]*tend=.*/ tend=${PHYS_TEND:-1.0}/" \
      "${src}" > "${out_nml}"
  else
    cp "${src}" "${out_nml}"
  fi
  rm -f "${out_nml}.ic"
  hackathon_apply_part_dep_algo "${out_nml}"
  echo "${out_nml}"
}

hackathon_validate_inputs() {
  local path
  for path in "${BIN_GPU}" "${NML}"; do
    if [[ ! -e "${path}" ]]; then
      echo "ERROR: missing ${path}" >&2
      exit 2
    fi
  done
  if [[ ! -d "${IC_DIR}" ]]; then
    echo "ERROR: IC directory not found: ${IC_DIR}" >&2
    exit 2
  fi
}

hackathon_export_nsys_stats() {
  local rep="$1" out_dir="$2"
  mkdir -p "${out_dir}"
  local base="${out_dir}/$(basename "${rep}" .nsys-rep)"
  echo "== exporting nsys stats to ${out_dir}"
  nsys stats --force-export=true "${rep}" | tee "${base}_summary.txt"
  nsys stats --force-export=true --report nvtx_sum "${rep}" | tee "${base}_nvtx_sum.txt"
  nsys stats --force-export=true --report cuda_gpu_kern_sum "${rep}" | tee "${base}_kern_sum.txt"
  nsys stats --force-export=true --report cuda_api_sum "${rep}" | tee "${base}_api_sum.txt"
  if command -v sqlite3 >/dev/null 2>&1; then
    hackathon_query_cic_sqlite "${rep}" | tee "${base}_cic_launch_stats.txt"
  fi
}

hackathon_query_cic_sqlite() {
  local rep="$1"
  local sqlite="${rep%.nsys-rep}.sqlite"
  if [[ ! -f "${sqlite}" ]]; then
    nsys export --force-overwrite=true --type=sqlite --output="${sqlite%.sqlite}" "${rep}" >/dev/null 2>&1 || true
  fi
  if [[ ! -f "${sqlite}" ]]; then
    echo "WARNING: no sqlite sidecar for ${rep}" >&2
    return 1
  fi
  sqlite3 "${sqlite}" <<'SQL'
.headers on
.mode column
SELECT s.value AS kernel,
       COUNT(*) AS launches,
       ROUND(SUM(k.end - k.start)/1e9, 3) AS total_s,
       ROUND(AVG(k.end - k.start)/1e6, 2) AS avg_ms,
       ROUND(MIN(k.end - k.start)/1e6, 2) AS min_ms,
       ROUND(MAX(k.end - k.start)/1e6, 2) AS max_ms,
       ROUND(AVG(k.gridX), 0) AS avg_gridX,
       ROUND(AVG(k.blockX), 0) AS avg_blockX
FROM CUPTI_ACTIVITY_KIND_KERNEL k
JOIN StringIds s ON k.demangledName = s.id
WHERE s.value LIKE '%cic_block_reduce%'
GROUP BY s.value;
SQL
}
