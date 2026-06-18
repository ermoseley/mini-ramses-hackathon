# CLUSTER — multi-cluster harness

Canonical install and runtime paths for **mini-ramses-hackathon**. RAMSES physics code remains in `mini-ramses-dev`; this repo is only the Slurm harness.

## Install paths

| Cluster | `CLUSTER` | Default `HARNESS_DIR` | GPU |
| --- | --- | --- | --- |
| Stellar | `stellar` | `/scratch/gpfs/moseley/hackathon` | A100 |
| Marlowe | `marlowe` | `/scratch/m000115/hackathon` | H100 |
| Sherlock | `sherlock` | TBD | TBD |

Home-directory copies (`~/hackathon`, `~/marlowe/hackathon`) may exist for convenience; **scratch is the runtime default** when the profile path exists.

### Stellar

```bash
export CLUSTER=stellar
git clone https://github.com/ermoseley/mini-ramses-hackathon.git /scratch/gpfs/moseley/hackathon
cd /scratch/gpfs/moseley/hackathon
bin/doctor.sh
```

Modules (from `clusters/stellar.profile`): `nvhpc/25.5`, `fftw/nvhpc-21.5/3.3.9` for `mhd-turb`.

### Marlowe

```bash
export CLUSTER=marlowe
git clone https://github.com/ermoseley/mini-ramses-hackathon.git /scratch/m000115/hackathon
cd /scratch/m000115/hackathon
bin/doctor.sh
```

Modules: `slurm nvhpc/25.5 cudnn/cuda12/9.3.0.75 gcc/64`, FFTW as on Stellar.

Slurm: `--account=marlowe-m000115`, `--partition=preempt`, `-G 1`.

### Sherlock

Stub profile only. Set `HARNESS_DIR_DEFAULT` when scratch path is known.

## Workflow

1. `export CLUSTER=…` (or hostname auto-detect in `bin/hackathon-env.sh`)
2. `source bin/hackathon-env.sh` — loads `clusters/${CLUSTER}.profile` + `hackathon_common.sh`
3. `./submit_profiles.sh <case>` — builds (unless `BUILD_BINARIES=0`) and submits

Slurm resource lines (`--partition`, `--gres`, `--mem`, Marlowe `--account`) come from `CLUSTER_SBATCH_*_OPTS` in the profile, not hardcoded `#SBATCH` in `slurm/*.slurm`.

## Runtime artifacts (not in git)

Initial conditions and simulation output are **generated on scratch** at job time. They are in `.gitignore` and must never be committed:

- ICs: `${HARNESS_DIR}/ics_*`, `ic_grafic/`, zoom `level_*`
- Output: `${RUN_DIR}/output_*`, `dmo_gpu_<jobid>/`, `profiles_<jobid>/`, `run.log`, plots, nsys/ncu traces

After `git clone`, run a case to create ICs/output on scratch. Do not rsync or copy output trees into the repo checkout.

## Cross-cluster drift

| Setting | Stellar | Marlowe |
| --- | --- | --- |
| `GPU_MAKEFILE` | `Makefile.a100` | `Makefile.h100` |
| `GPU_CUDA_ARCH` | `sm_80` | `sm_90` |
| `GPU_NPRE` default | 4 | 8 |
| `ot-amr` levelmax | 8 | 10 |
| `ot-amr` wall time | 5 min | 2 h |

Do not copy namelists or job overrides blindly between clusters.

## NVHPC / link errors

Load the same NVHPC module the r3d/nvomp libraries were built with. Mismatch → `libr3d.a` / `__fd_sincos_1` link failures. See mini-ramses-dev debug-playbook #4.

## Deprecated

- `sync_from_stellar.sh` — replaced by `git pull` in `$HARNESS_DIR`
- Flat `~/hackathon` without `CLUSTER=` — use profile + `bin/hackathon-env.sh`

## Verify after deploy

```bash
bin/doctor.sh
./submit_profiles.sh test
./submit_profiles.sh mhd-turb    # Stellar (FFTW)
./submit_profiles.sh ot-amr      # Marlowe (longer AMR defaults)
```

Check fresh `run.log`: MHD cases need `emag > 0` at step 1.
