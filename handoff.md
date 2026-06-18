# Handoff: mini-ramses-hackathon (multi-cluster harness)

Summary for agents continuing harness work. Physics code stays in **mini-ramses-dev**; this repo is Slurm/scripts only.

## What this is

| Item | Value |
| --- | --- |
| **GitHub** | https://github.com/ermoseley/mini-ramses-hackathon |
| **Local clone** | `~/ramses-development/mini-ramses-hackathon` |
| **Default branch** | `main` |
| **Agent guide** | `AGENTS.md` |

## Architecture

```
export CLUSTER=stellar|marlowe|sherlock
source bin/hackathon-env.sh
  → clusters/${CLUSTER}.profile   # scratch paths, Slurm opts, modules, GPU defaults
  → hackathon_common.sh
./submit_profiles.sh <case>
  → hackathon_sbatch (profile-driven partition/gres/mem)
  → slurm/*.slurm
```

**Layout:** `clusters/`, `bin/`, `makefiles/`, `namelists/`, `slurm/`, `scripts/`, `submit_profiles.sh`, `hackathon_common.sh`

## Cluster scratch paths

| Cluster | `CLUSTER` | `HARNESS_DIR` default |
| --- | --- | --- |
| Stellar | `stellar` | `/scratch/gpfs/moseley/hackathon` |
| Marlowe | `marlowe` | `/scratch/m000115/hackathon` |
| Sherlock | `sherlock` | stub (path TBD) |

## Install on cluster

```bash
export CLUSTER=stellar   # or marlowe
git clone https://github.com/ermoseley/mini-ramses-hackathon.git /scratch/gpfs/moseley/hackathon
cd /scratch/gpfs/moseley/hackathon
export MINIRAM=~/ramses-development/mini-ramses-dev   # if not ~/mini-ramses-dev
bin/doctor.sh
./submit_profiles.sh test
```

Updates: `git pull --ff-only` in `$HARNESS_DIR`. Do **not** use `sync_from_stellar.sh`.

## Hard rules (git policy)

**Never commit:**

- **ICs:** `ics_*`, `ic_*`, `ic_grafic/`, zoom `level_*`
- **Output:** `output_*`, `dmo_gpu_*`, `dmo_cpu_*`, `profiles_*`, `run.log`, plots, nsys/ncu traces

All blocked in `.gitignore`. Runtime artifacts live on scratch only.

## Common commands

```bash
./submit_profiles.sh test
./submit_profiles.sh dmo-gpu
./submit_profiles.sh mhd-turb          # Stellar; needs FFTW module from profile
./submit_profiles.sh ot-amr            # Marlowe: L10, NPRE=8 via profile
CLEAN=0 ./submit_profiles.sh brio-wu   # incremental GPU rebuild (default CLEAN=1)
BUILD_BINARIES=0 ./submit_profiles.sh orszag-tang
```

GPU builds: **serial `make` only** (no `-j`). Known-bad: `NPRE=4` + `FASTMATH=1`.

## Cross-cluster drift

Do not copy namelists blindly between clusters.

| Setting | Stellar | Marlowe |
| --- | --- | --- |
| Makefile | `Makefile.a100` | `Makefile.h100` |
| CUDA arch | `sm_80` | `sm_90` |
| Default NPRE | 4 | 8 |
| `ot-amr` levelmax | 8 | 10 |

## Agent constraints

- Mac/Cursor agent **cannot** compile NVHPC/CUDA or submit Slurm jobs — give exact cluster commands.
- Do not change namelist defaults silently (show diff).
- Do not claim fixes worked without fresh `run.log` (`emag > 0` at step 1 for MHD).
- Physics edits → `mini-ramses-dev`; harness edits → this repo.

## Verified vs not verified

| Verified (local) | Not verified (needs cluster) |
| --- | --- |
| Repo created + pushed to GitHub | `./submit_profiles.sh test` on Stellar scratch |
| Harness files committed; no ICs/output in git | `./submit_profiles.sh mhd-turb` (FFTW) |
| Bash syntax checks pass | `./submit_profiles.sh ot-amr` on Marlowe |
| Obsidian runbooks updated | Deploy may need reconcile if cluster copy differed |

## Docs to read first

1. `README.md`
2. `CLUSTER.md`
3. `AGENTS.md`
4. Obsidian: `mini-ramses — debug-playbook`, `runbook — Stellar`, `runbook — Marlowe`

## Suggested next task (cluster)

```bash
export CLUSTER=stellar
cd /scratch/gpfs/moseley/hackathon
git pull --ff-only
bin/doctor.sh
./submit_profiles.sh test
```

Then `mhd-turb` on Stellar and `ot-amr` on Marlowe. Log results in Obsidian `30-runs/` or `templates/session-handoff.md`.
