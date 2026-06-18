# AGENTS — mini-ramses-hackathon

Harness-only repo. Physics code: `mini-ramses-dev` (separate checkout).

## Session start

1. Read `README.md` and `CLUSTER.md`.
2. For validation criteria, read mini-ramses-dev `AGENTS.md` and Obsidian [[mini-ramses — debug-playbook]].
3. Mac agents **cannot** compile NVHPC/CUDA or submit Slurm jobs — give exact cluster commands.

## IC and output policy (mandatory)

**Never commit initial conditions or simulation output.**

- **ICs:** `ics_*`, `ic_*`, `ic_grafic`, grafic face files, zoom `level_*` dirs — generated under `${HARNESS_DIR}/ics_*` at runtime.
- **Output:** RAMSES `output_*/` snapshots, harness workdirs (`dmo_gpu_*`, `dmo_cpu_*`, `profiles_*`, …), `run.log`, plots, profiling traces — written under `${RUN_DIR}` on scratch.

`.gitignore` enforces both; do not `git add -f` IC or output paths.

## Architecture

```
export CLUSTER=stellar|marlowe|sherlock
source bin/hackathon-env.sh
  → clusters/${CLUSTER}.profile
  → hackathon_common.sh
./submit_profiles.sh <case>
  → hackathon_sbatch (profile Slurm opts)
  → slurm/*.slurm
```

Makefiles live in `makefiles/`; namelists in `namelists/`; Slurm scripts in `slurm/`.

## Key files

| File | Role |
| --- | --- |
| `hackathon_common.sh` | Build, IC generators, `hackathon_sbatch`, module load |
| `submit_profiles.sh` | Case launcher |
| `clusters/*.profile` | Per-cluster paths and defaults |
| `bin/hackathon-env.sh` | Entry point for env |
| `bin/install.sh` | Deploy to scratch via git |
| `makefiles/Makefile.a100` / `.h100` | GPU builds (serial `make` only) |

## Cluster scratch paths

- Stellar: `/scratch/gpfs/moseley/hackathon`
- Marlowe: `/scratch/m000115/hackathon`

## Validation (minimum)

| Case | Command | Pass |
| --- | --- | --- |
| Smoke | `./submit_profiles.sh test` | Job completes |
| DMO GPU | `./submit_profiles.sh dmo-gpu` | `Run completed` |
| MHD | `./submit_profiles.sh orszag-tang` | `emag > 0` step 1 in `run.log` |
| TURB | `./submit_profiles.sh mhd-turb` | FFTW module loads, run completes |

## Agent constraints

- Do not change namelist defaults silently — show diff.
- Do not claim fixes worked without fresh `run.log`.
- GPU builds: **serial make** (`-j` races `.mod` files).
- `NPRE=4` + `FASTMATH=1` is known-bad on GPU.

## Updating docs

When paths or workflow change, update:

- This file
- `mini-ramses-dev/AGENTS.md` (harness section)
- Obsidian [[runbook — Stellar]], [[runbook — Marlowe]]
