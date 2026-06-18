#!/usr/bin/env bash
# NVHPC-only bisect helper for debug-cosmo (login-node build, GPU run via ~/use run).
set -euo pipefail

SHA="${1:?usage: bisect_cosmo.sh SHA tag [timeout_sec]}"
TAG="${2:?usage: bisect_cosmo.sh SHA tag [timeout_sec]}"
TIMEOUT_SEC="${3:-600}"

HARNESS_DIR="${HARNESS_DIR:-/scratch/gpfs/moseley/hackathon}"
MINIRAM="${MINIRAM:-${HOME}/mini-ramses-dev}"
MAKEFILE="${HARNESS_DIR}/makefiles/Makefile.debug-cosmo"
NML="${HARNESS_DIR}/namelists/debug_cosmo.nml"
BISECT_ROOT="${HARNESS_DIR}/use_debug/bisect"
WORKDIR="${HARNESS_DIR}/use_debug"
IC_DIR="${IC_DIR:-${HARNESS_DIR}/ics_ramses}"

module load nvhpc/25.5
unset NVCOMPILER_TERM NVCOMPILER_FPE MAKEFLAGS
export NVHPC_MODULE_STRICT=1
export NVHPC_CUDA_HOME=/opt/nvidia/hpc_sdk/Linux_x86_64/25.5/cuda/12.9
export NVHPC_MATH_LIB=/opt/nvidia/hpc_sdk/Linux_x86_64/25.5/math_libs/lib64

mkdir -p "${BISECT_ROOT}" "${WORKDIR}"

echo "=== BUILD ${TAG} (${SHA}) $(date -Is) ==="
cd "${MINIRAM}"
git checkout -q "${SHA}"
echo "HEAD: $(git log -1 --oneline)"
cd bin
make -f "${MAKEFILE}" -j1 clean
make -f "${MAKEFILE}" -j1 \
  COMPILER=NVHPC NDIM=3 HYDRO=1 GRAV=1 UNITS=COSMO CUDA_ARCH=sm_80 \
  NVHPC_CUDA_HOME="${NVHPC_CUDA_HOME}" NVHPC_MATH_LIB="${NVHPC_MATH_LIB}" ramses
cp -f ramses3d ramses3d.hydro

echo "--- ldd ${TAG} ---"
ldd ramses3d.hydro | grep -E 'cudafor|25.5' | head -6 | tee "${BISECT_ROOT}/ldd_${TAG}.txt"
strings ramses3d.hydro | grep BUILDCOMMAND | head -1 | tee "${BISECT_ROOT}/buildcmd_${TAG}.txt"

echo "=== RUN ${TAG} on GPU hold timeout=${TIMEOUT_SEC}s ==="
~/use run bash -lc "
  module load nvhpc/25.5
  unset NVCOMPILER_TERM
  export HARNESS_DIR='${HARNESS_DIR}' MINIRAM='${MINIRAM}' IC_DIR='${IC_DIR}'
  cd '${WORKDIR}'
  source '${HARNESS_DIR}/hackathon_common.sh'
  hackathon_stage_dmo_run_nml '${NML}' input.nml
  LOG='${BISECT_ROOT}/run_${TAG}.log'
  echo '=== RUN ${TAG} \$(date -Is) ===' | tee \"\$LOG\"
  timeout ${TIMEOUT_SEC} '${MINIRAM}/bin/ramses3d.hydro' input.nml >> \"\$LOG\" 2>&1 || echo exit=\$? >> \"\$LOG\"
  grep 'Main step=' \"\$LOG\" | tail -1
  grep 'Fine step=' \"\$LOG\" | tail -1
"

python3 - "${BISECT_ROOT}/run_${TAG}.log" "${BISECT_ROOT}/summary_${TAG}.txt" "${TAG}" <<'PY'
import re, sys
log, out, tag = sys.argv[1], sys.argv[2], sys.argv[3]
lines = open(log).read().splitlines()
collapse = None
for ln in lines:
    m = re.search(r"Fine step=\s*(\d+).*dt=\s*([0-9.Ee+-]+).*a=\s*([0-9.Ee+-]+)", ln)
    if m and float(m.group(3)) > 0.15 and float(m.group(2)) < 1e-9:
        collapse = ln
        break
main = [ln for ln in lines if "Main step=" in ln]
fine = [ln for ln in lines if "Fine step=" in ln]
with open(out, "w") as f:
    f.write(f"tag={tag}\n")
    f.write(f"main_last={main[-1] if main else 'none'}\n")
    f.write(f"fine_last={fine[-1] if fine else 'none'}\n")
    f.write(f"collapse={collapse or 'none'}\n")
print(open(out).read())
PY
