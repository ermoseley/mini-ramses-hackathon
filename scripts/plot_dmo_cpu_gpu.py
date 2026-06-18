#!/usr/bin/env python3
"""Two-panel log-column-density figure comparing a CPU run and a GPU run.

Driver around the part2map Fortran tool in ~/mini-ramses-dev/utils/f90.
Steps:
  1. Locate the latest (or selected) output_NNNNN/ inside each run directory.
  2. Invoke part2map on each to write a binary .map file.
  3. Read the .map files (same Fortran-record layout as utils/py/map2img.py).
  4. Render side-by-side with matplotlib imshow on a shared log10 colour scale.

Examples
--------
  # Plot the latest output of each run with default 512x512 maps:
  python3 plot_dmo_cpu_gpu.py \\
      --cpu ~/hackathon/dmo_cpu_<jobid>/dmo/ \\
      --gpu ~/hackathon/dmo_gpu_<jobid>/dmo/ \\
      --out dmo_compare.png

  # Pick a specific snapshot and 1024x1024 maps along the y axis:
  python3 plot_dmo_cpu_gpu.py --cpu CPU_DIR --gpu GPU_DIR \\
      --output-num 3 --nx 1024 --ny 1024 --dir y

The part2map binary path defaults to ~/mini-ramses-dev/utils/f90/part2map and
can be overridden with --part2map or the MINIRAM env var.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

import numpy as np
import matplotlib
import matplotlib.pyplot as plt
from scipy.io import FortranFile


def find_outputs(run_dir: Path) -> list[Path]:
    """Return sorted list of output_NNNNN directories inside run_dir."""
    pat = re.compile(r"output_(\d{5})$")
    outs = [p for p in run_dir.iterdir() if p.is_dir() and pat.match(p.name)]
    outs.sort(key=lambda p: int(pat.match(p.name).group(1)))
    return outs


def pick_output(run_dir: Path, output_num: int | None) -> Path:
    outs = find_outputs(run_dir)
    if not outs:
        sys.exit(f"ERROR: no output_NNNNN/ directories under {run_dir}")
    if output_num is None:
        return outs[-1]
    name = f"output_{output_num:05d}"
    for p in outs:
        if p.name == name:
            return p
    sys.exit(f"ERROR: {name} not under {run_dir}; available: "
             + ", ".join(p.name for p in outs))


def run_part2map(part2map: Path, output_dir: Path, out_map: Path,
                 nx: int, ny: int, axis: str, dep: str,
                 xmin: float | None, xmax: float | None,
                 ymin: float | None, ymax: float | None,
                 zmin: float | None, zmax: float | None) -> None:
    cmd = [str(part2map),
           "-inp", str(output_dir),
           "-out", str(out_map),
           "-dir", axis,
           "-dep", dep,
           "-nx", str(nx),
           "-ny", str(ny)]
    for flag, val in (("-xmi", xmin), ("-xma", xmax),
                      ("-ymi", ymin), ("-yma", ymax),
                      ("-zmi", zmin), ("-zma", zmax)):
        if val is not None:
            cmd += [flag, str(val)]
    print(f"== {' '.join(cmd)}")
    subprocess.run(cmd, check=True)


def read_map(path: Path) -> tuple[np.ndarray, dict]:
    """Read a part2map binary; mirrors utils/py/map2img.py."""
    with FortranFile(str(path), "r") as f:
        t, dx, dy, dz = f.read_reals("f8")
        nx, ny = f.read_ints("i")
        dat = f.read_reals("f4")
    img = np.array(dat).reshape(ny, nx).T   # (nx, ny) after transpose
    meta = {"t": float(t), "dx": float(dx), "dy": float(dy), "dz": float(dz),
            "nx": int(nx), "ny": int(ny)}
    return img, meta


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cpu", required=True, type=Path,
                    help="CPU run directory (contains output_NNNNN/)")
    ap.add_argument("--gpu", required=True, type=Path,
                    help="GPU run directory (contains output_NNNNN/)")
    ap.add_argument("--out", default="dmo_cpu_gpu_compare.png", type=Path,
                    help="Output PNG path")
    ap.add_argument("--output-num", type=int, default=None,
                    help="output_NNNNN to plot (default: latest in each)")
    ap.add_argument("--nx", type=int, default=512)
    ap.add_argument("--ny", type=int, default=512)
    ap.add_argument("--dir", default="z", choices=["x", "y", "z"],
                    dest="axis", help="projection axis")
    ap.add_argument("--dep", default="CIC", choices=["CIC", "TSC", "PCS"],
                    help="particle deposition scheme")
    ap.add_argument("--xmin", type=float); ap.add_argument("--xmax", type=float)
    ap.add_argument("--ymin", type=float); ap.add_argument("--ymax", type=float)
    ap.add_argument("--zmin", type=float); ap.add_argument("--zmax", type=float)
    ap.add_argument("--cmap", default="inferno")
    ap.add_argument("--vmin", type=float, default=None,
                    help="log10 floor for the shared colour scale")
    ap.add_argument("--vmax", type=float, default=None,
                    help="log10 ceil for the shared colour scale")
    ap.add_argument("--part2map", type=Path, default=None,
                    help="path to the part2map binary (default: "
                         "$MINIRAM/utils/f90/part2map)")
    ap.add_argument("--no-display", action="store_true",
                    help="don't open a window; just save the PNG")
    args = ap.parse_args()

    if args.no_display:
        matplotlib.use("Agg")

    # Resolve part2map binary
    part2map = args.part2map
    if part2map is None:
        miniram = Path(os.environ.get("MINIRAM",
                                      Path.home() / "mini-ramses-dev"))
        part2map = miniram / "utils" / "f90" / "part2map"
    if not part2map.exists():
        sys.exit(f"ERROR: part2map binary not found at {part2map}\n"
                 f"       Build it: cd {part2map.parent} && "
                 f"gfortran -O2 -o part2map part2map.f90")

    cpu_out = pick_output(args.cpu, args.output_num)
    gpu_out = pick_output(args.gpu, args.output_num)
    print(f"== CPU output: {cpu_out}")
    print(f"== GPU output: {gpu_out}")

    cpu_map = args.cpu / f"{cpu_out.name}_dens_{args.axis}.map"
    gpu_map = args.gpu / f"{gpu_out.name}_dens_{args.axis}.map"
    bbox = (args.xmin, args.xmax, args.ymin, args.ymax, args.zmin, args.zmax)

    run_part2map(part2map, cpu_out, cpu_map,
                 args.nx, args.ny, args.axis, args.dep, *bbox)
    run_part2map(part2map, gpu_out, gpu_map,
                 args.nx, args.ny, args.axis, args.dep, *bbox)

    cpu_img, cpu_meta = read_map(cpu_map)
    gpu_img, gpu_meta = read_map(gpu_map)
    print(f"== CPU map {cpu_img.shape}  t={cpu_meta['t']:.4g}")
    print(f"== GPU map {gpu_img.shape}  t={gpu_meta['t']:.4g}")

    # Log10 column density on a shared scale. Mask zeros so log doesn't barf.
    def log_safe(a: np.ndarray) -> np.ndarray:
        return np.log10(np.where(a > 0, a, np.nan))

    cpu_log = log_safe(cpu_img)
    gpu_log = log_safe(gpu_img)
    vmin = args.vmin if args.vmin is not None \
        else np.nanpercentile(np.concatenate([cpu_log.ravel(), gpu_log.ravel()]), 1)
    vmax = args.vmax if args.vmax is not None \
        else np.nanpercentile(np.concatenate([cpu_log.ravel(), gpu_log.ravel()]), 99.5)

    fig, axes = plt.subplots(1, 2, figsize=(12, 6), constrained_layout=True)
    for ax, img, label, meta in (
            (axes[0], cpu_log, f"CPU ({cpu_out.name})", cpu_meta),
            (axes[1], gpu_log, f"GPU ({gpu_out.name})", gpu_meta)):
        im = ax.imshow(img.T, origin="lower", cmap=args.cmap,
                       vmin=vmin, vmax=vmax, interpolation="nearest")
        ax.set_title(f"{label}\n$t={meta['t']:.4g}$, "
                     f"{meta['nx']}$\\times${meta['ny']}, proj={args.axis}")
        ax.set_xlabel("pixel x"); ax.set_ylabel("pixel y")
    cb = fig.colorbar(im, ax=axes, shrink=0.9, location="right")
    cb.set_label(r"$\log_{10}\,\Sigma_\mathrm{DM}$ (code units)")

    fig.savefig(args.out, dpi=150)
    print(f"== wrote {args.out}")
    if not args.no_display:
        plt.show()
    else:
        plt.close(fig)


if __name__ == "__main__":
    main()
