#!/usr/bin/env bash
# Mac host helpers for Nsight Compute report analysis (GUI-only on macOS).
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hackathon_common.sh
source "${HARNESS_DIR}/hackathon_common.sh"
hackathon_setup_paths

NCU_UI_APP="/Applications/NVIDIA Nsight Compute.app"
NCU_UI_BIN="${NCU_UI_APP}/Contents/MacOS/ncu-ui"
NCU_LINUX_BIN="${NCU_UI_APP}/Contents/Resources/target/linux-desktop-glibc_2_11_3-x64/ncu"

hackathon_mac_ncu_ui_bin() {
  [[ -x "${NCU_UI_BIN}" ]] && printf '%s' "${NCU_UI_BIN}"
}

hackathon_mac_ncu_detect() {
  if [[ "$(uname -s)" != "Darwin" ]]; then
    return 1
  fi
  if [[ -x "${NCU_UI_BIN}" ]]; then
    echo "ncu-ui: ${NCU_UI_BIN}"
    "${NCU_UI_BIN}" --version 2>&1 | head -1
    echo "note: macOS host has ncu-ui only (no native ncu CLI for --import --csv)"
    echo "      bundled Linux ncu exists but cannot run on macOS: ${NCU_LINUX_BIN}"
    return 0
  fi
  echo "ERROR: install Nsight Compute for MacOS-arm64 from developer.nvidia.com/nsight-compute" >&2
  return 1
}

# Open .ncu-rep in ncu-ui. Optional: workdir with staged .cuf symlinks for source lookup.
open_ncu_report() {
  local rep="${1:?usage: mac_ncu.sh open REP.ncu-rep [workdir]}"
  local workdir="${2:-$(dirname "${rep}")}"
  local ui
  ui="$(hackathon_mac_ncu_ui_bin)" || {
    echo "ERROR: ncu-ui not found at ${NCU_UI_BIN}" >&2
    exit 1
  }
  if [[ ! -f "${rep}" ]]; then
    echo "ERROR: report not found: ${rep}" >&2
    exit 1
  fi
  hackathon_ncu_stage_source_lookup "${workdir}" 2>/dev/null || true
  echo "== open NCU report in GUI"
  echo "   ui:      ${ui}"
  echo "   rep:     ${rep}"
  echo "   workdir: ${workdir}"
  echo "   source:  ${MINIRAM}/gpu/gpu_hydro.cuf"
  echo ""
  echo "In ncu-ui: select kernel hydro_device_hydro_integrator_kernel_, Source page."
  echo "If lines missing: File -> Preferences -> Source -> add ${MINIRAM}/gpu"
  exec "${ui}" --shared-instance 1 "${rep}"
}

# Quick check: embedded lineinfo in .ncu-rep (works without ncu CLI).
embedded_source_lines() {
  local rep="${1:?usage: mac_ncu.sh lines REP.ncu-rep}"
  if [[ ! -f "${rep}" ]]; then
    echo "ERROR: report not found: ${rep}" >&2
    exit 1
  fi
  echo "== embedded gpu_hydro.cuf line markers in ${rep}"
  strings "${rep}" | grep -oE 'source:gpu_hydro\.cuf:[0-9]+' \
    | sed 's/source:gpu_hydro.cuf://' | sort -n | uniq -c | sort -rn
}

case "${1:-}" in
  detect) hackathon_mac_ncu_detect ;;
  open) shift; open_ncu_report "$@" ;;
  lines) shift; embedded_source_lines "$@" ;;
  *)
    cat <<EOF
Usage:
  $(basename "$0") detect
  $(basename "$0") open  PATH/TO/report.ncu-rep [workdir]
  $(basename "$0") lines PATH/TO/report.ncu-rep

Mac NCU is GUI-only. Use 'open' for interactive source localization.
Use 'lines' for a quick embedded-lineinfo scan (no GUI).
EOF
    ;;
esac
