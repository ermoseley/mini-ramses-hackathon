#!/usr/bin/env python3
"""Rudimentary CPU vs GPU DMO validation plots from RAMSES output snapshots.

Writes PNGs under ``--outdir`` (default: ``<cpu_run>/../compare_plots``):
  - ``vel_hist_last.png`` — |v| histogram overlay (CPU vs GPU, last common snap)
  - ``vel_scatter_last.png`` — per-particle |dv| vs sorted index (subsampled)
  - ``speed_vs_aexp.png`` — mean |v| vs aexp for all common snapshots

Uses ``ramses_output_io`` (numpy only). Does not call pm_dump harness scripts.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import numpy as np

_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

import ramses_output_io as rio


def speed(part: rio.PartSnapshot) -> np.ndarray:
    return np.sqrt(np.sum(part.vel * part.vel, axis=0))


def aligned_speeds(cpu: rio.PartSnapshot, gpu: rio.PartSnapshot):
    oc = np.argsort(cpu.birth_id, kind="stable")
    og = np.argsort(gpu.birth_id, kind="stable")
    if not np.array_equal(cpu.birth_id[oc], gpu.birth_id[og]):
        raise ValueError("birth_id mismatch — run compare_dmo_outputs.py first")
    return speed(cpu)[oc], speed(gpu)[og]


def subsample(n: int, max_points: int) -> np.ndarray:
    if n <= max_points:
        return np.arange(n)
    return np.linspace(0, n - 1, max_points, dtype=int)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cpu", required=True, type=Path)
    ap.add_argument("--gpu", required=True, type=Path)
    ap.add_argument("--outdir", type=Path, default=None)
    ap.add_argument("--max-scatter", type=int, default=50000)
    ap.add_argument("--last-only", action="store_true", help="skip speed_vs_aexp panel")
    args = ap.parse_args()

    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError as exc:
        print(f"[WARN] matplotlib unavailable ({exc}); skipping plots")
        return 0

    cpu_dir = args.cpu.resolve()
    gpu_dir = args.gpu.resolve()
    common = sorted(set(rio.discover_output_nums(cpu_dir)) & set(rio.discover_output_nums(gpu_dir)))
    if not common:
        print("[FAIL] no common output snapshots to plot")
        return 1

    outdir = args.outdir or (cpu_dir.parent / "compare_plots")
    outdir.mkdir(parents=True, exist_ok=True)

    last = common[-1]
    cpu_last = rio.read_part_snapshot(cpu_dir, last)
    gpu_last = rio.read_part_snapshot(gpu_dir, last)
    v_cpu, v_gpu = aligned_speeds(cpu_last, gpu_last)
    dv = np.abs(v_cpu - v_gpu)

    # |v| histogram
    fig, ax = plt.subplots(figsize=(7, 4))
    bins = np.linspace(0, max(v_cpu.max(), v_gpu.max()) * 1.01, 60)
    ax.hist(v_cpu, bins=bins, histtype="step", label=f"CPU output_{last:05d}", density=True)
    ax.hist(v_gpu, bins=bins, histtype="step", label=f"GPU output_{last:05d}", density=True)
    ax.set_xlabel(r"$|v|$")
    ax.set_ylabel("pdf")
    ax.legend()
    ax.set_title("Speed histogram (last snapshot)")
    fig.tight_layout()
    hist_path = outdir / "vel_hist_last.png"
    fig.savefig(hist_path, dpi=120)
    plt.close(fig)
    print(f"wrote {hist_path}")

    # |dv| scatter (subsampled)
    idx = subsample(len(dv), args.max_scatter)
    fig, ax = plt.subplots(figsize=(7, 4))
    ax.semilogy(idx, np.maximum(dv[idx], 1e-30), ",", alpha=0.5)
    ax.set_xlabel("particle index (sorted by birth_id)")
    ax.set_ylabel(r"$|v_\mathrm{cpu} - v_\mathrm{gpu}|$")
    ax.set_title(f"Per-particle speed mismatch (output_{last:05d})")
    fig.tight_layout()
    sc_path = outdir / "vel_scatter_last.png"
    fig.savefig(sc_path, dpi=120)
    plt.close(fig)
    print(f"wrote {sc_path}")

    if not args.last_only:
        mean_cpu = []
        mean_gpu = []
        aexp = []
        for nout in common:
            c = rio.read_part_snapshot(cpu_dir, nout)
            g = rio.read_part_snapshot(gpu_dir, nout)
            vc, vg = aligned_speeds(c, g)
            info = rio.parse_info_txt(cpu_dir / f"output_{nout:05d}" / "info.txt")
            mean_cpu.append(float(np.mean(vc)))
            mean_gpu.append(float(np.mean(vg)))
            aexp.append(info.aexp)
        fig, ax = plt.subplots(figsize=(7, 4))
        ax.plot(aexp, mean_cpu, "o-", label="CPU mean |v|")
        ax.plot(aexp, mean_gpu, "s-", label="GPU mean |v|")
        ax.set_xlabel("aexp")
        ax.set_ylabel("mean |v|")
        ax.legend()
        ax.set_title("Mean speed vs expansion factor")
        fig.tight_layout()
        ts_path = outdir / "speed_vs_aexp.png"
        fig.savefig(ts_path, dpi=120)
        plt.close(fig)
        print(f"wrote {ts_path}")

    print(f"plot summary: last=nout {last}, npart={cpu_last.npart}, max|dv|={dv.max():.3e}, mean|dv|={dv.mean():.3e}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
