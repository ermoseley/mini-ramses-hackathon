#!/usr/bin/env python3
"""Column-integrated magnetic energy density in the x-z plane (Blues map)."""

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


def _amr2map_emag_column(
    x: np.ndarray,
    z: np.ndarray,
    dx: np.ndarray,
    level: np.ndarray,
    emag: np.ndarray,
    boxlen: float,
    levelmin: int,
    lmax: int,
) -> np.ndarray:
    maps: dict[int, np.ndarray] = {}
    for lev in range(levelmin, lmax + 1):
        maps[lev] = np.zeros((2**lev, 2**lev), dtype=np.float64)

    lev = level.astype(np.int32, copy=False)
    w = dx.copy()
    valid = (lev >= levelmin) & (lev <= lmax) & (w > 0.0) & (emag > 0.0)
    if not np.any(valid):
        return np.zeros((2**lmax, 2**lmax), dtype=np.float64)

    x_v = x[valid]
    z_v = z[valid]
    lev_v = lev[valid]
    emag_v = emag[valid]
    w_v = w[valid]

    for ilev in range(levelmin, lmax + 1):
        m = lev_v == ilev
        if not np.any(m):
            continue
        n = 2**ilev
        ix = np.clip(np.floor(x_v[m] / boxlen * n).astype(np.int32), 0, n - 1)
        iy = np.clip(np.floor(z_v[m] / boxlen * n).astype(np.int32), 0, n - 1)
        np.add.at(maps[ilev], (ix, iy), emag_v[m] * w_v[m])

    ln = 2**lmax
    out = maps[lmax].copy()
    for ilevel in range(levelmin, lmax):
        ndom = 2**ilevel
        x_norm = (np.arange(ln) + 0.5) / ln
        ic = np.clip((x_norm * ndom).astype(np.int32), 0, ndom - 1)
        jc = np.clip((x_norm * ndom).astype(np.int32), 0, ndom - 1)
        out += maps[ilevel][ic[:, None], jc[None, :]]
    return out


def emag_column_map(nout: int, run_dir: Path) -> tuple[np.ndarray, float, float, int]:
    ram = _import_miniramses()
    c = ram.rd_cell(nout, path=str(run_dir))
    if c.nvar <= IVAR_BZ:
        raise ValueError(f"Snapshot nvar={c.nvar}; expected MHD with B components")
    inf = ram.rd_info(nout, path=str(run_dir))
    bx, by, bz = c.u[IVAR_BX], c.u[IVAR_BY], c.u[IVAR_BZ]
    emag = 0.5 * (bx * bx + by * by + bz * bz)

    boxlen = float(inf.boxlen)
    time = float(inf.time)
    levelmin = int(inf.levelmin)
    lmax = int(inf.nlevelmax)
    if lmax <= 0:
        lmax = int(np.max(c.level)) + 1

    col = _amr2map_emag_column(
        c.x[0], c.x[2], c.dx, c.level + 1, emag, boxlen, levelmin, lmax
    )
    return col, boxlen, time, lmax


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--run-dir", type=Path, required=True)
    ap.add_argument("--output-id", type=int, default=None)
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--cmap", default="Blues")
    ap.add_argument("--log10", action="store_true", default=True)
    ap.add_argument("--no-log10", action="store_false", dest="log10")
    args = ap.parse_args()

    run_dir = args.run_dir.resolve()
    nout = pick_output_id(run_dir, args.output_id)
    col, boxlen, time, lmax = emag_column_map(nout, run_dir)

    out = args.out or (run_dir / f"abc_bmag_xz_{nout:05d}.png")
    display = np.log10(np.where(col > 0.0, col, np.nan)) if args.log10 else col
    pos = display[np.isfinite(display)]
    vmin = float(np.min(pos)) if pos.size else 0.0
    vmax = float(np.max(pos)) if pos.size else 1.0

    import matplotlib

    matplotlib.use("Agg")
    import matplotlib.pyplot as plt

    fig, ax = plt.subplots(figsize=(7.0, 6.0), constrained_layout=True)
    im = ax.imshow(
        display.T,
        origin="lower",
        extent=(0.0, boxlen, 0.0, boxlen),
        aspect="equal",
        cmap=args.cmap,
        vmin=vmin,
        vmax=vmax,
        interpolation="nearest",
    )
    ax.set_xlabel("x [code length]")
    ax.set_ylabel("z [code length]")
    ax.set_title(f"ABC column magnetic energy (output {nout:05d}, t={time:.4f})")
    cb = fig.colorbar(im, ax=ax, shrink=0.85)
    cb.set_label(r"$\log_{10}\,\int (B^2/2)\,dy$" if args.log10 else r"$\int (B^2/2)\,dy$")
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=150)
    plt.close(fig)
    print(f"wrote {out} (t={time:.6f}, lmax={lmax}, map {col.shape[0]}x{col.shape[1]})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
