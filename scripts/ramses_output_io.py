"""Minimal RAMSES snapshot I/O for the DMO CPU vs GPU harness (numpy only).

Reads ``output_NNNNN/part.*`` stream-access binaries (``access="stream"`` layout
from ``open_part_file`` in ``ramses_commons.f90``) and ``part_header.txt`` /
``info.txt``. Matches ``utils/f90/part2map.f90`` byte offsets.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path

import numpy as np

OUTPUT_RE = re.compile(r"^output_(\d+)$")

# Known RAMSES part fields in on-disk order (subset we may skip while seeking).
_FIELD_SIZES = {
    "pos": lambda ndim, npart: ndim * npart * 4,
    "vel": lambda ndim, npart: ndim * npart * 4,
    "mass": lambda _ndim, npart: npart * 4,
    "potential": lambda _ndim, npart: npart * 4,
    "metallicity": lambda _ndim, npart: npart * 4,
    "accel": lambda ndim, npart: ndim * npart * 4,
    "acceleration": lambda ndim, npart: ndim * npart * 4,
    "angmom": lambda ndim, npart: ndim * npart * 4,
    "birth_time": lambda _ndim, npart: npart * 4,
    "merging_time": lambda _ndim, npart: npart * 4,
    "level": lambda _ndim, npart: npart * 4,
    "birth_id": lambda _ndim, npart: npart * 4,
    "identity": lambda _ndim, npart: npart * 4,
    "merging_id": lambda _ndim, npart: npart * 4,
    "tracking_id": lambda _ndim, npart: npart * 4,
    "size": lambda _ndim, npart: npart * 4,
    "charge": lambda _ndim, npart: npart * 4,
}


@dataclass
class RunInfo:
    nfile: int
    ncpu: int
    ndim: int
    levelmin: int
    nlevelmax: int
    boxlen: float
    time: float
    aexp: float


@dataclass
class PartSnapshot:
    npart: int
    ndim: int
    pos: np.ndarray  # (ndim, npart)
    vel: np.ndarray  # (ndim, npart)
    mass: np.ndarray  # (npart,)
    level: np.ndarray  # (npart,) int32
    birth_id: np.ndarray  # (npart,) int32 — RAMSES idp (i8b=4 by default)


def parse_info_txt(path: Path) -> RunInfo:
    fields: dict[str, float] = {}
    for line in path.read_text().splitlines():
        if "=" not in line:
            continue
        key, val = line.split("=", 1)
        fields[key.strip()] = float(val.strip())
    nfile = int(fields["nfile"])
    ncpu = int(fields.get("ncpu", nfile))
    if nfile > 0:
        ncpu = nfile
    levelmax = int(fields.get("nlevelmax", fields.get("levelmax", fields["levelmin"])))
    return RunInfo(
        nfile=nfile,
        ncpu=ncpu,
        ndim=int(fields["ndim"]),
        levelmin=int(fields["levelmin"]),
        nlevelmax=levelmax,
        boxlen=fields["boxlen"],
        time=fields["time"],
        aexp=fields["aexp"],
    )


def parse_part_header(path: Path) -> tuple[int, int, list[str]]:
    lines = path.read_text().splitlines()
    npart = int(lines[1].strip())
    nfile = int(lines[3].strip())
    fields = lines[5].strip().lower().split()
    return npart, nfile, fields


def discover_output_nums(run_dir: Path) -> list[int]:
    nums: list[int] = []
    for entry in run_dir.iterdir():
        if not entry.is_dir():
            continue
        match = OUTPUT_RE.match(entry.name)
        if match:
            nums.append(int(match.group(1)))
    return sorted(nums)


def _field_offset(fields: list[str], target: str, ndim: int, npart: int) -> int:
    off = 9  # ndim @1, npart @5 (1-based stream positions in part2map.f90)
    for name in fields:
        key = name.strip().lower()
        if key == target:
            return off
        size_fn = _FIELD_SIZES.get(key)
        if size_fn is None:
            raise ValueError(f"unknown part field {name!r} in header; extend _FIELD_SIZES")
        off += size_fn(ndim, npart)
    raise ValueError(f"field {target!r} not listed in part_header.txt")


def _read_pos_vel_mass(data: memoryview, ndim: int, npart: int):
    pos = np.empty((ndim, npart), dtype=np.float64)
    vel = np.empty((ndim, npart), dtype=np.float64)
    off = 8  # 0-based: skip ndim+npart words (8 bytes)
    for idim in range(ndim):
        pos[idim] = np.frombuffer(data, dtype="<f4", count=npart, offset=off)
        off += npart * 4
    for idim in range(ndim):
        vel[idim] = np.frombuffer(data, dtype="<f4", count=npart, offset=off)
        off += npart * 4
    mass = np.frombuffer(data, dtype="<f4", count=npart, offset=off)
    return pos, vel, mass.astype(np.float64)


def read_part_file(path: Path, fields: list[str], ndim: int, npart: int) -> PartSnapshot:
    raw = path.read_bytes()
    pos, vel, mass = _read_pos_vel_mass(raw, ndim, npart)

    level_off = _field_offset(fields, "level", ndim, npart) - 1
    level = np.frombuffer(raw, dtype="<i4", count=npart, offset=level_off)

    id_off = _field_offset(fields, "birth_id", ndim, npart) - 1
    birth_id = np.frombuffer(raw, dtype="<i4", count=npart, offset=id_off)

    return PartSnapshot(npart, ndim, pos, vel, mass, level, birth_id)


def merge_snapshots(parts: list[PartSnapshot]) -> PartSnapshot:
    if not parts:
        raise ValueError("no particle files")
    ndim = parts[0].ndim
    npart = sum(p.npart for p in parts)
    pos = np.empty((ndim, npart), dtype=np.float64)
    vel = np.empty((ndim, npart), dtype=np.float64)
    mass = np.empty(npart, dtype=np.float64)
    level = np.empty(npart, dtype=np.int32)
    birth_id = np.empty(npart, dtype=np.int32)
    off = 0
    for p in parts:
        n = p.npart
        pos[:, off : off + n] = p.pos
        vel[:, off : off + n] = p.vel
        mass[off : off + n] = p.mass
        level[off : off + n] = p.level
        birth_id[off : off + n] = p.birth_id
        off += n
    return PartSnapshot(npart, ndim, pos, vel, mass, level, birth_id)


def read_part_snapshot(
    run_dir: Path,
    nout: int,
    prefix: str = "part",
    backup: bool = False,
) -> PartSnapshot:
    run_dir = run_dir.resolve()
    tag = str(nout).zfill(5)
    if backup:
        snap_dir = run_dir / f"backup_{tag}"
    else:
        snap_dir = run_dir / f"output_{tag}"

    info = parse_info_txt(snap_dir / "info.txt")
    header_npart, header_nfile, fields = parse_part_header(snap_dir / f"{prefix}_header.txt")

    per_cpu: list[PartSnapshot] = []
    for icpu in range(1, info.ncpu + 1):
        cpu_tag = str(icpu).zfill(5)
        part_path = snap_dir / f"{prefix}.{cpu_tag}"
        if not part_path.is_file():
            raise FileNotFoundError(part_path)
        # npart from file header (stream @ byte 5) should match slice size
        file_npart = int(np.fromfile(part_path, dtype=np.int32, count=1, offset=4)[0])
        per_cpu.append(read_part_file(part_path, fields, info.ndim, file_npart))

    merged = merge_snapshots(per_cpu)
    if header_npart and merged.npart != header_npart:
        print(f"[WARN] part_header npart={header_npart} != merged {merged.npart}")
    return merged
