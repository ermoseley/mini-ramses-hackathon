#!/usr/bin/env python3
"""Log column density in the x-z plane with density-weighted B-field hatch lines.

Reads a mini-ramses MHD snapshot via ``miniramses.rd_cell``, integrates gas density
along the line-of-sight axis (default **y**), and overlays short in-plane magnetic
field segments (Bx, Bz) weighted by rho along the column.

Examples
--------
  python3 plot_mhd_turb_column_xz.py \\
      --run-dir /scratch/gpfs/moseley/hackathon/mhd_turb_l8_a200_beta01 \\
      --output-id 3 --no-display

  python3 plot_mhd_turb_column_xz.py --run-dir ./run --out column_xz.png
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

import numpy as np

_HERE = Path(__file__).resolve().parent
OUTPUT_RE = re.compile(r"^output_(\d+)$")

# MHD primitive layout from hydro/output_hydro.f90 (0-based indices in rd_cell).
IVAR_RHO = 0
IVAR_BX = 5
IVAR_BY = 6
IVAR_BZ = 7


def _import_miniramses():
    default_mini = _HERE.parent / "mini-ramses-dev"
    mini_root = Path(os.environ.get("MINIRAM", os.environ.get("MINI_RAMSES", str(default_mini))))
    utils_py = mini_root / "utils" / "py"
    if (utils_py / "miniramses.py").is_file():
        sys.path.insert(0, str(utils_py))
    else:
        sys.path.insert(0, str(mini_root))
    import miniramses as ram

    return ram


def _projection_indices(axis: str) -> tuple[int, int, int]:
    """Return (i_horiz1, i_horiz2, i_los) for axis in {x,y,z}."""
    if axis == "x":
        return 1, 2, 0  # y-z map, integrate along x
    if axis == "y":
        return 0, 2, 1  # x-z map, integrate along y
    return 0, 1, 2  # x-y map, integrate along z


def _axis_labels(axis: str) -> tuple[str, str]:
    if axis == "x":
        return "y", "z"
    if axis == "y":
        return "x", "z"
    return "x", "y"


def _amr2map_column(
    x: np.ndarray,
    y: np.ndarray,
    z: np.ndarray,
    dx: np.ndarray,
    level: np.ndarray,
    rho: np.ndarray,
    bx: np.ndarray,
    bz_inplane: np.ndarray,
    boxlen: float,
    levelmin: int,
    lmax: int,
    axis: str,
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """Column-integrate rho and rho-weighted in-plane B onto the transverse plane."""
    coords = (x, y, z)
    i1, i2, i_los = _projection_indices(axis)
    horiz1 = coords[i1]
    horiz2 = coords[i2]

    maps_rho: dict[int, np.ndarray] = {}
    maps_b1: dict[int, np.ndarray] = {}
    maps_b2: dict[int, np.ndarray] = {}
    weights: dict[int, np.ndarray] = {}

    for lev in range(levelmin, lmax + 1):
        n = 2**lev
        maps_rho[lev] = np.zeros((n, n), dtype=np.float64)
        maps_b1[lev] = np.zeros((n, n), dtype=np.float64)
        maps_b2[lev] = np.zeros((n, n), dtype=np.float64)
        weights[lev] = np.zeros((n, n), dtype=np.float64)

    lev = level.astype(np.int32, copy=False)
    # Column weight = cell extent along line of sight (physical units).
    w = dx.copy()

    valid = (lev >= levelmin) & (lev <= lmax) & (w > 0.0) & (rho > 0.0)
    if not np.any(valid):
        ln = 2**lmax
        zmap = np.zeros((ln, ln), dtype=np.float64)
        return zmap, zmap.copy(), zmap.copy()

    h1_v = horiz1[valid]
    h2_v = horiz2[valid]
    lev_v = lev[valid]
    rho_v = rho[valid]
    bx_v = bx[valid]
    bz_v = bz_inplane[valid]
    w_v = w[valid]

    for ilev in range(levelmin, lmax + 1):
        m = lev_v == ilev
        if not np.any(m):
            continue
        n = 2**ilev
        ix = np.floor(h1_v[m] / boxlen * n).astype(np.int32)
        iy = np.floor(h2_v[m] / boxlen * n).astype(np.int32)
        ix = np.clip(ix, 0, n - 1)
        iy = np.clip(iy, 0, n - 1)
        ww = w_v[m]
        rr = rho_v[m]
        np.add.at(maps_rho[ilev], (ix, iy), rr * ww)
        np.add.at(maps_b1[ilev], (ix, iy), rr * bx_v[m] * ww)
        np.add.at(maps_b2[ilev], (ix, iy), rr * bz_v[m] * ww)
        np.add.at(weights[ilev], (ix, iy), rr * ww)

    ln = 2**lmax
    out_rho = maps_rho[lmax].copy()
    out_b1 = maps_b1[lmax].copy()
    out_b2 = maps_b2[lmax].copy()
    out_w = weights[lmax].copy()

    for ilevel in range(levelmin, lmax):
        ndom = 2**ilevel
        x_norm = (np.arange(ln) + 0.5) / ln
        ic = np.clip((x_norm * ndom).astype(np.int32), 0, ndom - 1)
        jc = np.clip((x_norm * ndom).astype(np.int32), 0, ndom - 1)
        out_rho += maps_rho[ilevel][ic[:, None], jc[None, :]]
        out_b1 += maps_b1[ilevel][ic[:, None], jc[None, :]]
        out_b2 += maps_b2[ilevel][ic[:, None], jc[None, :]]
        out_w += weights[ilevel][ic[:, None], jc[None, :]]

    with np.errstate(invalid="ignore", divide="ignore"):
        b1 = np.where(out_w > 0.0, out_b1 / out_w, 0.0)
        b2 = np.where(out_w > 0.0, out_b2 / out_w, 0.0)
    return out_rho.astype(np.float64), b1.astype(np.float64), b2.astype(np.float64)


def column_maps(
    nout: int,
    run_dir: Path,
    axis: str = "y",
) -> tuple[np.ndarray, np.ndarray, np.ndarray, float, float, int, float]:
    """Return (Sigma, B_horiz1, B_horiz2, boxlen, time, lmax, aexp)."""
    ram = _import_miniramses()
    c = ram.rd_cell(nout, path=str(run_dir))
    if c.nvar <= IVAR_BZ:
        raise ValueError(f"Snapshot nvar={c.nvar}; expected MHD with B components")

    inf = ram.rd_info(nout, path=str(run_dir))
    boxlen = float(inf.boxlen)
    time = float(inf.time)
    aexp = float(getattr(inf, "aexp", 1.0))
    levelmin = int(inf.levelmin)
    lmax = int(inf.nlevelmax)
    if lmax <= 0:
        lmax = int(np.max(c.level)) + 1

    rho = c.u[IVAR_RHO]
    bx = c.u[IVAR_BX]
    by = c.u[IVAR_BY]
    bz = c.u[IVAR_BZ]

    i1, i2, i_los = _projection_indices(axis)
    b_horiz1 = (bx, by, bz)[i1]
    b_horiz2 = (bx, by, bz)[i2]

    sigma, b1, b2 = _amr2map_column(
        c.x[0],
        c.x[1],
        c.x[2],
        c.dx,
        c.level + 1,
        rho,
        b_horiz1,
        b_horiz2,
        boxlen,
        levelmin,
        lmax,
        axis,
    )
    return sigma, b1, b2, boxlen, time, lmax, aexp


def _draw_b_hatches(
    ax,
    b1: np.ndarray,
    b2: np.ndarray,
    boxlen: float,
    *,
    step: int,
    line_len_frac: float,
    color: str,
    alpha: float,
    min_b_frac: float,
) -> None:
    """Draw short line segments aligned with the in-plane B field."""
    ny, nx = b1.shape
    step = max(1, int(step))
    ys = np.arange(step // 2, ny, step)
    xs = np.arange(step // 2, nx, step)
    yy, xx = np.meshgrid(ys, xs, indexing="ij")

    b1s = b1[yy, xx]
    b2s = b2[yy, xx]
    bmag = np.hypot(b1s, b2s)
    bmax = float(np.nanmax(bmag)) if np.any(np.isfinite(bmag)) else 0.0
    if bmax <= 0.0:
        return
    mask = bmag > min_b_frac * bmax
    if not np.any(mask):
        return

    xx = xx[mask].astype(np.float64)
    yy = yy[mask].astype(np.float64)
    b1s = b1s[mask]
    b2s = b2s[mask]
    bmag = bmag[mask]
    ux = b1s / bmag
    uy = b2s / bmag

    dx_pix = boxlen / nx
    dz_pix = boxlen / ny
    half_len = line_len_frac * min(dx_pix, dz_pix)

    x0 = (xx + 0.5) * dx_pix
    z0 = (yy + 0.5) * dz_pix
    for x_c, z_c, ux_i, uy_i in zip(x0, z0, ux, uy):
        ax.plot(
            [x_c - half_len * ux_i, x_c + half_len * ux_i],
            [z_c - half_len * uy_i, z_c + half_len * uy_i],
            color=color,
            alpha=alpha,
            lw=0.6,
            solid_capstyle="round",
        )


def plot_column(
    sigma: np.ndarray,
    b1: np.ndarray,
    b2: np.ndarray,
    boxlen: float,
    time: float,
    nout: int,
    lmax: int,
    axis: str,
    out: Path,
    *,
    cmap: str,
    vmin: float | None,
    vmax: float | None,
    quiver_step: int,
    b_color: str,
    b_alpha: float,
    b_min_frac: float,
    no_bfield: bool,
) -> None:
    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    log_sigma = np.log10(np.where(sigma > 0.0, sigma, np.nan))
    lo = vmin if vmin is not None else float(np.nanpercentile(log_sigma, 1.0))
    hi = vmax if vmax is not None else float(np.nanpercentile(log_sigma, 99.5))

    xlab, ylab = _axis_labels(axis)
    extent = (0.0, boxlen, 0.0, boxlen)
    display = np.asarray(log_sigma.T)

    fig, ax = plt.subplots(figsize=(8.0, 7.0), constrained_layout=True)
    im = ax.imshow(
        display,
        origin="lower",
        extent=extent,
        aspect="equal",
        cmap=cmap,
        vmin=lo,
        vmax=hi,
        interpolation="nearest",
    )
    if not no_bfield:
        _draw_b_hatches(
            ax,
            b1,
            b2,
            boxlen,
            step=quiver_step,
            line_len_frac=0.45,
            color=b_color,
            alpha=b_alpha,
            min_b_frac=b_min_frac,
        )

    ax.set_xlabel(f"{xlab} [code length]")
    ax.set_ylabel(f"{ylab} [code length]")
    ax.set_title(
        rf"MHD column density ($\log_{{10}}\Sigma$, proj={axis})\n"
        rf"output {nout:05d}, $t={time:.4g}$, lmax={lmax}"
    )
    cb = fig.colorbar(im, ax=ax, shrink=0.85)
    cb.set_label(r"$\log_{10}\,\Sigma$ (code units)")
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=150)
    plt.close(fig)


def discover_output_nums(run_dir: Path) -> list[int]:
    nums: list[int] = []
    for entry in run_dir.iterdir():
        if not entry.is_dir():
            continue
        match = OUTPUT_RE.match(entry.name)
        if match:
            nums.append(int(match.group(1)))
    return sorted(nums)


def pick_output_id(run_dir: Path, output_id: int | None) -> int:
    nums = discover_output_nums(run_dir)
    if not nums:
        raise SystemExit(f"ERROR: no output_NNNNN/ under {run_dir}")
    if output_id is None:
        return nums[-1]
    if output_id not in nums:
        raise SystemExit(
            f"ERROR: output_{output_id:05d} not found; available: "
            + ", ".join(f"{n:05d}" for n in nums)
        )
    return output_id


def main() -> int:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument(
        "--run-dir",
        type=Path,
        required=True,
        help="Run directory containing output_NNNNN/",
    )
    ap.add_argument(
        "--output-id",
        "--output-num",
        type=int,
        default=None,
        dest="output_id",
        help="Snapshot index (default: latest output_*)",
    )
    ap.add_argument(
        "--plane",
        "--dir",
        default="y",
        choices=["x", "y", "z"],
        dest="axis",
        help="Line-of-sight axis for column integration (default: y → x-z plane)",
    )
    ap.add_argument(
        "--out",
        type=Path,
        default=None,
        help="Output PNG (default: <run-dir>/mhd_turb_column_<axis>_<nout>.png)",
    )
    ap.add_argument("--cmap", default="magma")
    ap.add_argument("--vmin", type=float, default=None, help="log10 floor")
    ap.add_argument("--vmax", type=float, default=None, help="log10 ceiling")
    ap.add_argument(
        "--quiver-step",
        type=int,
        default=8,
        help="Subsample stride for B hatch lines on the map grid (default: 8)",
    )
    ap.add_argument("--b-color", default="white", help="B hatch line color")
    ap.add_argument("--b-alpha", type=float, default=0.75)
    ap.add_argument(
        "--b-min-frac",
        type=float,
        default=0.05,
        help="Skip B segments below this fraction of max |B| (default: 0.05)",
    )
    ap.add_argument("--no-bfield", action="store_true", help="Skip B overlay")
    ap.add_argument("--no-display", action="store_true", help="Save PNG only")
    args = ap.parse_args()

    run_dir = args.run_dir.resolve()
    if not run_dir.is_dir():
        print(f"[FAIL] not a directory: {run_dir}")
        return 1

    nout = pick_output_id(run_dir, args.output_id)
    snap = run_dir / f"output_{nout:05d}"
    if not snap.is_dir():
        print(f"[FAIL] missing snapshot dir: {snap}")
        return 1

    sigma, b1, b2, boxlen, time, lmax, _aexp = column_maps(nout, run_dir, args.axis)
    out = args.out or (run_dir / f"mhd_turb_column_{args.axis}_{nout:05d}_t{time:.3f}.png")

    plot_column(
        sigma,
        b1,
        b2,
        boxlen,
        time,
        nout,
        lmax,
        args.axis,
        out,
        cmap=args.cmap,
        vmin=args.vmin,
        vmax=args.vmax,
        quiver_step=args.quiver_step,
        b_color=args.b_color,
        b_alpha=args.b_alpha,
        b_min_frac=args.b_min_frac,
        no_bfield=args.no_bfield,
    )
    print(f"wrote {out} (t={time:.6f}, lmax={lmax}, map {sigma.shape[0]}x{sigma.shape[1]})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
