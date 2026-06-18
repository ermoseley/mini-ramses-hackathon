#!/usr/bin/env python3
"""Compare CPU vs GPU RAMSES snapshot outputs (output_NNNNN/) for DMO runs.

Post-merge validation harness: reads standard ``part.*`` dumps (not pm_dump).
Uses the local numpy-only ``ramses_output_io`` module by default; pass
``--backend miniramses`` to use ``mini-ramses-dev/utils/py/miniramses.py``.

Usage:
  compare_dmo_outputs.py --cpu /path/cpu_run --gpu /path/gpu_run \\
      [--rtol 1e-4] [--atol 1e-6] [--max-bad-frac 1e-4]
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

import numpy as np

# Prefer harness-local I/O (no astropy/matplotlib dependency chain).
_HERE = Path(__file__).resolve().parent
if str(_HERE) not in sys.path:
    sys.path.insert(0, str(_HERE))

import ramses_output_io as rio


def is_close(a: np.ndarray, b: np.ndarray, rtol: float, atol: float) -> np.ndarray:
    scale = np.maximum(np.abs(a), np.abs(b))
    return np.abs(a - b) <= atol + rtol * scale


def compare_field(name: str, cpu: np.ndarray, gpu: np.ndarray, rtol: float, atol: float):
    """Return (n_bad_particles, max_rel) for vector fields (dims, npart) or 1d."""
    if cpu.ndim == 1:
        bad = ~is_close(cpu, gpu, rtol, atol)
        per_part_bad = bad
    else:
        bad = ~is_close(cpu, gpu, rtol, atol)
        per_part_bad = np.any(bad, axis=0)
    n_bad = int(np.count_nonzero(per_part_bad))
    if n_bad == 0:
        rel = 0.0
    else:
        if cpu.ndim == 1:
            diff = np.abs(cpu - gpu)[per_part_bad]
            denom = np.maximum(np.abs(cpu[per_part_bad]), np.abs(gpu[per_part_bad]))
        else:
            diff = np.max(np.abs(cpu - gpu), axis=0)[per_part_bad]
            denom = np.maximum(
                np.max(np.abs(cpu), axis=0)[per_part_bad],
                np.max(np.abs(gpu), axis=0)[per_part_bad],
            )
        denom = np.maximum(denom, 1e-30)
        rel = float(np.max(diff / denom))
    return n_bad, rel


def load_snapshot(backend: str, nout: int, run_dir: Path, miniramses_py: str | None):
    if backend == "ramses_output_io":
        return rio.read_part_snapshot(run_dir, nout)
    if backend == "miniramses":
        if miniramses_py:
            sys.path.insert(0, str(Path(miniramses_py).resolve()))
        else:
            for candidate in (
                _HERE / "../../mini-ramses-dev/utils/py",
                _HERE / "../../../mini-ramses-dev/utils/py",
            ):
                if (candidate / "miniramses.py").is_file():
                    sys.path.insert(0, str(candidate.resolve()))
                    break
        import miniramses as ram  # noqa: WPS433

        p = ram.rd_part(nout, path=str(run_dir) + "/", silent=True)
        return rio.PartSnapshot(
            npart=p.npart,
            ndim=p.ndim,
            pos=np.asarray(p.pos, dtype=np.float64),
            vel=np.asarray(p.vel, dtype=np.float64),
            mass=np.asarray(p.mass, dtype=np.float64),
            level=np.asarray(p.level, dtype=np.int32),
            birth_id=np.asarray(p.birth_id, dtype=np.int32),
        )
    raise ValueError(f"unknown backend {backend!r}")


def compare_snapshot(
    nout: int,
    cpu_dir: Path,
    gpu_dir: Path,
    rtol: float,
    atol: float,
    max_bad_frac: float,
    backend: str,
    miniramses_py: str | None,
):
    cpu = load_snapshot(backend, nout, cpu_dir, miniramses_py)
    gpu = load_snapshot(backend, nout, gpu_dir, miniramses_py)

    if cpu.npart != gpu.npart:
        return {
            "nout": nout,
            "status": "FAIL",
            "reason": f"npart mismatch cpu={cpu.npart} gpu={gpu.npart}",
        }

    order_cpu = np.argsort(cpu.birth_id, kind="stable")
    order_gpu = np.argsort(gpu.birth_id, kind="stable")
    if not np.array_equal(cpu.birth_id[order_cpu], gpu.birth_id[order_gpu]):
        return {
            "nout": nout,
            "status": "FAIL",
            "reason": "birth_id sets differ after sort",
        }

    fields = {
        "pos": (cpu.pos[:, order_cpu], gpu.pos[:, order_gpu]),
        "vel": (cpu.vel[:, order_cpu], gpu.vel[:, order_gpu]),
        "mass": (cpu.mass[order_cpu], gpu.mass[order_gpu]),
        "level": (
            cpu.level[order_cpu].astype(np.float64),
            gpu.level[order_gpu].astype(np.float64),
        ),
    }

    total = cpu.npart
    worst_frac = 0.0
    worst_rel = 0.0
    worst_field = ""
    details = []

    for fname, (cval, gval) in fields.items():
        if fname == "level":
            n_bad = int(np.count_nonzero(cval != gval))
            rel = 0.0
        else:
            n_bad, rel = compare_field(fname, cval, gval, rtol, atol)
        frac = n_bad / total
        details.append((fname, n_bad, frac, rel))
        if frac > worst_frac or (math.isclose(frac, worst_frac) and rel > worst_rel):
            worst_frac = frac
            worst_rel = rel
            worst_field = fname

    status = "PASS"
    reason = ""
    if worst_frac > max_bad_frac:
        status = "FAIL"
        reason = (
            f"{worst_field}: {worst_frac:.3e} of particles outside rtol={rtol:g} "
            f"(max rel err {worst_rel:.3e}, limit {max_bad_frac:g})"
        )

    return {
        "nout": nout,
        "status": status,
        "reason": reason,
        "npart": total,
        "details": details,
        "worst_field": worst_field,
        "worst_frac": worst_frac,
        "worst_rel": worst_rel,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--cpu", required=True, type=Path, help="CPU run directory")
    ap.add_argument("--gpu", required=True, type=Path, help="GPU run directory")
    ap.add_argument("--rtol", type=float, default=1e-4)
    ap.add_argument("--atol", type=float, default=1e-6)
    ap.add_argument(
        "--max-bad-frac",
        type=float,
        default=1e-4,
        help="FAIL if more than this fraction of particles miss rtol on any field",
    )
    ap.add_argument(
        "--backend",
        choices=("ramses_output_io", "miniramses"),
        default="ramses_output_io",
        help="snapshot reader (default: harness-local numpy I/O)",
    )
    ap.add_argument(
        "--miniramses-py",
        default="",
        help="only for --backend miniramses: directory containing miniramses.py",
    )
    ap.add_argument(
        "--snapshots",
        default="",
        help="comma-separated output numbers to check (default: all common)",
    )
    args = ap.parse_args()

    cpu_dir = args.cpu.resolve()
    gpu_dir = args.gpu.resolve()
    cpu_outs = set(rio.discover_output_nums(cpu_dir))
    gpu_outs = set(rio.discover_output_nums(gpu_dir))
    common = sorted(cpu_outs & gpu_outs)
    only_cpu = sorted(cpu_outs - gpu_outs)
    only_gpu = sorted(gpu_outs - cpu_outs)

    if args.snapshots.strip():
        wanted = {int(x) for x in args.snapshots.split(",") if x.strip()}
        common = sorted(wanted & set(common))
        missing = sorted(wanted - set(common))
        if missing:
            print(f"[WARN] requested snapshots not common to both runs: {missing}")

    print(f"CPU outputs: {sorted(cpu_outs)}")
    print(f"GPU outputs: {sorted(gpu_outs)}")
    if only_cpu:
        print(f"[WARN] only on CPU: {only_cpu}")
    if only_gpu:
        print(f"[WARN] only on GPU: {only_gpu}")
    if not common:
        print("[FAIL] no common output_NNNNN directories")
        return 1

    miniramses_py = args.miniramses_py or None
    n_fail = 0
    for nout in common:
        result = compare_snapshot(
            nout,
            cpu_dir,
            gpu_dir,
            args.rtol,
            args.atol,
            args.max_bad_frac,
            args.backend,
            miniramses_py,
        )
        print(f"\n=== output_{nout:05d} (npart={result.get('npart', '?')}) ===")
        if result["status"] == "FAIL" and "details" not in result:
            print(f"[FAIL] {result['reason']}")
            n_fail += 1
            continue
        for fname, n_bad, frac, rel in result["details"]:
            tag = "ok" if frac <= args.max_bad_frac else "BAD"
            print(f"  {fname:5s}: n_bad={n_bad:8d}  frac={frac:.3e}  max_rel={rel:.3e}  [{tag}]")
        if result["status"] == "FAIL":
            print(f"[FAIL] {result['reason']}")
            n_fail += 1
        else:
            print("[PASS] broad agreement")

    print()
    if n_fail == 0:
        print(f"PASS: all {len(common)} common snapshots within broad-agreement limits")
        return 0
    print(f"FAIL: {n_fail} snapshot(s) outside limits")
    return 1


if __name__ == "__main__":
    sys.exit(main())
