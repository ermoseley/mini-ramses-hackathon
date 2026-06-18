#!/usr/bin/env python3
"""Sanity-check Orszag-Tang / ot-amr GPU output before plotting.

Separates (1) simulation wrote sane hydro data vs (2) miniramses mis-reads AMR.

Example:
  python check_ot_snapshot.py --path /scratch/.../dmo_work_12345/gpu_run
  MINIRAM=~/mini-ramses-dev python check_ot_snapshot.py --path ./output_parent
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import numpy as np

OT_RHO0 = 25.0 / (36.0 * np.pi)  # standard OT IC (code units)


def _read_info(path: Path) -> dict[str, float]:
    out: dict[str, float] = {}
    for line in path.read_text().splitlines():
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        try:
            out[k.strip()] = float(v.strip())
        except ValueError:
            pass
    return out


def _miniramses_has_bitmask_reader(mini_root: Path) -> bool:
    p = mini_root / "utils" / "py" / "miniramses.py"
    if not p.is_file():
        return False
    text = p.read_text()
    compact = text.replace(" ", "")
    has_new = "refined_int=transfer[ndim]" in compact and "nvar=ndim+1" in compact
    has_old = "nvar=ndim+2**ndim" in compact or "transfer[ndim+ind]" in compact
    return has_new and not has_old


def _raw_hydro_header(hydro0: Path) -> tuple[int, int, int, int]:
    ndim = int(np.fromfile(hydro0, dtype=np.int32, count=1, offset=0)[0])
    nprim = int(np.fromfile(hydro0, dtype=np.int32, count=1, offset=4)[0])
    levelmin = int(np.fromfile(hydro0, dtype=np.int32, count=1, offset=8)[0])
    nlevelmax = int(np.fromfile(hydro0, dtype=np.int32, count=1, offset=12)[0])
    return ndim, nprim, levelmin, nlevelmax


def _raw_hydro_rho_sample(hydro0: Path, nprim: int, levelmin: int, nlevelmax: int, max_vals: int = 50000) -> np.ndarray:
    """First-oct density samples without AMR (unigrid sanity)."""
    header = 16 + 4 * (nlevelmax - levelmin + 1)
    nvartot = nprim * 8
    n = min(max_vals, nvartot)
    raw = np.fromfile(hydro0, dtype=np.float32, count=n, offset=header)
    # layout (ncache, nvar, 8) with nvar=nprim; density is ivar=0
    return raw[0:nvartot:8][: n // 8]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", type=Path, required=True, help="Run dir or gpu_run/ containing output_XXXXX")
    ap.add_argument("--nout", type=int, default=1, help="Snapshot index (default: 1)")
    args = ap.parse_args()

    run = args.path.resolve()
    snap = run / f"output_{args.nout:05d}"
    if not snap.is_dir():
        # common harness layout: workdir/gpu_run/output_*
        alt = run / "gpu_run" / f"output_{args.nout:05d}"
        if alt.is_dir():
            snap = alt
        else:
            print(f"[FAIL] no output_{args.nout:05d} under {run} or {run}/gpu_run")
            return 1

    info_path = snap / "info.txt"
    hydro0 = snap / "hydro.00001"
    if not info_path.is_file() or not hydro0.is_file():
        print(f"[FAIL] missing info.txt or hydro.00001 in {snap}")
        return 1

    info = _read_info(info_path)
    mini = Path(os.environ.get("MINIRAM", os.environ.get("MINI_RAMSES", Path.home() / "mini-ramses-dev")))
    ndim, nprim, file_lmin, file_lmax = _raw_hydro_header(hydro0)

    print(f"snapshot: {snap}")
    print(f"MINIRAM: {mini}")
    print(f"info: time={info.get('time', '?')} levelmin={info.get('levelmin', '?')} "
          f"nlevelmax={info.get('nlevelmax', info.get('levelmax', '?'))} ncpu={info.get('ncpu', '?')}")
    print(f"hydro header: ndim={ndim} nprim={nprim} levelmin={file_lmin} nlevelmax={file_lmax}")
    print(f"expected MHD nprim=8 when NVAR=5; nprim=11 means NVAR=8 build still active")

    bitmask_ok = _miniramses_has_bitmask_reader(mini)
    head = ""
    try:
        import subprocess

        r = subprocess.run(
            ["git", "-C", str(mini), "rev-parse", "--short", "HEAD"],
            capture_output=True,
            text=True,
            timeout=5,
        )
        if r.returncode == 0:
            head = r.stdout.strip()
    except OSError:
        pass
    if head:
        print(f"mini-ramses-dev HEAD: {head}")
    print(
        f"miniramses bitmask reader: {'OK' if bitmask_ok else 'MISSING (need utils/py/miniramses.py from gpu_mhd with packed refined_int)'}"
    )
    if not bitmask_ok:
        print("[WARN] stale miniramses reads 8 logicals/oct; current RAMSES packs refined into one int → garbage plots")

    rho_raw = _raw_hydro_rho_sample(hydro0, nprim, file_lmin, file_lmax)
    if rho_raw.size:
        t = info.get("time", -1.0)
        print(f"raw hydro rho (first oct cells): min={rho_raw.min():.6g} max={rho_raw.max():.6g} mean={rho_raw.mean():.6g}")
        print(f"OT IC reference rho0={OT_RHO0:.6g} (only meaningful at t≈0)")
        if t < 1e-12:
            if abs(rho_raw.mean() - OT_RHO0) > 0.05:
                print("[FAIL] raw hydro density does not match OT IC — simulation or IC path suspect")
            else:
                print("[OK] raw hydro density matches OT IC at t=0")
        else:
            print(f"[INFO] t={t:.4g} — skipped IC check (evolved state; raw sample is one oct only)")

    if not bitmask_ok:
        print("[WARN] with a stale AMR reader, rd_cell min/max/mean can look fine while plots are spatially scrambled")

    utils_py = mini / "utils" / "py"
    if (utils_py / "miniramses.py").is_file():
        sys.path.insert(0, str(utils_py))
        try:
            import miniramses as ram  # noqa: WPS433

            c = ram.rd_cell(args.nout, path=str(snap.parent))
            rho = c.u[0]
            lev = c.level.astype(np.int32, copy=False)
            print(f"rd_cell: nvar={c.nvar} ncell={c.ncell} rho min/max/mean="
                  f"{rho.min():.6g}/{rho.max():.6g}/{rho.mean():.6g} "
                  f"level [{lev.min()}, {lev.max()}]")
            finite = np.isfinite(rho).mean()
            if finite < 0.99:
                print(f"[FAIL] rd_cell rho non-finite fraction {1 - finite:.4g}")
                return 1
            if rho.max() > 1e4 or rho.min() < 0:
                print("[WARN] rd_cell rho range extreme — check units or corrupt hydro")
        except Exception as exc:
            print(f"[WARN] rd_cell failed: {exc}")
    else:
        print(f"[WARN] miniramses not found under {utils_py}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
