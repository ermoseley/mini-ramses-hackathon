#!/usr/bin/env python3
"""Ponomarenko x-z column-integrated magnetic energy density (Blues map)."""

from __future__ import annotations

import sys
from pathlib import Path

import plot_abc_bmag_xz as bmag


def main(argv: list[str] | None = None) -> int:
    if argv is None:
        argv = sys.argv[1:]
    if "--label" not in argv:
        argv = ["--label", "Ponomarenko", *argv]
    sys.argv = [sys.argv[0], *argv]
    return bmag.main()


if __name__ == "__main__":
    raise SystemExit(main())
