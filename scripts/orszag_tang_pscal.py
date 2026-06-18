#!/usr/bin/env python3
"""Generate Orszag-Tang MHD grafic ICs with a checkerboard passive scalar.

Standard OT hydro + B fields (same as make_orszag_tang_ic.py / orszag_tang.py),
plus ic_pvar_00001 with primitive value 1 where (i even) or (j even), else 0 (k
ignored). Fortran-equivalent: (mod(i,2)==0) .or. (mod(j,2)==0) on 1-based
cell indices.

Usage:
  python orszag_tang_pscal.py 5 --size 1.0 --outdir /path/to/ic_ot_pscal_5_3d
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import numpy as np

_HERE = Path(__file__).resolve().parent


def _find_grafic_dir() -> Path:
    """Locate mini-ramses-dev/utils/py/grafic (grafic.py must exist)."""
    candidates: list[Path] = []
    for key in ("MINIRAM", "MINI_RAMSES"):
        root = os.environ.get(key)
        if root:
            candidates.append(Path(root) / "utils" / "py" / "grafic")
    candidates.extend(
        [
            Path.home() / "mini-ramses-dev" / "utils" / "py" / "grafic",
            _HERE.parent / "mini-ramses-dev" / "utils" / "py" / "grafic",
        ]
    )
    seen: set[str] = set()
    for d in candidates:
        key = str(d.resolve()) if d.exists() else str(d)
        if key in seen:
            continue
        seen.add(key)
        if (d / "grafic.py").is_file():
            return d
    msg = (
        "ERROR: cannot find mini-ramses-dev/utils/py/grafic/grafic.py\n"
        "Tried: " + ", ".join(str(c) for c in candidates) + "\n"
        "Set MINIRAM=/path/to/mini-ramses-dev (same checkout used for the GPU build)."
    )
    raise SystemExit(msg)


_GRAFIC_DIR = _find_grafic_dir()
if str(_GRAFIC_DIR) not in sys.path:
    sys.path.insert(0, str(_GRAFIC_DIR))

import grafic  # noqa: E402


def write_array(filename: str, array: np.ndarray, box_size_cu: float, *, as_int64: bool = False) -> None:
    g = grafic.Grafic()
    g.set_data(np.asarray(array))
    g.make_header(box_size_cu)
    if as_int64:
        g.write_int64(filename)
    else:
        g.write_float(filename)


def orszag_tang_fields(
    n1: int,
    n2: int,
    n3: int,
    *,
    rho0: float,
    p0: float,
    v_amp: float,
    b_amp: float,
):
    i = np.arange(n1, dtype=np.float64)
    j = np.arange(n2, dtype=np.float64)
    k = np.arange(n3, dtype=np.float64)
    x = (i + 0.5) / n1
    y = (j + 0.5) / n2
    X, Y, _Z = np.meshgrid(x, y, k, indexing="ij")

    two_pi = 2.0 * np.pi
    four_pi = 4.0 * np.pi

    d = np.full((n1, n2, n3), float(rho0), dtype=np.float32)
    p = np.full((n1, n2, n3), float(p0), dtype=np.float32)
    u = (-v_amp * np.sin(two_pi * Y)).astype(np.float32)
    v = (v_amp * np.sin(two_pi * X)).astype(np.float32)
    w = np.zeros((n1, n2, n3), dtype=np.float32)

    B0 = b_amp / np.sqrt(four_pi)
    bx = (-B0 * np.sin(two_pi * Y)).astype(np.float32)
    by = (B0 * np.sin(four_pi * X)).astype(np.float32)
    bz = np.zeros((n1, n2, n3), dtype=np.float32)
    return d, u, v, w, p, bx, by, bz


def checkerboard_pscal(n1: int, n2: int, n3: int) -> np.ndarray:
    """Passive scalar mass fraction: 1 where i or j is even (1-based), else 0."""
    i = np.arange(1, n1 + 1, dtype=np.int32)
    j = np.arange(1, n2 + 1, dtype=np.int32)
    I, J, _K = np.meshgrid(i, j, np.arange(n3), indexing="ij")
    return ((I % 2 == 0) | (J % 2 == 0)).astype(np.float32)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("lvl", type=int, help="Refinement level (grid size n=2^lvl)")
    ap.add_argument("--size", type=float, default=1.0, help="Box size in code units (default 1.0)")
    ap.add_argument("--rho0", type=float, default=(25.0 / (36.0 * np.pi)), help="Initial density")
    ap.add_argument("--p0", type=float, default=(5.0 / (12.0 * np.pi)), help="Initial pressure")
    ap.add_argument("--v_amp", type=float, default=1.0, help="Velocity amplitude")
    ap.add_argument("--b_amp", type=float, default=1.0, help="Magnetic field amplitude")
    ap.add_argument("--outdir", type=str, default=None, help="Output directory")
    args = ap.parse_args()

    n = 2 ** int(args.lvl)
    n1, n2, n3 = n, n, n
    L = float(args.size)

    d, u, v, w, p, bx, by, bz = orszag_tang_fields(
        n1, n2, n3, rho0=args.rho0, p0=args.p0, v_amp=args.v_amp, b_amp=args.b_amp
    )
    pscal = checkerboard_pscal(n1, n2, n3)

    if args.outdir is None:
        outdir = _HERE / f"ics_orszag_tang_pscal/ic_ot_pscal_{args.lvl}_3d"
    else:
        outdir = Path(args.outdir)
    os.makedirs(outdir, exist_ok=True)
    os.chdir(outdir)

    write_array("ic_d", d, L)
    write_array("ic_u", u, L)
    write_array("ic_v", v, L)
    write_array("ic_w", w, L)
    write_array("ic_p", p, L)
    # input_hydro_grafic.f90: ivar=6 -> title(1) -> ic_pvar_00001 (not ic_pvar_1)
    write_array("ic_pvar_00001", pscal, L)

    write_array("ic_bxleft", bx, L)
    write_array("ic_bxright", bx, L)
    write_array("ic_byleft", by, L)
    write_array("ic_byright", by, L)
    write_array("ic_bzleft", bz, L)
    write_array("ic_bzright", bz, L)

    print(f"Orszag-Tang + checkerboard passive scalar ICs written to: {outdir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
