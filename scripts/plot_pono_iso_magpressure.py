#!/usr/bin/env python3
"""Single isosurface of magnetic pressure B^2/2 for Ponomarenko MHD snapshot."""

from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

import numpy as np

OUTPUT_RE = re.compile(r"^output_(\d+)$")
IVAR_BX, IVAR_BY, IVAR_BZ = 5, 6, 7


def _import_miniramses():
    _here = Path(__file__).resolve().parent
    mini_root = Path(os.environ.get("MINIRAM", os.environ.get("MINI_RAMSES", _here.parent / "mini-ramses-dev")))
    utils_py = mini_root / "utils" / "py"
    sys.path.insert(0, str(utils_py if (utils_py / "miniramses.py").is_file() else mini_root))
    import miniramses as ram

    return ram


def discover_output_nums(run_dir: Path) -> list[int]:
    nums: list[int] = []
    for entry in run_dir.iterdir():
        if entry.is_dir() and (m := OUTPUT_RE.match(entry.name)):
            nums.append(int(m.group(1)))
    return sorted(nums)


def pick_output_id(run_dir: Path, output_id: int | None) -> int:
    nums = discover_output_nums(run_dir)
    if not nums:
        raise SystemExit(f"no output_NNNNN/ under {run_dir}")
    if output_id is None:
        return nums[-1]
    if output_id not in nums:
        raise SystemExit(f"output_{output_id:05d} not found; have {', '.join(f'{n:05d}' for n in nums)}")
    return output_id


def _resample_cube(cube: np.ndarray, n: int) -> np.ndarray:
    if cube.shape[0] == n:
        return cube
    from scipy.ndimage import zoom

    out = zoom(cube, n / cube.shape[0], order=1)
    if out.shape[0] == n:
        return out
    idx = np.linspace(0, out.shape[0] - 1, n).astype(int)
    return out[np.ix_(idx, idx, idx)]


def _auto_isolevel(cube: np.ndarray, percentile: float, center_frac: float) -> float:
    n = cube.shape[0]
    lo = int(n * (0.5 - 0.5 * center_frac))
    hi = int(n * (0.5 + 0.5 * center_frac))
    core = cube[lo:hi, lo:hi, lo:hi]
    pos = core[core > 0.0]
    if pos.size == 0:
        pos = cube[cube > 0.0]
    if pos.size == 0:
        raise SystemExit("magnetic pressure field is empty")
    return float(np.percentile(pos, percentile))


def _smooth_cube(cube: np.ndarray, sigma: float) -> np.ndarray:
    if sigma <= 0.0:
        return cube
    from scipy.ndimage import gaussian_filter

    return gaussian_filter(cube, sigma=sigma, mode="nearest")


def _mesh_facecolors(verts: np.ndarray, faces: np.ndarray, boxlen: float, cmap) -> np.ndarray:
    tri = verts[faces]
    normals = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
    normals /= np.maximum(np.linalg.norm(normals, axis=1)[:, None], 1.0e-30)
    cent = tri.mean(axis=1)
    depth = (0.58 * cent[:, 2] + 0.28 * cent[:, 0] - 0.14 * cent[:, 1]) / boxlen
    depth = np.clip(depth, 0.0, 1.0)

    from matplotlib.colors import LightSource

    shade = LightSource(azdeg=320, altdeg=38).shade_normals(normals, fraction=0.8)
    shade = 0.42 + 0.58 * np.clip(shade, 0.0, 1.0)
    colors = cmap(0.16 + 0.72 * depth)
    colors[:, :3] *= shade[:, None]
    colors[:, 3] = 0.97
    return colors


def _clean_axes(ax, boxlen: float) -> None:
    ticks = np.array([0.0, 0.5 * boxlen, boxlen])
    ticklabels = [f"{t:.1f}" for t in ticks]
    ax.set_xticks(ticks)
    ax.set_yticks(ticks)
    ax.set_zticks(ticks)
    ax.set_xticklabels(ticklabels)
    ax.set_yticklabels(ticklabels)
    ax.set_zticklabels(ticklabels)
    ax.tick_params(labelsize=7, colors="0.25", pad=0)
    for axis in (ax.xaxis, ax.yaxis, ax.zaxis):
        axis.pane.set_facecolor((1.0, 1.0, 1.0, 0.0))
        axis.pane.set_edgecolor((1.0, 1.0, 1.0, 0.0))
        axis.line.set_color("0.25")
    ax.grid(False)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run-dir", type=Path, required=True)
    ap.add_argument("--output-id", type=int, default=None)
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--isolevel", type=float, default=None)
    ap.add_argument("--percentile", type=float, default=92.0)
    ap.add_argument("--grid", type=int, default=128)
    ap.add_argument("--center-frac", type=float, default=0.5)
    ap.add_argument("--smooth-sigma", type=float, default=1.0)
    args = ap.parse_args()

    run_dir = args.run_dir.resolve()
    nout = pick_output_id(run_dir, args.output_id)
    ram = _import_miniramses()
    c = ram.rd_cell(nout, path=str(run_dir))
    if c.nvar <= IVAR_BZ:
        raise SystemExit(f"Snapshot nvar={c.nvar}; expected MHD with B components")
    inf = ram.rd_info(nout, path=str(run_dir))
    bx, by, bz = c.u[IVAR_BX], c.u[IVAR_BY], c.u[IVAR_BZ]
    pmag = 0.5 * (bx * bx + by * by + bz * bz)

    boxlen = float(inf.boxlen)
    time = float(inf.time)
    xmin = float(np.min(c.x[0] - c.dx / 2))
    ymin = float(np.min(c.x[1] - c.dx / 2))
    zmin = float(np.min(c.x[2] - c.dx / 2))

    cube = ram.mk_cube(c.x[0], c.x[1], c.x[2], c.dx, pmag)
    cube = _resample_cube(cube, args.grid)
    cube = _smooth_cube(cube, args.smooth_sigma)

    isolevel = args.isolevel
    if isolevel is None:
        isolevel = _auto_isolevel(cube, args.percentile, args.center_frac)

    from skimage.measure import marching_cubes

    ng = cube.shape[0]
    spacing = boxlen / ng
    verts, faces, _, _ = marching_cubes(cube, level=isolevel, spacing=(spacing, spacing, spacing))
    verts[:, 0] += xmin
    verts[:, 1] += ymin
    verts[:, 2] += zmin

    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt
    from mpl_toolkits.mplot3d.art3d import Poly3DCollection

    fig = plt.figure(figsize=(7.2, 6.2), facecolor="white")
    ax = fig.add_subplot(111, projection="3d")
    mesh = Poly3DCollection(
        verts[faces],
        facecolors=_mesh_facecolors(verts, faces, boxlen, plt.get_cmap("magma")),
        edgecolors="none",
        linewidths=0.0,
        antialiased=True,
    )
    ax.add_collection3d(mesh)
    ax.set_xlabel(r"$x$ [code units]", labelpad=3, fontsize=9)
    ax.set_ylabel(r"$y$ [code units]", labelpad=3, fontsize=9)
    ax.set_zlabel(r"$z$ [code units]", labelpad=3, fontsize=9)
    ax.set_xlim(0.0, boxlen)
    ax.set_ylim(0.0, boxlen)
    ax.set_zlim(0.0, boxlen)
    ax.set_title(f"Ponomarenko magnetic pressure, $B^2/2$ (t={time:.3f})", pad=10, fontsize=13)
    ax.view_init(elev=19, azim=-38)
    ax.set_box_aspect((1.0, 1.0, 1.0), zoom=1.22)
    ax.set_proj_type("persp", focal_length=0.9)
    _clean_axes(ax, boxlen)

    out = args.out or (run_dir / f"pono_iso_magpressure_{nout:05d}.png")
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=300, bbox_inches="tight", pad_inches=0.04)
    plt.close(fig)
    print(
        f"wrote {out} (t={time:.6f}, isolevel={isolevel:.6g}, "
        f"grid={ng}^3, smooth_sigma={args.smooth_sigma:g}, "
        f"verts={len(verts)}, faces={len(faces)})"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
