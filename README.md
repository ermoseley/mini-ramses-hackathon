# mini-ramses-hackathon

Multi-cluster Slurm harness for [mini-ramses-dev](https://github.com/rteyssie/mini-ramses) GPU validation, profiling, and parity tests.

**GitHub:** https://github.com/ermoseley/mini-ramses-hackathon

## Quick start (cluster)

```bash
# One-time install to scratch (see clusters/*.profile for default paths)
export CLUSTER=stellar   # or marlowe
git clone https://github.com/ermoseley/mini-ramses-hackathon.git /scratch/gpfs/moseley/hackathon
# or: CLUSTER=stellar bin/install.sh

cd /scratch/gpfs/moseley/hackathon   # Stellar default
export CLUSTER=stellar
export MINIRAM=~/ramses-development/mini-ramses-dev   # if not ~/mini-ramses-dev
bin/doctor.sh
./submit_profiles.sh test
```

Add to `~/.bashrc` on each cluster:

```bash
export CLUSTER=stellar   # or marlowe on Marlowe login nodes
```

## Layout

| Path | Purpose |
| --- | --- |
| `clusters/*.profile` | Per-cluster scratch paths, Slurm opts, modules, GPU defaults |
| `bin/hackathon-env.sh` | Source profile + `hackathon_common.sh` |
| `bin/install.sh` | `git clone` / `git pull` to scratch |
| `bin/doctor.sh` | Print resolved harness config |
| `makefiles/` | `Makefile.a100`, `Makefile.h100`, `Makefile.cpu`, `Makefile.debug-cosmo` |
| `namelists/` | Test namelists (paths are short; IC dirs are separate) |
| `slurm/` | Cluster-neutral Slurm scripts (partition/gres via profile) |
| `scripts/` | Plot/compare/NCU helpers |

RAMSES source lives in a **separate** repo (`mini-ramses-dev`), not in this harness.

## Runtime artifacts (not in git)

**Initial conditions and simulation output are never stored in this repo.**

| Kind | Examples | Where they live |
| --- | --- | --- |
| ICs | `ics_ramses/`, `ics_orszag_tang/`, `ic_grafic/` | `${HARNESS_DIR}/ics_*` (generated at job time) |
| Output | `output_00001/`, `dmo_gpu_<jobid>/`, `profiles_<jobid>/` | `${RUN_DIR}` (scratch, same as harness by default) |
| Logs / plots | `run.log`, `*.png`, `*.nsys-rep` | Job workdirs under `${RUN_DIR}` |

`.gitignore` blocks all of the above. Do not `git add -f` IC or output paths. After `git clone`, run a case to populate scratch; do not copy old output trees into the repo.

If you see IC or output files in `git status`, leave them untracked.

## Cluster profiles

| `CLUSTER` | Scratch default | GPU | Makefile |
| --- | --- | --- | --- |
| `stellar` | `/scratch/gpfs/moseley/hackathon` | A100 `sm_80` | `Makefile.a100` |
| `marlowe` | `/scratch/m000115/hackathon` | H100 `sm_90` | `Makefile.h100` |
| `sherlock` | TBD | TBD | stub |

See [CLUSTER.md](CLUSTER.md) for install paths, modules, and drift notes.

## Common commands

```bash
./submit_profiles.sh test
./submit_profiles.sh dmo-gpu
./submit_profiles.sh mhd-turb          # needs FFTW module (profile sets default)
./submit_profiles.sh ot-amr            # Marlowe: L10, NPRE=8 via profile
CLEAN=0 ./submit_profiles.sh brio-wu   # incremental rebuild (default CLEAN=1)
BUILD_BINARIES=0 ./submit_profiles.sh orszag-tang
```

## Updating the harness

```bash
cd $HARNESS_DIR
git pull --ff-only
```

Do **not** use `sync_from_stellar.sh` (deprecated). Keep clusters aligned via this repo.

## Environment variables

| Var | Meaning |
| --- | --- |
| `CLUSTER` | `stellar` \| `marlowe` \| `sherlock` |
| `HARNESS_DIR` | Harness root (defaults from profile scratch path) |
| `MINIRAM` | Path to `mini-ramses-dev` checkout |
| `CLEAN` | `1` (default) run `make clean` before GPU build; `0` incremental |
| `BUILD_BINARIES` | `1` build before submit; `0` reuse existing binary |
| `GPU_NPRE`, `GPU_FASTMATH`, … | Passed through to `hackathon_build_binary` |

Full list: `./submit_profiles.sh` with no args (prints help).
