# Sourced by SLURM batch scripts. Slurm runs a copy under /var/spool/slurmd/...;
# use SLURM_SUBMIT_DIR or HARNESS_DIR (set at submit), not BASH_SOURCE[0].

_hackathon_harness="${HARNESS_DIR:-${SLURM_SUBMIT_DIR:-}}"
if [[ -z "${_hackathon_harness}" || ! -f "${_hackathon_harness}/hackathon_common.sh" ]]; then
  echo "ERROR: hackathon_common.sh not found." >&2
  echo "       Submit from the hackathon directory: cd \$HARNESS_DIR && sbatch ..." >&2
  echo "       SLURM_SUBMIT_DIR=${SLURM_SUBMIT_DIR:-unset} HARNESS_DIR=${HARNESS_DIR:-unset}" >&2
  exit 2
fi
export HARNESS_DIR="${_hackathon_harness}"
SCRIPT_DIR="${_hackathon_harness}"
if [[ -f "${_hackathon_harness}/bin/hackathon-env.sh" && -n "${CLUSTER:-}" ]]; then
  # shellcheck source=/dev/null
  source "${_hackathon_harness}/bin/hackathon-env.sh"
else
  # shellcheck source=hackathon_common.sh
  source "${_hackathon_harness}/hackathon_common.sh"
  hackathon_setup_paths
fi
