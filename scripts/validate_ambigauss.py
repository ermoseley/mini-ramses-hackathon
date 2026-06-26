#!/usr/bin/env python3
"""Validate Gaussian ambipolar diffusion B_y on periodic unigrid runs."""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import numpy as np

from validate_ambidiff import (
    convergence_rate,
    import_miniramses,
    l1_l2,
    latest_output,
    profile_by,
)


def analytic_by(
    x: np.ndarray,
    t: float,
    b0: float,
    sigma: float,
    x0: float,
    eta: float,
    bz: float,
) -> np.ndarray:
    chi = eta * bz * bz
    sig2 = sigma * sigma + 2.0 * chi * t
    amp = b0 / math.sqrt(1.0 + 2.0 * chi * t / (sigma * sigma))
    return amp * np.exp(-0.5 * (x - x0) ** 2 / sig2)


def variance_theory(sigma: float, t: float, eta: float, bz: float) -> float:
    chi = eta * bz * bz
    return sigma * sigma + 2.0 * chi * t


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--workdir", type=Path, required=True)
    p.add_argument("--levels", type=int, nargs="+", default=[6, 7, 8, 9])
    p.add_argument("--a0", type=float, default=0.01)
    p.add_argument("--sigma", type=float, default=0.1)
    p.add_argument("--bz", type=float, default=1.0)
    p.add_argument("--eta-ad", type=float, default=0.01)
    p.add_argument("--boxlen", type=float, default=1.0)
    p.add_argument("--miniram", type=Path, default=Path.home() / "mini-ramses-dev")
    p.add_argument("--out", type=Path, default=None)
    args = p.parse_args()

    ram = import_miniramses(args.miniram)
    chi = args.eta_ad * args.bz * args.bz
    x0 = 0.5 * args.boxlen

    lines: list[str] = []
    lines.append("Gaussian ambipolar diffusion validation")
    lines.append(
        f"  B_y = {args.a0} exp(-(x-{x0})^2/(2*{args.sigma}^2)), "
        f"B_z = {args.bz}, eta_ad = {args.eta_ad}"
    )
    lines.append(f"  chi = eta_ad*B_z^2 = {chi:.6g}")
    lines.append("")

    l1s: list[float] = []
    l2s: list[float] = []
    dxs: list[float] = []

    for lev in args.levels:
        run = args.workdir / f"L{lev}"
        if not run.is_dir():
            lines.append(f"L{lev}: MISSING {run}")
            continue
        nout = latest_output(run)
        info = ram.rd_info(nout, path=str(run))
        t = float(info.texp)
        x, by, dx = profile_by(run, ram, nout)
        ref = analytic_by(x, t, args.a0, args.sigma, x0, args.eta_ad, args.bz)
        l1, l2 = l1_l2(by, ref)
        l1s.append(l1)
        l2s.append(l2)
        dxs.append(dx)

        w = np.sum(by * by)
        w0 = args.a0 * args.a0 * args.sigma * math.sqrt(math.pi / 2.0)
        sig_meas = math.sqrt(max(w / max(w0, 1.0e-30) * args.sigma * args.sigma, 0.0))
        sig_th = math.sqrt(variance_theory(args.sigma, t, args.eta_ad, args.bz))
        lines.append(
            f"L{lev}  t={t:.5g}  dx={dx:.3e}  L1={l1:.3e}  L2={l2:.3e}  "
            f"sigma_meas={sig_meas:.4f}  sigma_theory={sig_th:.4f}  ncell={len(x)}"
        )
        lines.append("")

    if len(l1s) >= 2:
        p1 = convergence_rate(l1s, dxs)
        p2 = convergence_rate(l2s, dxs)
        lines.append(
            f"spatial convergence (log error vs log dx):  L1 slope = {p1:.3f},  L2 slope = {p2:.3f}"
        )
        lines.append("  (expect ~2 for second-order spatial discretization)")

    text = "\n".join(lines) + "\n"
    out = args.out or (args.workdir / "ambigauss_report.txt")
    out.write_text(text)
    print(text, end="")


if __name__ == "__main__":
    main()
