#!/usr/bin/env python3
"""Validate linear ambipolar diffusion B_y = B0 sin(kx) on periodic unigrid runs."""

from __future__ import annotations

import argparse
import math
import re
import sys
from pathlib import Path

import numpy as np

MAIN_RE = re.compile(
    r"Main step=\s*\d+.*?emag=\s*([+-]?\d+\.\d+E[+-]\d+|NaN|Inf)",
    re.IGNORECASE,
)
FINE_RE = re.compile(
    r"Fine step=\s*\d+\s+t=\s*([+-]?\d+\.\d+E[+-]\d+)",
    re.IGNORECASE,
)


def import_miniramses(miniram: Path):
    sys.path.insert(0, str(miniram / "utils" / "py"))
    import miniramses as ram  # noqa: WPS433

    return ram


def latest_output(run_dir: Path) -> int:
    outs = sorted(run_dir.glob("output_*"))
    if not outs:
        raise FileNotFoundError(f"no output_* in {run_dir}")
    return int(outs[-1].name.split("_")[-1])


def profile_by(run_dir: Path, ram, nout: int, mid_frac: float = 0.5):
    c = ram.rd_cell(nout, path=str(run_dir))
    ndim = c.ndim
    if ndim == 1:
        mask = np.ones(c.ncell, dtype=bool)
    elif ndim == 2:
        y0 = mid_frac * ram.rd_info(nout, path=str(run_dir)).boxlen
        mask = np.abs(c.x[1] - y0) < 1.5 * np.min(c.dx)
    else:
        y0 = z0 = mid_frac * ram.rd_info(nout, path=str(run_dir)).boxlen
        mask = (np.abs(c.x[1] - y0) < 1.5 * np.min(c.dx)) & (
            np.abs(c.x[2] - z0) < 1.5 * np.min(c.dx)
        )
    x = c.x[0][mask]
    by = c.u[6][mask]
    order = np.argsort(x)
    return x[order], by[order], float(np.min(c.dx))


def analytic_by(x: np.ndarray, t: float, b0: float, k: float, eta: float, bz: float) -> np.ndarray:
    chi = eta * bz * bz
    return b0 * np.sin(k * x) * math.exp(-chi * k * k * t)


def l1_l2(sim: np.ndarray, ref: np.ndarray) -> tuple[float, float]:
    err = sim - ref
    return float(np.mean(np.abs(err))), float(np.sqrt(np.mean(err * err)))


def emag_series(run_log: Path) -> tuple[np.ndarray, np.ndarray]:
    times: list[float] = []
    emags: list[float] = []
    last_t = 0.0
    with run_log.open() as fh:
        for line in fh:
            m = FINE_RE.search(line)
            if m:
                last_t = float(m.group(1))
            m = MAIN_RE.search(line)
            if m and m.group(1).lower() not in ("nan", "inf"):
                times.append(last_t)
                emags.append(float(m.group(1)))
    if not times:
        return np.array([]), np.array([])
    return np.array(times), np.array(emags)


def fit_decay_rate(t: np.ndarray, emag: np.ndarray, b0: float, bz: float) -> float | None:
    if len(t) < 3:
        return None
    e0 = 0.5 * b0 * b0
    ez = 0.5 * bz * bz
    pert = emag - ez
    ok = pert > 0
    if np.count_nonzero(ok) < 3:
        return None
    coef = np.polyfit(t[ok], np.log(pert[ok]), 1)
    return -coef[0]


def convergence_rate(errors: list[float], dxs: list[float]) -> float | None:
    if len(errors) < 2:
        return None
    log_e = np.log(np.array(errors, dtype=float))
    log_dx = np.log(np.array(dxs, dtype=float))
    return float(np.polyfit(log_dx, log_e, 1)[0])


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--workdir", type=Path, required=True)
    p.add_argument("--levels", type=int, nargs="+", default=[6, 7, 8, 9])
    p.add_argument("--a0", type=float, default=0.01)
    p.add_argument("--bz", type=float, default=1.0)
    p.add_argument("--eta-ad", type=float, default=0.01)
    p.add_argument("--boxlen", type=float, default=1.0)
    p.add_argument("--miniram", type=Path, default=Path.home() / "mini-ramses-dev")
    p.add_argument("--out", type=Path, default=None)
    args = p.parse_args()

    ram = import_miniramses(args.miniram)
    k = 2.0 * math.pi / args.boxlen
    chi = args.eta_ad * args.bz * args.bz
    rate_theory = chi * k * k

    lines: list[str] = []
    lines.append(f"ambipolar linear diffusion validation")
    lines.append(f"  B_y = {args.a0} sin(kx), B_z = {args.bz}, eta_ad = {args.eta_ad}")
    lines.append(f"  k = {k:.6g}, expected decay rate chi*k^2 = {rate_theory:.6g}")
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
        ref = analytic_by(x, t, args.a0, k, args.eta_ad, args.bz)
        l1, l2 = l1_l2(by, ref)
        l1s.append(l1)
        l2s.append(l2)
        dxs.append(dx)
        lines.append(f"L{lev}  t={t:.5g}  dx={dx:.3e}  L1={l1:.3e}  L2={l2:.3e}  ncell={len(x)}")

        tlog, emag = emag_series(run / "run.log")
        rate = fit_decay_rate(tlog, emag, args.a0, args.bz)
        if rate is not None:
            lines.append(
                f"       emag decay rate (fitted) = {rate:.6g}  "
                f"(theory chi*k^2 = {rate_theory:.6g}, ratio = {rate / rate_theory:.3f})"
            )
        lines.append("")

    if len(l1s) >= 2:
        p1 = convergence_rate(l1s, dxs)
        p2 = convergence_rate(l2s, dxs)
        lines.append(f"spatial convergence (log error vs log dx):  L1 slope = {p1:.3f},  L2 slope = {p2:.3f}")
        lines.append("  (expect ~2 for second-order spatial discretization)")

    text = "\n".join(lines) + "\n"
    out = args.out or (args.workdir / "ambidiff_report.txt")
    out.write_text(text)
    print(text, end="")


if __name__ == "__main__":
    main()
