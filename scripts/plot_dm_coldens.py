#!/usr/bin/env python3
"""Render a log-scale dark-matter column-density image from a RAMSES snapshot.

Projects particle mass onto a 2-D map, then plots with matplotlib on a log10
scale.  Projection uses either:

  * **python** (default) — reads ``part.*`` via ``ramses_output_io`` and
    deposits with CIC (matches ``utils/f90/part2map.f90`` for the non-periodic
    case);
  * **part2map** — calls the Fortran utility in ``mini-ramses-dev/utils/f90``.

Examples
--------
  # Latest snapshot in a DMO gpu_run directory:
  python3 plot_dm_coldens.py --run dmo_work_<jobid>/2_.../gpu_run \\
      --out dm_coldens.png --no-display

  # Specific snapshot, 1024² map along y:
  python3 plot_dm_coldens.py --run RUN_DIR --output-num 3 \\
      --nx 1024 --ny 1024 --dir y --out snap3_y.png --no-display

  # List which output_NNNNN/ dirs contain particle dumps:
  python3 plot_dm_coldens.py --run RUN_DIR --list-outputs

  # Re-plot an existing part2map binary:
  python3 plot_dm_coldens.py --map output_00003_dens_z.map --out snap3.png
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

import matplotlib
import matplotlib.pyplot as plt
import numpy as np
from scipy.io import FortranFile

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

import ramses_output_io as rio

OUTPUT_RE = re.compile(r"^output_(\d{5})$")


def find_outputs(run_dir: Path) -> list[Path]:
    outs = [p for p in run_dir.iterdir() if p.is_dir() and OUTPUT_RE.match(p.name)]
    outs.sort(key=lambda p: int(OUTPUT_RE.match(p.name).group(1)))
    return outs


def snapshot_has_part(snap_dir: Path, prefix: str = "part") -> bool:
    return (snap_dir / f"{prefix}.00001").is_file() and (
        snap_dir / f"{prefix}_header.txt"
    ).is_file()


def outputs_with_part(run_dir: Path, prefix: str = "part") -> list[Path]:
    return [o for o in find_outputs(run_dir) if snapshot_has_part(o, prefix)]


def output_num_from_dir(snap_dir: Path) -> int:
    match = OUTPUT_RE.match(snap_dir.name)
    if not match:
        raise ValueError(f"not an output_NNNNN directory: {snap_dir}")
    return int(match.group(1))


def pick_output(run_dir: Path, output_num: int | None) -> Path:
    outs = find_outputs(run_dir)
    if not outs:
        sys.exit(f"ERROR: no output_NNNNN/ directories under {run_dir}")
    if output_num is None:
        with_part = outputs_with_part(run_dir)
        if with_part:
            return with_part[-1]
        return outs[-1]
    name = f"output_{output_num:05d}"
    for p in outs:
        if p.name == name:
            return p
    sys.exit(
        f"ERROR: {name} not under {run_dir}; available: "
        + ", ".join(p.name for p in outs)
    )


def require_part_snapshot(snap_dir: Path, run_dir: Path) -> None:
    if snapshot_has_part(snap_dir):
        return
    listing = sorted(p.name for p in snap_dir.iterdir())[:20]
    with_part = outputs_with_part(run_dir)
    msg = [
        f"ERROR: {snap_dir.name} has no particle dump (missing part.00001 / part_header.txt).",
        f"  directory: {snap_dir}",
    ]
    if listing:
        msg.append(f"  contents (first {len(listing)}): {', '.join(listing)}")
    if with_part:
        msg.append(
            "  snapshots with part data: "
            + ", ".join(p.name for p in with_part)
        )
        msg.append(
            f"  try: --output-num {output_num_from_dir(with_part[-1])}"
        )
    else:
        msg.append("  no snapshot under this run contains part.* files.")
    sys.exit("\n".join(msg))


def resolve_part2map(explicit: Path | None) -> Path:
    if explicit is not None:
        return explicit
    miniram = Path(os.environ.get("MINIRAM", Path.home() / "mini-ramses-dev"))
    return miniram / "utils" / "f90" / "part2map"


def projection_axes(axis: str) -> tuple[int, int]:
    if axis == "x":
        return 1, 2
    if axis == "y":
        return 0, 2
    return 0, 1


def axis_labels(axis: str) -> tuple[str, str]:
    if axis == "x":
        return "y", "z"
    if axis == "y":
        return "x", "z"
    return "x", "y"


def resolve_box(
    info: rio.RunInfo,
    *,
    xmin: float | None,
    xmax: float | None,
    ymin: float | None,
    ymax: float | None,
    zmin: float | None,
    zmax: float | None,
) -> tuple[float, float, float, float, float, float]:
    bl = info.boxlen
    return (
        0.0 if xmin is None else xmin,
        bl if xmax is None else xmax,
        0.0 if ymin is None else ymin,
        bl if ymax is None else ymax,
        0.0 if zmin is None else zmin,
        bl if zmax is None else zmax,
    )


def deposit_cic(
    map2d: np.ndarray,
    nx: int,
    ny: int,
    ddx: np.ndarray,
    ddy: np.ndarray,
    mass: np.ndarray,
) -> None:
    """CIC deposit matching part2map.f90 (non-periodic)."""
    ix = np.floor(ddx).astype(np.int64)
    iy = np.floor(ddy).astype(np.int64)
    fx = ddx - ix
    fy = ddy - iy
    mask = (ix >= 0) & (ix < nx) & (iy >= 0) & (iy < ny) & (fx >= 0) & (fy >= 0)
    if not np.any(mask):
        return
    ix = ix[mask]
    iy = iy[mask]
    fx = fx[mask]
    fy = fy[mask]
    m = mass[mask]
    ixp1 = ix + 1
    iyp1 = iy + 1
    np.add.at(map2d, (ix, iy), m * (1.0 - fx) * (1.0 - fy))
    np.add.at(map2d, (ix, iyp1), m * (1.0 - fx) * fy)
    np.add.at(map2d, (ixp1, iy), m * fx * (1.0 - fy))
    np.add.at(map2d, (ixp1, iyp1), m * fx * fy)


def project_snapshot_python(
    run_dir: Path,
    snap_dir: Path,
    *,
    nx: int,
    ny: int,
    axis: str,
    xmin: float | None,
    xmax: float | None,
    ymin: float | None,
    ymax: float | None,
    zmin: float | None,
    zmax: float | None,
    prefix: str = "part",
) -> tuple[np.ndarray, dict]:
    require_part_snapshot(snap_dir, run_dir)
    nout = output_num_from_dir(snap_dir)
    info = rio.parse_info_txt(snap_dir / "info.txt")
    snap = rio.read_part_snapshot(run_dir, nout, prefix=prefix)

    x0, x1, y0, y1, z0, z1 = resolve_box(
        info,
        xmin=xmin,
        xmax=xmax,
        ymin=ymin,
        ymax=ymax,
        zmin=zmin,
        zmax=zmax,
    )
    idim, jdim = projection_axes(axis)
    xxmin, xxmax, yymin, yymax = {
        "x": (y0, y1, z0, z1),
        "y": (x0, x1, z0, z1),
        "z": (x0, x1, y0, y1),
    }[axis]
    zzmin, zzmax = {
        "x": (x0, x1),
        "y": (y0, y1),
        "z": (z0, z1),
    }[axis]

    pos = snap.pos
    lo = np.array([x0, y0, z0])
    hi = np.array([x1, y1, z1])
    in_box = np.all((pos >= lo[:, None]) & (pos <= hi[:, None]), axis=0)
    if not np.any(in_box):
        sys.exit(f"ERROR: no particles in projection box for {snap_dir.name}")

    pos = pos[:, in_box]
    mass = snap.mass[in_box]
    dx = (xxmax - xxmin) / float(nx)
    dy = (yymax - yymin) / float(ny)

    # part2map non-periodic map is (0:nx, 0:ny) -> (nx+1, ny+1) cells.
    map2d = np.zeros((nx + 1, ny + 1), dtype=np.float64)
    ddx = (pos[idim] - xxmin) / dx
    ddy = (pos[jdim] - yymin) / dy
    deposit_cic(map2d, nx, ny, ddx, ddy, mass)

    meta = {
        "t": info.time,
        "dx": x1 - x0,
        "dy": y1 - y0,
        "dz": z1 - z0,
        "nx": nx + 1,
        "ny": ny + 1,
        "xmin": xxmin,
        "xmax": xxmax,
        "ymin": yymin,
        "ymax": yymax,
        "zzmin": zzmin,
        "zzmax": zzmax,
        "npart": int(np.count_nonzero(in_box)),
        "mtot": float(mass.sum()),
    }
    print(
        f"== python CIC: {meta['npart']} particles, "
        f"mtot={meta['mtot']:.6g}, map {meta['nx']}x{meta['ny']}"
    )
    return map2d, meta


def run_part2map(
    part2map: Path,
    output_dir: Path,
    out_map: Path,
    *,
    nx: int,
    ny: int,
    axis: str,
    dep: str,
    xmin: float | None,
    xmax: float | None,
    ymin: float | None,
    ymax: float | None,
    zmin: float | None,
    zmax: float | None,
) -> None:
    cmd = [
        str(part2map),
        "-inp",
        str(output_dir),
        "-out",
        str(out_map),
        "-dir",
        axis,
        "-dep",
        dep,
        "-nx",
        str(nx),
        "-ny",
        str(ny),
    ]
    for flag, val in (
        ("-xmi", xmin),
        ("-xma", xmax),
        ("-ymi", ymin),
        ("-yma", ymax),
        ("-zmi", zmin),
        ("-zma", zmax),
    ):
        if val is not None:
            cmd += [flag, str(val)]
    print(f"== {' '.join(cmd)}")
    result = subprocess.run(cmd, capture_output=True, text=True)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="", file=sys.stderr)
    combined = (result.stdout or "") + (result.stderr or "")
    if result.returncode != 0 or "incomplete" in combined.lower() or not out_map.is_file():
        hint = ""
        if "incomplete" in combined.lower():
            hint = " (part.00001 / part_header.txt missing in snapshot directory?)"
        raise RuntimeError(
            f"part2map failed (exit {result.returncode}){hint}\n"
            f"  expected map: {out_map}"
        )


def read_map(path: Path) -> tuple[np.ndarray, dict]:
    """Read a part2map binary; layout matches utils/py/map2img.py."""
    with FortranFile(str(path), "r") as f:
        t, dx, dy, dz = f.read_reals("f8")
        nx, ny = f.read_ints("i")
        dat = f.read_reals("f4")
        xmin = ymin = 0.0
        xmax = float(dx)
        ymax = float(dy)
        try:
            xmin, xmax = f.read_reals("f8")
            ymin, ymax = f.read_reals("f8")
        except Exception:
            pass
    img = np.array(dat, dtype=np.float64).reshape(ny, nx).T
    meta = {
        "t": float(t),
        "dx": float(dx),
        "dy": float(dy),
        "dz": float(dz),
        "nx": int(nx),
        "ny": int(ny),
        "xmin": float(xmin),
        "xmax": float(xmax),
        "ymin": float(ymin),
        "ymax": float(ymax),
    }
    return img, meta


def log_column_density(img: np.ndarray) -> np.ndarray:
    return np.log10(np.where(img > 0, img, np.nan))


def list_outputs(run_dir: Path) -> None:
    run_dir = run_dir.resolve()
    outs = find_outputs(run_dir)
    if not outs:
        print(f"No output_NNNNN/ under {run_dir}")
        return
    print(f"Snapshots under {run_dir}:")
    for snap in outs:
        tag = "part OK" if snapshot_has_part(snap) else "no part dump"
        print(f"  {snap.name}: {tag}")


def main() -> None:
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    src = ap.add_mutually_exclusive_group(required=True)
    src.add_argument(
        "--run",
        type=Path,
        help="run directory containing output_NNNNN/",
    )
    src.add_argument(
        "--map",
        type=Path,
        help="existing part2map binary (.map); skip projection step",
    )
    ap.add_argument(
        "--out",
        type=Path,
        default="dm_coldens.png",
        help="output PNG path (default: dm_coldens.png)",
    )
    ap.add_argument(
        "--output-num",
        type=int,
        default=None,
        help="output_NNNNN to plot when using --run (default: latest with part data)",
    )
    ap.add_argument(
        "--list-outputs",
        action="store_true",
        help="list output_NNNNN/ dirs and whether each has part.* dumps; then exit",
    )
    ap.add_argument("--nx", type=int, default=512)
    ap.add_argument("--ny", type=int, default=512)
    ap.add_argument(
        "--dir",
        default="z",
        choices=["x", "y", "z"],
        dest="axis",
        help="line-of-sight axis (projection direction)",
    )
    ap.add_argument(
        "--dep",
        default="CIC",
        choices=["CIC", "TSC", "PCS"],
        help="deposition scheme (part2map backend only; python supports CIC)",
    )
    ap.add_argument(
        "--backend",
        default="python",
        choices=["python", "part2map", "auto"],
        help="projection backend (default: python via ramses_output_io)",
    )
    ap.add_argument("--prefix", default="part", help="particle file prefix")
    ap.add_argument("--xmin", type=float)
    ap.add_argument("--xmax", type=float)
    ap.add_argument("--ymin", type=float)
    ap.add_argument("--ymax", type=float)
    ap.add_argument("--zmin", type=float)
    ap.add_argument("--zmax", type=float)
    ap.add_argument("--cmap", default="inferno")
    ap.add_argument(
        "--vmin",
        type=float,
        default=None,
        help="log10 floor for colour scale (default: 1st percentile)",
    )
    ap.add_argument(
        "--vmax",
        type=float,
        default=None,
        help="log10 ceil for colour scale (default: 99.5th percentile)",
    )
    ap.add_argument(
        "--part2map",
        type=Path,
        default=None,
        help="path to part2map binary (default: $MINIRAM/utils/f90/part2map)",
    )
    ap.add_argument(
        "--no-display",
        action="store_true",
        help="save PNG only; do not open a window",
    )
    args = ap.parse_args()

    if args.list_outputs:
        if args.run is None:
            sys.exit("ERROR: --list-outputs requires --run")
        list_outputs(args.run)
        return

    if args.no_display:
        matplotlib.use("Agg")

    axis = args.axis
    if args.map is not None:
        map_path = args.map.resolve()
        if not map_path.is_file():
            sys.exit(f"ERROR: map file not found: {map_path}")
        img, meta = read_map(map_path)
        snap_name = map_path.stem
    else:
        run_dir = args.run.resolve()
        output_dir = pick_output(run_dir, args.output_num)
        snap_name = output_dir.name

        backend = args.backend
        if backend == "auto":
            backend = "part2map" if args.dep != "CIC" else "python"

        if backend == "python":
            if args.dep != "CIC":
                sys.exit("ERROR: python backend supports CIC only; use --backend part2map")
            img, meta = project_snapshot_python(
                run_dir,
                output_dir,
                nx=args.nx,
                ny=args.ny,
                axis=axis,
                xmin=args.xmin,
                xmax=args.xmax,
                ymin=args.ymin,
                ymax=args.ymax,
                zmin=args.zmin,
                zmax=args.zmax,
                prefix=args.prefix,
            )
        else:
            map_path = run_dir / f"{snap_name}_dens_{axis}.map"
            part2map = resolve_part2map(args.part2map)
            if not part2map.is_file():
                sys.exit(
                    f"ERROR: part2map not found at {part2map}\n"
                    f"       Build: cd {part2map.parent} && "
                    f"gfortran -O2 -o part2map part2map.f90\n"
                    f"       Or use --backend python (default)."
                )
            require_part_snapshot(output_dir, run_dir)
            try:
                run_part2map(
                    part2map,
                    output_dir,
                    map_path,
                    nx=args.nx,
                    ny=args.ny,
                    axis=axis,
                    dep=args.dep,
                    xmin=args.xmin,
                    xmax=args.xmax,
                    ymin=args.ymin,
                    ymax=args.ymax,
                    zmin=args.zmin,
                    zmax=args.zmax,
                )
            except RuntimeError as exc:
                if args.backend == "auto":
                    print(f"== part2map failed, falling back to python: {exc}")
                    img, meta = project_snapshot_python(
                        run_dir,
                        output_dir,
                        nx=args.nx,
                        ny=args.ny,
                        axis=axis,
                        xmin=args.xmin,
                        xmax=args.xmax,
                        ymin=args.ymin,
                        ymax=args.ymax,
                        zmin=args.zmin,
                        zmax=args.zmax,
                        prefix=args.prefix,
                    )
                else:
                    sys.exit(str(exc))
            else:
                img, meta = read_map(map_path)

    log_img = log_column_density(img)
    print(
        f"== map: {meta['nx']}x{meta['ny']}, t={meta['t']:.4g}, proj={axis}"
    )

    vmin = args.vmin if args.vmin is not None else np.nanpercentile(log_img, 1)
    vmax = args.vmax if args.vmax is not None else np.nanpercentile(log_img, 99.5)

    xlab, ylab = axis_labels(axis)
    extent = [meta["xmin"], meta["xmax"], meta["ymin"], meta["ymax"]]

    fig, ax = plt.subplots(figsize=(8, 7), constrained_layout=True)
    im = ax.imshow(
        log_img.T,
        origin="lower",
        extent=extent,
        cmap=args.cmap,
        vmin=vmin,
        vmax=vmax,
        interpolation="nearest",
        aspect="equal",
    )
    ax.set_xlabel(f"{xlab} [code length]")
    ax.set_ylabel(f"{ylab} [code length]")
    ax.set_title(
        rf"DM column density ($\log_{{10}}\Sigma$, proj={axis})\n"
        rf"{snap_name}, $t={meta['t']:.4g}$"
    )
    cb = fig.colorbar(im, ax=ax, shrink=0.85)
    cb.set_label(r"$\log_{10}\,\Sigma_\mathrm{DM}$ (code units)")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(args.out, dpi=150)
    print(f"== wrote {args.out}")
    if not args.no_display:
        plt.show()
    else:
        plt.close(fig)


if __name__ == "__main__":
    main()
