#!/usr/bin/env bash
# Validate NCU source localization before pulling artifacts or starting optimization.
#
# Usage (on Stellar login node, after ncu-ot-localize finishes):
#   REP=/scratch/gpfs/$USER/hackathon/dmo_gpu_JOBID/orszag_tang_l7/ncu_orszag_tang_l7.ncu-rep
#   WD=/scratch/gpfs/$USER/hackathon/dmo_gpu_JOBID/orszag_tang_l7
#   ./validate_ncu_source.sh "$REP" "$WD"
# (Job outputs live under RUN_DIR, typically scratch — not ~/hackathon unless that is your cwd.)
#
# Optional second arg: job workdir (defaults to dirname of .ncu-rep).
# Exit 0 = source CSV looks usable; exit 1 = blocked (do not optimize blind).

set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=hackathon_common.sh
source "${HARNESS_DIR}/hackathon_common.sh"
hackathon_setup_paths

REP="${1:?usage: validate_ncu_source.sh PATH/TO/report.ncu-rep [workdir]}"
WORKDIR="${2:-$(dirname "${REP}")}"

NCU_BIN="${NCU_BIN:-$(command -v ncu || true)}"
for candidate in \
    "/opt/nvidia/hpc_sdk/Linux_x86_64/25.5/compilers/bin/ncu"; do
  [[ -x "${candidate}" && -z "${NCU_BIN}" ]] && NCU_BIN="${candidate}"
done
if [[ -z "${NCU_BIN}" || ! -x "${NCU_BIN}" ]]; then
  echo "ERROR: ncu not found" >&2
  exit 1
fi

if [[ ! -f "${REP}" ]]; then
  echo "ERROR: report not found: ${REP}" >&2
  exit 1
fi

FOLDERS="$(hackathon_ncu_resolve_source_folders "${WORKDIR}" 2>/dev/null || true)"
PRIMARY="${MINIRAM}/gpu/${NCU_DEFAULT_SOURCE:-gpu_hydro.cuf}"

echo "== validate_ncu_source"
echo "   ncu:     $("${NCU_BIN}" --version 2>&1 | head -1)"
echo "   rep:     ${REP}"
echo "   workdir: ${WORKDIR}"
echo "   folders: ${FOLDERS:-<none>}"
echo "   primary: ${PRIMARY}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
  exit 0
}

tmpdir="$(mktemp -d)"
trap 'rm -rf "${tmpdir}"' EXIT

try_csv() {
  local tag="$1"
  shift
  local out="${tmpdir}/${tag}.csv"
  echo "--- try: ${tag} ---"
  if ! "${NCU_BIN}" "$@" --csv > "${out}" 2>"${tmpdir}/${tag}.err"; then
    echo "   exit non-zero"
    cat "${tmpdir}/${tag}.err" >&2 || true
    return 1
  fi
  if grep -q '^==ERROR==' "${out}"; then
    echo "   ==ERROR== in output:"
    head -3 "${out}" >&2
    return 1
  fi
  head -1 "${out}"
  wc -l < "${out}" | awk '{print "   lines:", $1}'
  cp "${out}" "${tmpdir}/best.csv"
  return 0
}

CAPTURE_CSV="${WORKDIR}/profile_exports/$(basename "${REP}" .ncu-rep)_source.csv"
best=""
NCU_KERNEL="${NCU_KERNEL:-regex:.*hydro_integrator_kernel.*}"
if hackathon_ncu_source_csv_ok "${CAPTURE_CSV}" 2>/dev/null; then
  echo "--- using replay/post-export CSV: ${CAPTURE_CSV} ---"
  cp "${CAPTURE_CSV}" "${tmpdir}/best.csv"
  best="post-export"
elif try_csv "cuda-sass" --import "${REP}" --page source --print-source cuda,sass \
    --kernel-name-base demangled --kernel-name "${NCU_KERNEL}"; then
  best="cuda-sass"
elif [[ -f "${PRIMARY}" ]] && try_csv "resolve" --import "${REP}" --page source \
    --print-source cuda,sass --kernel-name-base demangled --kernel-name "${NCU_KERNEL}" \
    --resolve-source-file "${PRIMARY}"; then
  best="resolve"
else
  fail "replay export failed; open rep in ncu-ui or scp profile_exports/*_source.csv"
fi

csv="${tmpdir}/best.csv"
header="$(head -1 "${csv}")"
if ! grep -qiE 'File|Line|Address' <<< "${header}"; then
  fail "CSV from '${best}' lacks File/Line/Address columns. Header: ${header}"
fi

if ! grep -qiE '\.cuf|\.cu|\.f90' "${csv}"; then
  fail "CSV has no .cuf/.cu/.f90 paths — source not resolved. Try opening rep in ncu-ui."
fi

if ! awk -F, 'NR>1 && $0 !~ /^==/ {found=1} END{exit !found}' "${csv}"; then
  fail "CSV has header only (no data rows)"
fi

echo "--- top shared-excess rows (if column present) ---"
if grep -q 'derived__memory_l1_wavefronts_shared_excessive' "${csv}"; then
  python3 - <<'PY' "${csv}" 2>/dev/null || true
import csv, sys
path = sys.argv[1]
with open(path, newline='') as f:
    rows = list(csv.DictReader(f))
col = 'derived__memory_l1_wavefronts_shared_excessive'
file_col = next((c for c in rows[0] if c.lower() == 'file'), 'File')
line_col = next((c for c in rows[0] if c.lower() == 'line'), 'Line')
def key(r):
    try: return float(r.get(col, 0) or 0)
    except: return 0
for r in sorted(rows, key=key, reverse=True)[:8]:
    print(f"  {r.get(file_col,'?')}:{r.get(line_col,'?')}  {col}={r.get(col,'?')}")
PY
else
  head -5 "${csv}"
fi

pass "source CSV usable (strategy=${best}). Safe to scp profile_exports/ and optimize."
