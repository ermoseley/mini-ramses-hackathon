#!/usr/bin/env python3
"""Plot z-slices of passive scalar from Orszag-Tang MHD AMR output (ot-pscal).

Composites AMR leaf cells the same way as plot_ot.py. Default variable is the
first passive scalar (ivar=9 for NPSCAL=1 MHD: rho, v, p, B, then pscal).

Example:
  python plot_ot_pscal.py --path /scratch/.../dmo_gpu_12345/orszag_tang_amr_pscal
  python plot_ot_pscal.py --path ./run --nouts 1 2 --outdir ./plots
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

import numpy as np

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

import ramses_output_io as rio
from plot_ot import _amr2map_z_slice, _import_miniramses


def _default_pscal_ivar(run_dir: Path, nout: int) -> int:
    """Return 1-based hydro output index of the first passive scalar (MHD: after B)."""
    header = run_dir / f"output_{nout:05d}" / "hydro_header.txt"
    if header.is_file():
        for line in header.read_text().splitlines():
            line = line.strip()
            if line.startswith("variable #") and (
                "scalar_" in line or "density_scalar_" in line or "passive" in line.lower()
            ):
                # e.g. 'variable # 9: scalar_1'
                try:
                    num = int(line.split("#", 1)[1].split(":", 1)[0].strip())
                    if num > 0:
                        return num
                except (IndexError, ValueError):
                    continue
    # MHD + one passive scalar: rho,v,p,B (8) then scalar_1 at 9.
    return 9


def z_slice_pscal(
    nout: int,
    path: Path,
    slice_frac: float = 0.5,
    ivar: int = 9,
    slice_thickness: float | None = None,
) -> tuple[np.ndarray, float, float, int]:
    """Return (pscal_xy, boxlen, time, lmax) for a z-normal slice in code units."""
    ram = _import_miniramses()
    c = ram.rd_cell(nout, path=str(path))
    if ivar < 1 or ivar > c.nvar:
        raise ValueError(f"--ivar {ivar} out of range (nvar={c.nvar})")
    pscal = c.u[ivar - 1]
    inf = ram.rd_info(nout, path=str(path))
    boxlen = float(inf.boxlen)
    time = float(inf.time)
    levelmin = int(inf.levelmin)
    lmax = int(inf.nlevelmax)
    if lmax <= 0:
        lmax = int(np.max(c.level))

    z_center = slice_frac * boxlen
    if slice_thickness is not None:
        half = slice_thickness / 2.0
    else:
        half = float(np.min(c.dx)) / 2.0
    zmin = z_center - half
    zmax = z_center + half

    image = _amr2map_z_slice(
        c.x[0],
        c.x[1],
        c.x[2],
        c.dx,
        c.level + 1,
        pscal,
        boxlen,
        levelmin,
        lmax,
        zmin,
        zmax,
    )
    return image, boxlen, time, lmax


def plot_slice(
    pscal: np.ndarray,
    boxlen: float,
    time: float,
    nout: int,
    out: Path,
    lmax: int,
) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, ax = plt.subplots(figsize=(7, 6))
    extent = (0.0, boxlen, 0.0, boxlen)
    display = np.asarray(pscal.T)
    im = ax.imshow(
        display,
        origin="lower",
        extent=extent,
        aspect="equal",
        cmap="binary",
        vmin=0.0,
        vmax=1.0,
        interpolation="nearest",
    )
    ax.set_xlabel("x")
    ax.set_ylabel("y")
    ax.set_title(
        rf"Passive scalar z-slice ($t={time:.3f}$, output {nout:05d}, lmax={lmax})"
    )
    plt.colorbar(im, ax=ax, shrink=0.85, label="passive scalar")
    fig.tight_layout()
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=150)
    plt.close(fig)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--path", type=Path, required=True, help="Run directory containing output_XXXXX")
    ap.add_argument(
        "--nouts",
        type=int,
        nargs="*",
        default=None,
        help="Snapshot indices (default: all output_* under --path)",
    )
    ap.add_argument("--outdir", type=Path, default=None, help="PNG output directory (default: <path>/ot_pscal_plots)")
    ap.add_argument(
        "--ivar",
        type=int,
        default=None,
        help="1-based hydro output variable (default: first scalar_* from hydro_header.txt, else 9)",
    )
    ap.add_argument("--slice-frac", type=float, default=0.5, help="z center as fraction of boxlen (default: 0.5)")
    ap.add_argument(
        "--slice-thickness",
        type=float,
        default=None,
        help="z slab thickness in code units (default: one finest leaf cell)",
    )
    args = ap.parse_args()

    run_dir = args.path.resolve()
    if not run_dir.is_dir():
        print(f"[FAIL] not a directory: {run_dir}")
        return 1

    nouts = args.nouts if args.nouts else rio.discover_output_nums(run_dir)
    if not nouts:
        print(f"[FAIL] no output_* snapshots under {run_dir}")
        return 1

    outdir = args.outdir or (run_dir / "ot_pscal_plots")

    for nout in nouts:
        snap = run_dir / f"output_{nout:05d}"
        if not snap.is_dir():
            print(f"[WARN] skipping missing {snap}")
            continue
        ivar = args.ivar if args.ivar is not None else _default_pscal_ivar(run_dir, nout)
        field, boxlen, time, lmax = z_slice_pscal(
            nout,
            run_dir,
            args.slice_frac,
            ivar,
            args.slice_thickness,
        )
        fmin = float(np.nanmin(field))
        fmax = float(np.nanmax(field))
        print(f"snapshot {nout:05d}: ivar={ivar} pscal min={fmin:.6g} max={fmax:.6g}")
        if fmax <= 0.0:
            print(
                "[WARN] passive scalar slice is all zero — check run.log for "
                "'Missing .../ic_pvar_00001' and output compilation.txt NPSCAL/NVAR"
            )
        out = outdir / f"ot_pscal_zslice_{nout:05d}_t{time:.3f}.png"
        plot_slice(field, boxlen, time, nout, out, lmax)
        print(f"wrote {out} (t={time:.6f}, lmax={lmax})")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
