#!/usr/bin/env python3
"""Validate Alfvén wave ambipolar damping on periodic unigrid runs."""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import numpy as np


def import_miniramses(miniram: Path):
    sys.path.insert(0, str(miniram / "utils" / "py"))
    import miniramses as ram  # noqa: WPS433

    return ram


def latest_output(run_dir: Path) -> int:
    outs = sorted(run_dir.glob("output_*"))
    if not outs:
        raise FileNotFoundError(f"no output_* in {run_dir}")
    return int(outs[-1].name.split("_")[-1])


def output_numbers(run_dir: Path) -> list[int]:
    return sorted(int(p.name.split("_")[-1]) for p in run_dir.glob("output_*"))


def theory_gamma(eta_ad: float, b_guide: float, boxlen: float, rho: float = 1.0) -> tuple[float, float, float]:
    k = 2.0 * math.pi / boxlen
    chi = eta_ad * b_guide * b_guide
    gamma = chi * k * k / (2.0 * rho)
    return k, chi, gamma


def profile_bperp(run_dir: Path, ram, nout: int, mid_frac: float = 0.5):
    c = ram.rd_cell(nout, path=str(run_dir))
    ndim = c.ndim
    if ndim == 1:
        mask = np.ones(c.ncell, dtype=bool)
    elif ndim == 2:
        y0 = mid_frac * ram.rd_info(nout, path=str(run_dir)).boxlen
        mask = np.abs(c.x[1] - y0) < 1.5 * np.min(c.dx)
    else:
        x0 = y0 = mid_frac * ram.rd_info(nout, path=str(run_dir)).boxlen
        mask = (np.abs(c.x[0] - x0) < 1.5 * np.min(c.dx)) & (
            np.abs(c.x[1] - y0) < 1.5 * np.min(c.dx)
        )
    z = c.x[2][mask] if ndim >= 3 else c.x[0][mask]
    bx = c.u[4][mask] if ndim >= 3 else c.u[4][mask]
    by = c.u[5][mask] if ndim >= 3 else c.u[5][mask]
    order = np.argsort(z)
    return z[order], bx[order], by[order], float(np.min(c.dx))


def analytic_bperp(a0: float, gamma: float, t: float) -> float:
    return a0 * math.exp(-gamma * t)


def l1_l2(sim: np.ndarray, ref: np.ndarray) -> tuple[float, float]:
    err = sim - ref
    return float(np.mean(np.abs(err))), float(np.sqrt(np.mean(err * err)))


def sin_coeff(x: np.ndarray, f: np.ndarray, k: float) -> float:
    s = np.sin(k * x)
    denom = float(np.sum(s * s))
    if denom <= 0:
        return 0.0
    return float(np.sum(f * s) / denom)


def cos_coeff(x: np.ndarray, f: np.ndarray, k: float) -> float:
    c = np.cos(k * x)
    denom = float(np.sum(c * c))
    if denom <= 0:
        return 0.0
    return float(np.sum(f * c) / denom)


def fit_bperp_amplitude(x: np.ndarray, bx: np.ndarray, by: np.ndarray, k: float) -> float:
    return math.hypot(cos_coeff(x, bx, k), sin_coeff(x, by, k))


def amplitude_series(
    run_dir: Path, ram, k: float, mid_frac: float = 0.5
) -> tuple[np.ndarray, np.ndarray, np.ndarray, np.ndarray]:
    times: list[float] = []
    bx_modes: list[float] = []
    by_modes: list[float] = []
    amps: list[float] = []
    for nout in output_numbers(run_dir):
        info = ram.rd_info(nout, path=str(run_dir))
        x, bx, by, _ = profile_bperp(run_dir, ram, nout, mid_frac)
        times.append(float(info.texp))
        bx_modes.append(cos_coeff(x, bx, k))
        by_modes.append(sin_coeff(x, by, k))
        amps.append(math.hypot(bx_modes[-1], by_modes[-1]))
    if not times:
        return np.array([]), np.array([]), np.array([]), np.array([])
    return np.array(times), np.array(bx_modes), np.array(by_modes), np.array(amps)


def plot_damping(
    t: np.ndarray,
    amp: np.ndarray,
    a0: float,
    gamma: float,
    omega: float,
    out: Path,
    label: str = "",
) -> None:
    import matplotlib.pyplot as plt

    out.parent.mkdir(parents=True, exist_ok=True)
    t_theory = np.linspace(0.0, float(t[-1]) if len(t) else 0.05, 800)
    fig, ax = plt.subplots(figsize=(7, 4.5))
    ax.plot(t, amp, "o-", lw=1.2, ms=4, color="#1f77b4", label=r"simulation $|B_\perp|$ amplitude")
    ax.plot(
        t_theory,
        a0 * np.exp(-gamma * t_theory),
        "--",
        lw=1.2,
        color="#d62728",
        label=f"theory A0 exp(-gamma t), gamma={gamma:.4g}",
    )
    ax.set_xlabel("time")
    ax.set_ylabel(r"$|B_\perp|$ Fourier amplitude")
    title = "Circularly polarized traveling Alfvén wave: ambipolar damping"
    if label:
        title = f"{title} ({label})"
    ax.set_title(title)
    ax.grid(True, alpha=0.3)
    ax.legend(loc="best", fontsize=9)
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    print(f"wrote {out} ({len(t)} points)")


def plot_bperp_profiles(
    run_dir: Path,
    ram,
    a0: float,
    k: float,
    gamma: float,
    out: Path,
    nframes: int = 5,
) -> None:
    import matplotlib.pyplot as plt

    outs = output_numbers(run_dir)
    if not outs:
        return
    picks = [outs[int(round(i * (len(outs) - 1) / (nframes - 1)))] for i in range(nframes)]
    out.parent.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=(7, 4.5))
    cmap = plt.get_cmap("viridis")
    for j, nout in enumerate(picks):
        info = ram.rd_info(nout, path=str(run_dir))
        t = float(info.texp)
        z, bx, by, _ = profile_bperp(run_dir, ram, nout)
        bperp = np.hypot(bx, by)
        amp = analytic_bperp(a0, gamma, t)
        color = cmap(j / max(1, nframes - 1))
        ax.plot(z, bperp, lw=1.1, color=color, label=f"t={t:.2f}")
        ax.axhline(amp, color=color, ls=":", lw=1.0)
    ax.set_xlabel("z")
    ax.set_ylabel(r"$|B_\perp|(z)$")
    ax.set_title(r"Traveling CP wave; dotted = theory envelope A0 exp(-gamma t)")
    ax.grid(True, alpha=0.3)
    ax.legend(loc="upper right", fontsize=8, ncol=2)
    fig.tight_layout()
    fig.savefig(out, dpi=150)
    print(f"wrote {out}")


def fit_decay_rate(t: np.ndarray, amp: np.ndarray) -> float | None:
    if len(t) < 3:
        return None
    ok = amp > 0
    if np.count_nonzero(ok) < 3:
        return None
    coef = np.polyfit(t[ok], np.log(amp[ok]), 1)
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
    p.add_argument("--a0", type=float, default=0.1)
    p.add_argument("--bz", type=float, default=1.0, help="guide-field B_z (legacy option name)")
    p.add_argument("--rho", type=float, default=1.0)
    p.add_argument("--eta-ad", type=float, default=0.1)
    p.add_argument("--boxlen", type=float, default=1.0)
    p.add_argument("--miniram", type=Path, default=Path.home() / "mini-ramses-dev")
    p.add_argument("--out", type=Path, default=None)
    p.add_argument("--plot", action="store_true", help="write damping amplitude plot")
    p.add_argument("--plot-out", type=Path, default=None, help="PNG path for --plot")
    p.add_argument(
        "--plot-level",
        type=int,
        default=None,
        help="level for --plot (default: finest available in --levels)",
    )
    args = p.parse_args()

    ram = import_miniramses(args.miniram)
    k, chi, gamma = theory_gamma(args.eta_ad, args.bz, args.boxlen, args.rho)
    omega = k * args.bz / math.sqrt(args.rho)

    lines: list[str] = []
    lines.append("Sec. 3.3 circularly polarized traveling Alfven wave (Moseley+2023, mu=0)")
    lines.append(
        f"  t=0: B_x = {args.a0} cos(kz), B_y = {args.a0} sin(kz), B_z = {args.bz}, "
        f"v = B, rho = {args.rho}"
    )
    lines.append(f"  Sec. 3.3 (ideal, no AD): constant |B_perp| = {args.a0}, omega = k*B_z/sqrt(rho)")
    lines.append(f"  With eta_ad>0: |B_perp|(t) ~ {args.a0} exp(-gamma t)")
    lines.append(f"  k = 2*pi/boxlen = {k:.6g}")
    lines.append(f"  chi = eta_ad*C_ave^2 = {chi:.6g}")
    lines.append(f"  theory omega = k*B_z/sqrt(rho) = {omega:.6g}")
    lines.append(f"  theory gamma = chi*k^2/(2*rho) = {gamma:.6g}")
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
        z, bx, by, dx = profile_bperp(run, ram, nout)
        bperp = np.hypot(bx, by)
        ref = analytic_bperp(args.a0, gamma, t)
        l1, l2 = l1_l2(bperp, np.full_like(bperp, ref))
        l1s.append(l1)
        l2s.append(l2)
        dxs.append(dx)
        amp = fit_bperp_amplitude(z, bx, by, k)
        amp0 = args.a0 * math.exp(-gamma * t)
        lines.append(
            f"L{lev}  t={t:.5g}  dx={dx:.3e}  L1={l1:.3e}  L2={l2:.3e}  "
            f"|B_perp|_fit={amp:.3e}  |B_perp|_theory={amp0:.3e}  ncell={len(z)}"
        )

        t_series, bx_series, by_series, amp_series = amplitude_series(run, ram, k)
        rate = fit_decay_rate(t_series, amp_series)
        if rate is not None:
            lines.append(
                f"       |B_perp| envelope decay (fitted) = {rate:.6g}  "
                f"(theory gamma = {gamma:.6g}, ratio = {rate / gamma:.3f})"
            )
        if len(amp_series) >= 2:
            tol = max(1.0e-12, 1.0e-4 * args.a0)
            monotonic = bool(np.all(np.diff(amp_series) <= tol))
            bx0 = abs(float(bx_series[0]))
            by0 = abs(float(by_series[0]))
            ratio = bx0 / by0 if by0 > 0 else math.inf
            lines.append(
                f"       envelope monotonic = {monotonic}  "
                f"initial |B_x|_mode={bx0:.3e}  "
                f"initial |B_y|_mode={by0:.3e}  ratio={ratio:.3f}"
            )
        lines.append("")

    if len(l1s) >= 2:
        p1 = convergence_rate(l1s, dxs)
        p2 = convergence_rate(l2s, dxs)
        lines.append(
            f"spatial convergence (log error vs log dx):  L1 slope = {p1:.3f},  L2 slope = {p2:.3f}"
        )

    text = "\n".join(lines) + "\n"
    out = args.out or (args.workdir / "alfven_ad_report.txt")
    out.write_text(text)
    print(text, end="")

    if args.plot:
        plot_lev = args.plot_level
        if plot_lev is None:
            avail = [
                lev
                for lev in args.levels
                if (args.workdir / f"L{lev}").is_dir() and output_numbers(args.workdir / f"L{lev}")
            ]
            if not avail:
                raise SystemExit(f"no runs with outputs under {args.workdir}")
            plot_lev = max(avail)
        run = args.workdir / f"L{plot_lev}"
        t_series, _, _, amp_series = amplitude_series(run, ram, k)
        if len(t_series) < 2:
            raise SystemExit(f"need >=2 outputs in {run} for --plot")
        plot_out = args.plot_out or (args.workdir / f"alfven_ad_damping_L{plot_lev}.png")
        plot_damping(t_series, amp_series, args.a0, gamma, omega, plot_out, label=f"L{plot_lev}")
        plot_bperp_profiles(
            run, ram, args.a0, k, gamma,
            plot_out.with_name(plot_out.stem + "_profiles.png"),
        )


if __name__ == "__main__":
    main()
