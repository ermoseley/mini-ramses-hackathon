#!/usr/bin/env bash
# Submit ambipolar validation chain sequentially (build+run per INIT, no concurrent makes).
set -euo pipefail
HARNESS="${HARNESS_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
export CLUSTER="${CLUSTER:-stellar}"
# shellcheck source=bin/hackathon-env.sh
source "${HARNESS}/bin/hackathon-env.sh"

scancel -u "${USER}" -n ambidiff,ambigauss,alfven_ad 2>/dev/null || true

J1=$(./submit_profiles.sh ambi-diff 2>&1 | grep "Submitted batch job" | awk '{print $4}')
echo "ambi-diff -> ${J1}"
J2=$(DMO_SLURM_TIME=04:00:00 hackathon_sbatch --dependency=afterany:"${J1}" --time=04:00:00 \
  --export=ALL,GPU_INIT=BGAUSS,BIN_GPU="${MINIRAM}/bin/ramses3d.mhd.ambigauss",BUILD_BINARIES=1,NML="$(hackathon_nml ambigauss.nml)" \
  ambigauss_gpu.slurm 2>&1 | grep "Submitted batch job" | awk '{print $4}')
echo "ambi-gauss -> ${J2} (after ${J1})"
J3=$(DMO_SLURM_TIME=04:00:00 hackathon_sbatch --dependency=afterany:"${J2}" --time=04:00:00 \
  --export=ALL,GPU_INIT=ALFVENAD,BIN_GPU="${MINIRAM}/bin/ramses3d.mhd.alfvenad",BUILD_BINARIES=1,NML="$(hackathon_nml alfven_ad.nml)" \
  alfven_ad_gpu.slurm 2>&1 | grep "Submitted batch job" | awk '{print $4}')
echo "alfven-ad -> ${J3} (after ${J2})"
