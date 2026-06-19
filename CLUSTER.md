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


## Marlowe SSH (ControlMaster)

Add to `~/.ssh/config` (mirror Stellar):

```
Host marlowe login.marlowe.stanford.edu
  HostName login.marlowe.stanford.edu
  User emoseley
  ControlMaster auto
  ControlPath ~/.ssh/sockets/cm-%r@%h:%p
  ControlPersist 8h
  ServerAliveInterval 60
  ServerAliveCountMax 3
```

Then: `bin/marlowe_login.sh` once, then `bin/marlowe_remote.sh '…'`.

Scratch harness: `/scratch/m000115/emoseley/hackathon-repo` (clone of this repo, branch `new_branch`) or `/scratch/m000115/hackathon`.


## Marlowe MHD Mach-10 workflow (128³ then 512³)

**Order:** interactive **128³** smoke on `preempt` before batch **512³** HLLD.

Scratch harness (preferred clone):

```bash
export CLUSTER=marlowe
export HARNESS_DIR=/scratch/m000115/emoseley/hackathon-repo
cd "${HARNESS_DIR}"
git pull
source bin/hackathon-env.sh
export MINIRAM=~/ramses-development/mini-ramses-dev   # or ~/mini-ramses-dev on cluster
export MINIRAM_EXPECTED_BRANCH=gpu_turb
export GPU_NPRE=4
```

### SSH (local Mac / agent)

See **Marlowe SSH (ControlMaster)** above. One-time auth:

```bash
cd "${HARNESS_DIR:-$HOME/ramses-development/mini-ramses-hackathon}"
bin/marlowe_login.sh
bin/marlowe_remote.sh 'hostname'
```

### 256³ interactive smoke (`preempt`)

Uses `mhd_turb_full_l8.nml`: `turb_T=0.1`, parabolic driving, **HLLD**, `turb_rms=200`. **Note:** after the `c_s=ρ=P=1` rescale (1 pc, `boxlen=1`, `eos_T2=34.25993294742506`), the old `beta=0.1` and Mach figures are stale — the empirical **M ≈ C√turb_rms** fit (**C≈1.658**, derived at the old `c_s≈0.19`) must be re-derived under the new sound speed. See `utils/py/plot_mach_turb_rms_theory.py` in mini-ramses-dev.

Allocate one H100 on the preempt partition (build on the GPU node if needed):

```bash
salloc --account=marlowe-m000115 --partition=preempt -G 1 --mem=80G --time=02:00:00
# on the compute node (run in-shell, do not sbatch from inside salloc):
cd /scratch/m000115/emoseley/hackathon-repo
source bin/hackathon-env.sh
export MINIRAM=~/ramses-development/mini-ramses-dev MINIRAM_EXPECTED_BRANCH=gpu_turb GPU_NPRE=4
hackathon_load_fftw
export MHD_TURB_BZ=0.7792435587233456
hackathon_ensure_mhd_turb_ics 8
export IC_DIR GPU_HYDRO=1 GPU_MHD=1 GPU_TURB=1 GPU_GRAV=0 BUILD_BINARIES=1
export NML="$(hackathon_nml mhd_turb_full_l8.nml)"
export BIN_GPU="${MINIRAM}/bin/ramses3d.mhd.turb" DMO_TEND=0.05 DMO_FOUTPUT=1000000 PROFILE=run
bash slurm/dmo_gpu.slurm
```

Pass criteria: `run.log` shows **`emag > 0` at step 1**, no CUDA OOM, sane timestep count for `tend=0.05`.

Alternative one-liner (login → GPU shell):

```bash
srun --account=marlowe-m000115 --partition=preempt -G 1 --mem=80G --time=02:00:00 --pty bash -l
```

## MHD turbulence run dirs (canonical namelists in `namelists/`)

| Case | Namelist | Notes |
| --- | --- | --- |
| 256³ HLLD | `mhd_turb_full_l8.nml` | Stellar reference (`turb_T=0.1`, `turb_rms=200`); `./submit_profiles.sh mhd-turb-l8-full` |
| 64³ base | `mhd_turb.nml` | `c_s=ρ=P=1` params (`turb_T=0.33`, `turb_rms=20`); `./submit_profiles.sh mhd-turb` |

Job workdirs land under `${RUN_DIR}/dmo_gpu_<jobid>/<case>/` unless you use a custom Slurm script in scratch (legacy Stellar: `/scratch/gpfs/moseley/hackathon/mhd_turb_l8_a200_beta01/`).

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
