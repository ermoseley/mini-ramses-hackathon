#!/usr/bin/env python3
"""Plot total magnetic energy (emag) vs time from a RAMSES run.log."""

from __future__ import annotations

import argparse
import re
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np

MAIN_RE = re.compile(
    r"Main step=\s*(\d+).*?emag=\s*([+-]?\d+\.\d+E[+-]\d+|NaN)",
    re.IGNORECASE,
)
FINE_RE = re.compile(
    r"Fine step=\s*(\d+)\s+t=\s*([+-]?\d+\.\d+E[+-]\d+)",
    re.IGNORECASE,
)


def parse_run_log(path: Path) -> tuple[np.ndarray, np.ndarray]:
    times: dict[int, float] = {}
    emags: dict[int, float] = {}

    with path.open() as fh:
        for line in fh:
            main = MAIN_RE.search(line)
            if main:
                step = int(main.group(1))
                val = main.group(2)
                if val.lower() != "nan":
                    emags[step] = float(val)
                continue
            fine = FINE_RE.search(line)
            if fine:
                step = int(fine.group(1))
                times[step] = float(fine.group(2))

    steps = sorted(set(times) & set(emags))
    if not steps:
        raise SystemExit(f"no Main/Fine step pairs with finite emag found in {path}")

    t = np.array([times[s] for s in steps], dtype=float)
    emag = np.array([emags[s] for s in steps], dtype=float)
    return t, emag


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_log", type=Path, help="path to run.log")
    parser.add_argument(
        "--out",
        type=Path,
        default=None,
        help="output PNG (default: <run_log_dir>/emag_vs_time.png)",
    )
    parser.add_argument("--logy", action="store_true", help="log-scale y axis")
    parser.add_argument("--title", default="", help="plot title")
    args = parser.parse_args()

    run_log = args.run_log.resolve()
    t, emag = parse_run_log(run_log)

    out = args.out or (run_log.parent / "emag_vs_time.png")
    title = args.title or f"emag vs time ({run_log.parent.name})"

    fig, ax = plt.subplots(figsize=(7, 4.5))
    ax.plot(t, emag, lw=1.2, color="#1f77b4")
    ax.set_xlabel("time")
    ax.set_ylabel("total magnetic energy (emag)")
    ax.set_title(title)
    ax.grid(True, alpha=0.3)
    if args.logy:
        ax.set_yscale("log")
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    print(
        f"wrote {out} ({len(t)} points, t=[{t[0]:.3g}, {t[-1]:.3g}], "
        f"emag=[{emag[0]:.3g}, {emag[-1]:.3g}])"
    )


if __name__ == "__main__":
    main()
