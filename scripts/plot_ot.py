#!/usr/bin/env python3
"""Plot z-slices of density from Orszag-Tang MHD output snapshots.

Composites AMR leaf cells following the spirit of ``amr2map.f90``: deposit each
level onto its native ``2**level`` grid with z-slab overlap weights, then sum
coarse maps onto the ``levelmax`` grid (unrefined regions keep coarse leaves;
refined regions use fine leaves). No ``mk_cube`` upsampling; ``imshow`` uses
``interpolation='nearest'``.

Example:
  python plot_ot.py --path /scratch/.../dmo_work_12345
  python plot_ot.py --path ./run --nouts 1 2 --outdir ./plots
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


def _import_miniramses():
    _default_mini = _HERE.parent / "mini-ramses-dev"
    mini_root = Path(os.environ.get("MINIRAM", os.environ.get("MINI_RAMSES", str(_default_mini))))
    utils_py = mini_root / "utils" / "py"
    if (utils_py / "miniramses.py").is_file():
        sys.path.insert(0, str(utils_py))
    else:
        sys.path.insert(0, str(mini_root))
    import miniramses as ram

    return ram


def _amr2map_z_slice(
    x: np.ndarray,
    y: np.ndarray,
    z: np.ndarray,
    dx: np.ndarray,
    level: np.ndarray,
    values: np.ndarray,
    boxlen: float,
    levelmin: int,
    lmax: int,
    zmin: float,
    zmax: float,
) -> np.ndarray:
    """Build an x-y map at resolution 2**lmax (amr2map-style composite)."""
    maps: dict[int, np.ndarray] = {}
    weights: dict[int, np.ndarray] = {}
    for lev in range(levelmin, lmax + 1):
        n = 2 ** lev
        maps[lev] = np.zeros((n, n), dtype=np.float64)
        weights[lev] = np.zeros((n, n), dtype=np.float64)

    zzspan = max(zmax - zmin, 1e-30 * boxlen)
    zzmin_n = zmin / boxlen
    zzmax_n = zmax / boxlen

    lev = level.astype(np.int32, copy=False)
    zz = z / boxlen
    dz = dx / boxlen
    # z overlap weight in [0, 1], as in amr2map (proj along z).
    overlap = (np.minimum(zz + dz / 2.0, zzmax_n) - np.maximum(zz - dz / 2.0, zzmin_n)) / dz
    overlap = np.clip(overlap, 0.0, 1.0)
    w = dz * overlap / (zzspan / boxlen)

    valid = (lev >= levelmin) & (lev <= lmax) & (w > 0.0)
    if not np.any(valid):
        ln = 2 ** lmax
        return np.zeros((ln, ln), dtype=np.float32)

    x_v = x[valid]
    y_v = y[valid]
    lev_v = lev[valid]
    val_v = values[valid]
    w_v = w[valid]

    for ilev in range(levelmin, lmax + 1):
        m = lev_v == ilev
        if not np.any(m):
            continue
        n = 2 ** ilev
        ix = np.floor(x_v[m] / boxlen * n).astype(np.int32)
        iy = np.floor(y_v[m] / boxlen * n).astype(np.int32)
        ix = np.clip(ix, 0, n - 1)
        iy = np.clip(iy, 0, n - 1)
        np.add.at(maps[ilev], (ix, iy), val_v[m] * w_v[m])
        np.add.at(weights[ilev], (ix, iy), w_v[m])

    ln = 2 ** lmax
    out_map = maps[lmax].copy()
    out_w = weights[lmax].copy()

    # Sum coarse-level maps onto the lmax grid (amr2map lines 390-408).
    for ilevel in range(levelmin, lmax):
        ndom = 2 ** ilevel
        x_norm = (np.arange(ln) + 0.5) / ln
        ic = np.clip((x_norm * ndom).astype(np.int32), 0, ndom - 1)
        jc = np.clip((x_norm * ndom).astype(np.int32), 0, ndom - 1)
        out_map += maps[ilevel][ic[:, None], jc[None, :]]
        out_w += weights[ilevel][ic[:, None], jc[None, :]]

    with np.errstate(invalid="ignore", divide="ignore"):
        image = np.where(out_w > 0.0, out_map / out_w, 0.0)
    return image.astype(np.float32)


def z_slice_density(
    nout: int,
    path: Path,
    slice_frac: float = 0.5,
    ivar: int = 1,
    slice_thickness: float | None = None,
) -> tuple[np.ndarray, float, float, int]:
    """Return (rho_xy, boxlen, time, lmax) for a z-normal slice in code units."""
    ram = _import_miniramses()
    c = ram.rd_cell(nout, path=str(path))
    if ivar < 1 or ivar > c.nvar:
        raise ValueError(f"--ivar {ivar} out of range (nvar={c.nvar})")
    rho = c.u[ivar - 1]
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

    # miniramses.rd_cell returns 0-based levels (base grid == levelmin-1), but
    # info.levelmin/nlevelmax and the composite below assume 1-based physical
    # levels (n = 2**level cells per dim).  Convert so the base grid is kept
    # instead of being filtered out into black voids.
    image = _amr2map_z_slice(
        c.x[0],
        c.x[1],
        c.x[2],
        c.dx,
        c.level + 1,
        rho,
        boxlen,
        levelmin,
        lmax,
        zmin,
        zmax,
    )
    return image, boxlen, time, lmax


def plot_slice(
    rho: np.ndarray,
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
    # image[i_x, i_y]; imshow rows are y and columns are x.
    display = np.asarray(rho.T)
    vmax = float(np.nanmax(display))
    if vmax <= 0.0:
        vmax = 1.0
    im = ax.imshow(
        display,
        origin="lower",
        extent=extent,
        aspect="equal",
        cmap="magma",
        vmin=0.0,
        vmax=vmax,
        interpolation="nearest",
    )
    ax.set_xlabel("x")
    ax.set_ylabel("y")
    ax.set_title(
        rf"Orszag-Tang density z-slice ($t={time:.3f}$, output {nout:05d}, lmax={lmax})"
    )
    plt.colorbar(im, ax=ax, shrink=0.85, label=r"$\rho$")
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
    ap.add_argument("--outdir", type=Path, default=None, help="PNG output directory (default: <path>/ot_plots)")
    ap.add_argument("--ivar", type=int, default=1, help="1-based hydro variable (1 = density)")
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

    outdir = args.outdir or (run_dir / "ot_plots")

    for nout in nouts:
        snap = run_dir / f"output_{nout:05d}"
        if not snap.is_dir():
            print(f"[WARN] skipping missing {snap}")
            continue
        rho, boxlen, time, lmax = z_slice_density(
            nout,
            run_dir,
            args.slice_frac,
            args.ivar,
            args.slice_thickness,
        )
        out = outdir / f"ot_density_zslice_{nout:05d}_t{time:.3f}.png"
        plot_slice(rho, boxlen, time, nout, out, lmax)
        print(f"wrote {out} (t={time:.6f}, lmax={lmax})")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
