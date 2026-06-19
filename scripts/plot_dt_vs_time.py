#!/usr/bin/env python3
"""Plot RAMSES timestep size (dt) vs simulation time (t) from run logs.

Parses per-timestep lines written by ``update_time.f90`` (format 888):

    Fine step= <nstep> t= <t> dt= <dt> a= <aexp> mem= ...

Examples
--------
  python3 scripts/plot_dt_vs_time.py --log run.log --out dt_vs_time.png
  python3 scripts/plot_dt_vs_time.py --run-dir /scratch/.../mhd_turb_full_l9_m10
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

# update_time.f90:888 — one line per fine timestep when ncontrol triggers.
FINE_STEP_RE = re.compile(
    r"Fine step=\s*(\d+)\s+t=\s*([\d.E+-]+)\s+dt=\s*([\d.E+-]+)",
    re.IGNORECASE,
)


def resolve_log_path(log: Path | None, run_dir: Path | None) -> Path:
    if log is not None:
        if not log.is_file():
            raise FileNotFoundError(f"log not found: {log}")
        return log
    if run_dir is None:
        raise ValueError("provide --log or --run-dir")
    for name in ("run.log", "stdout.log"):
        candidate = run_dir / name
        if candidate.is_file():
            return candidate
    raise FileNotFoundError(f"no run.log or stdout.log under {run_dir}")


def parse_fine_steps(log_path: Path) -> tuple[list[int], list[float], list[float]]:
    steps: list[int] = []
    times: list[float] = []
    dts: list[float] = []
    with log_path.open("r", errors="replace") as fh:
        for line in fh:
            m = FINE_STEP_RE.search(line)
            if not m:
                continue
            steps.append(int(m.group(1)))
            times.append(float(m.group(2)))
            dts.append(float(m.group(3)))
    return steps, times, dts


def plot_dt_vs_time(
    times: list[float],
    dts: list[float],
    out_path: Path,
    *,
    title: str | None = None,
    log_y: bool = True,
) -> None:
    try:
        import matplotlib

        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError as exc:
        raise SystemExit(f"matplotlib required: {exc}") from exc

    if not times:
        raise ValueError("no Fine step= lines parsed from log")

    fig, ax = plt.subplots(figsize=(8, 4.5), layout="constrained")
    ax.plot(times, dts, linewidth=0.8, color="C0")
    ax.set_xlabel("t")
    ax.set_ylabel("dt")
    ax.set_xscale("linear")
    if log_y:
        ax.set_yscale("log")
    if title:
        ax.set_title(title)
    ax.grid(True, alpha=0.3, linewidth=0.5)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out_path, dpi=150)
    plt.close(fig)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--log", type=Path, default=None, help="path to run.log or slurm stdout")
    ap.add_argument("--run-dir", type=Path, default=None, help="run directory containing run.log")
    ap.add_argument("--out", type=Path, required=True, help="output PNG path")
    ap.add_argument("--title", type=str, default=None, help="optional plot title")
    ap.add_argument(
        "--linear-y",
        action="store_true",
        help="force linear dt axis (default: log dt, linear t)",
    )
    args = ap.parse_args()

    log_path = resolve_log_path(args.log, args.run_dir)
    steps, times, dts = parse_fine_steps(log_path)
    if not times:
        print(f"[ERROR] no Fine step= lines in {log_path}", file=sys.stderr)
        return 1

    plot_dt_vs_time(
        times,
        dts,
        args.out,
        title=args.title,
        log_y=not args.linear_y,
    )

    t_min, t_max = min(times), max(times)
    dt_min, dt_max = min(dts), max(dts)
    print(f"log: {log_path}")
    print(f"timesteps parsed: {len(times)} (nstep {steps[0]}..{steps[-1]})")
    print(f"t range: [{t_min:.6g}, {t_max:.6g}]")
    print(f"dt range: [{dt_min:.6g}, {dt_max:.6g}]")
    print(f"wrote: {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
