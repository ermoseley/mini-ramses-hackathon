#!/usr/bin/env python3
"""Consolidate kick_drift_part_kernel NCU full-set CSV into the Phase-2 gate table.

The ncu-cic kick job profiles 5 launches; durations are bimodal (kick vs drift
actions). Launches are split Slow/Fast by the midpoint of gpu__time_duration.sum
and gates are evaluated on the SLOW-launch average, per the Phase-2 acceptance
criteria (vs the post-042 scalar baseline).

Usage:
  consolidate_kick_ncu.py COOP_RAW.csv [--baseline SCALAR_RAW.csv]

Export the CSV from the .ncu-rep with:
  ncu --import ncu_kick_drift.ncu-rep --csv --page raw > raw.csv
"""

from __future__ import annotations

import argparse
import csv
import sys


# (label, header substring, gate kind, threshold, unit hint)
# gate kinds: 'lt' value < thr ; 'gt' value > thr ; 'le' ; 'eq0' ; None = report only
GATES = [
    ("duration [ms]",          "gpu__time_duration.sum",                                             "lt", 1.0,   "ms"),
    ("long-scoreboard [inst]", "smsp__average_warps_issue_stalled_long_scoreboard_per_issue_active", "lt", 8.0,   ""),
    ("excess L2 glob sectors", "memory_l2_theoretical_sectors_global_excessive",                     "lt", 22e6,  "raw"),
    ("warps eligible/cycle",   "smsp__warps_eligible.avg.per_cycle_active",                          "gt", 0.36,  ""),
    ("issue active [%]",       "sm__issue_active.avg.pct_of_peak_sustained_elapsed",                 "gt", 27.0,  "%"),
    ("registers/thread",       "launch__registers_per_thread",                                       "le", 102,   ""),
    ("local sectors (spill)",  "memory_l2_theoretical_sectors_local",                                "eq0", 0,    "raw"),
    ("sass local loads",       "sass__inst_executed_local_loads",                                    "eq0", 0,    "raw"),
    ("sass local stores",      "sass__inst_executed_local_stores",                                   "eq0", 0,    "raw"),
]

EXTRAS = [
    ("elapsed cycles",         "gpc__cycles_elapsed.max"),
    ("warps active/sched",     "smsp__warps_active.avg.per_cycle_active"),
    ("achieved occupancy [%]", "sm__warps_active.avg.pct_of_peak_sustained_active"),
    ("L1TEX hit rate [%]",     "l1tex__t_sector_hit_rate.pct"),
    ("L2 hit rate [%]",        "lts__t_sector_hit_rate.pct"),
    ("regs/thread allocated",  "launch__registers_per_thread_allocated"),
]


def parse_num(s: str):
    s = s.strip().strip('"').replace(",", "")
    if not s or s in ("no data", "N/A"):
        return None
    try:
        return float(s)
    except ValueError:
        return None


def find_col(hdr, sub):
    # exact match first, then shortest header containing the substring
    if sub in hdr:
        return hdr.index(sub)
    cand = [i for i, h in enumerate(hdr) if sub in h]
    if not cand:
        return None
    cand.sort(key=lambda i: len(hdr[i]))
    return cand[0]


def scale(val, unit, hint):
    """Normalize to ms / raw counts per the units row."""
    u = (unit or "").strip().strip('"')
    if hint == "ms":
        return {"usecond": val / 1e3, "msecond": val, "nsecond": val / 1e6,
                "second": val * 1e3}.get(u, val)
    if hint == "raw":
        for pfx, m in (("G", 1e9), ("M", 1e6), ("K", 1e3)):
            if u.startswith(pfx):
                return val * m
    return val


def load(path):
    with open(path, newline="") as f:
        rows = list(csv.reader(f))
    hdr, units, data = rows[0], rows[1], rows[2:]
    data = [r for r in data if r and r[0].strip('"').strip().isdigit()]
    return hdr, units, data


def consolidate(path):
    hdr, units, data = load(path)
    dcol = find_col(hdr, "gpu__time_duration.sum")
    if dcol is None:
        sys.exit(f"{path}: gpu__time_duration.sum not found")
    durs = [scale(parse_num(r[dcol]) or 0.0, units[dcol], "ms") for r in data]
    mid = (min(durs) + max(durs)) / 2.0
    slow = [i for i, d in enumerate(durs) if d > mid]
    fast = [i for i, d in enumerate(durs) if d <= mid]
    out = {"_n": len(data), "_slow_ids": slow, "_fast_ids": fast,
           "_durs": [round(d, 4) for d in durs]}
    specs = [(g[0], g[1], g[4]) for g in GATES] + [(l, s, "") for l, s in EXTRAS]
    for label, sub, hint in specs:
        col = find_col(hdr, sub)
        if col is None:
            out[label] = (None, None)
            continue
        vals = [parse_num(r[col]) for r in data]
        vals = [scale(v, units[col], hint) if v is not None else None for v in vals]
        sv = [vals[i] for i in slow if vals[i] is not None]
        fv = [vals[i] for i in fast if vals[i] is not None]
        out[label] = (sum(sv) / len(sv) if sv else None,
                      sum(fv) / len(fv) if fv else None)
    return out


def fmt(v):
    if v is None:
        return "n/a"
    if abs(v) >= 1e6:
        return f"{v/1e6:.2f}M"
    if abs(v) >= 1000:
        return f"{v:,.0f}"
    return f"{v:.3f}".rstrip("0").rstrip(".")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("csv")
    ap.add_argument("--baseline", help="scalar baseline raw CSV for side-by-side")
    args = ap.parse_args()

    cur = consolidate(args.csv)
    base = consolidate(args.baseline) if args.baseline else None

    print(f"{args.csv}: {cur['_n']} launches, durations(ms)={cur['_durs']}")
    print(f"  slow ids(0-based)={cur['_slow_ids']}  fast ids={cur['_fast_ids']}")
    if base:
        print(f"baseline {args.baseline}: durations(ms)={base['_durs']}")
    print()
    hdrline = f"{'metric':<24} {'gate':<10} {'slow':>10} {'fast':>10}"
    if base:
        hdrline += f" {'base.slow':>10} {'base.fast':>10} {'d.slow%':>8}"
    hdrline += "  verdict"
    print(hdrline)
    print("-" * len(hdrline))
    for label, sub, kind, thr, hint in GATES:
        s, f = cur.get(label, (None, None))
        gate_s = {"lt": f"< {fmt(thr)}", "gt": f"> {fmt(thr)}",
                  "le": f"<= {fmt(thr)}", "eq0": "== 0"}[kind]
        verdict = "n/a"
        if s is not None:
            ok = {"lt": s < thr, "gt": s > thr, "le": s <= thr,
                  "eq0": s == 0}[kind]
            verdict = "PASS" if ok else "FAIL"
        line = f"{label:<24} {gate_s:<10} {fmt(s):>10} {fmt(f):>10}"
        if base:
            bs, bf = base.get(label, (None, None))
            dpc = (f"{100*(s-bs)/bs:+.1f}%" if (s is not None and bs not in (None, 0))
                   else "n/a")
            line += f" {fmt(bs):>10} {fmt(bf):>10} {dpc:>8}"
        line += f"  {verdict}"
        print(line)
    print()
    for label, _ in EXTRAS:
        s, f = cur.get(label, (None, None))
        line = f"{label:<24} {'':<10} {fmt(s):>10} {fmt(f):>10}"
        if base:
            bs, bf = base.get(label, (None, None))
            line += f" {fmt(bs):>10} {fmt(bf):>10}"
        print(line)


if __name__ == "__main__":
    main()
