#!/usr/bin/env python3
"""Plot Ponomarenko total magnetic energy vs time from run.log."""

from __future__ import annotations

import argparse
from pathlib import Path

import matplotlib.pyplot as plt

from plot_emag_vs_time import parse_run_log


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "run_log",
        type=Path,
        nargs="?",
        default=None,
        help="path to run.log (default: positional or required)",
    )
    parser.add_argument("--out", type=Path, default=None)
    parser.add_argument(
        "--linear-y",
        action="store_true",
        help="linear y axis (default: log emag)",
    )
    args = parser.parse_args()
    if args.run_log is None:
        parser.error("run_log path required")

    run_log = args.run_log.resolve()
    t, emag = parse_run_log(run_log)
    out = args.out or Path("plots/pono_emag_vs_time.png")
    out.parent.mkdir(parents=True, exist_ok=True)

    fig, ax = plt.subplots(figsize=(7, 4.5))
    ax.plot(t, emag, lw=1.2, color="#1f77b4")
    ax.set_xlabel("time")
    ax.set_ylabel("total magnetic energy (emag)")
    ax.set_title(f"Ponomarenko emag vs time ({run_log.parent.name})")
    ax.grid(True, alpha=0.3)
    if not args.linear_y:
        ax.set_yscale("log")
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    print(
        f"wrote {out} ({len(t)} points, t=[{t[0]:.3g}, {t[-1]:.3g}], "
        f"emag=[{emag[0]:.3g}, {emag[-1]:.3g}])"
    )


if __name__ == "__main__":
    main()
