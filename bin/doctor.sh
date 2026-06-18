#!/usr/bin/env bash
# Print resolved cluster harness configuration.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}"

# shellcheck source=/dev/null
source "${ROOT}/bin/hackathon-env.sh"

echo "== mini-ramses-hackathon doctor"
echo "CLUSTER=${CLUSTER} (${CLUSTER_NAME:-})"
echo "HARNESS_DIR=${HARNESS_DIR}"
echo "RUN_DIR=${RUN_DIR}"
echo "MINIRAM=${MINIRAM}"
echo "GPU_MAKEFILE=${GPU_MAKEFILE:-<unset>}"
echo "GPU_CUDA_ARCH=${GPU_CUDA_ARCH:-<unset>}"
echo "GPU_NPRE (default)=${GPU_NPRE_DEFAULT:-<unset>}"
echo "GPU_SLURM_TEST=${GPU_SLURM_TEST:-<unset>}"
echo "CLUSTER_SBATCH_GPU_OPTS=${CLUSTER_SBATCH_GPU_OPTS[*]:-<unset>}"
if [[ -d "${ROOT}/.git" ]]; then
  echo "git: $(git -C "${ROOT}" rev-parse --short HEAD 2>/dev/null) ($(git -C "${ROOT}" branch --show-current 2>/dev/null))"
fi
if [[ -d "${MINIRAM}/.git" ]]; then
  echo "MINIRAM: $(git -C "${MINIRAM}" rev-parse --short HEAD 2>/dev/null) branch=$(git -C "${MINIRAM}" branch --show-current 2>/dev/null)"
fi
echo "ics: (not in repo — harness generates under \${HARNESS_DIR}/ics_*)"
if command -v module >/dev/null 2>&1; then
  echo "module nvhpc: $(module list 2>&1 | grep -i nvhpc || echo 'not loaded')"
fi
