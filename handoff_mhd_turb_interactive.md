# Agent handoff: mhd-turb on Stellar (interactive GPU)

## Context — do NOT work on debug-cosmo

- **debug-cosmo is shelved.** Both GPU and CPU AMR show pathological behavior (dt collapse / deeper issue). **rteyssie is handling this.**
- Prior `debug` branch work (revert `10179cbe`, E1 `multipole_leaf` floor `b3510b20`) — leave unless rteyssie directs otherwise.

## Your task

Run and debug **mhd-turb** (driven MHD turbulence, 64³ unigrid, GPU MHD+TURB) on **Stellar** using **interactive GPU** (`~/use`). Avoid batch Slurm unless the user asks.

**Pass criteria (minimum):**

- Build completes (NVHPC, `TURB=1`, FFTW linked)
- ICs staged; **`emag > 0` at step 1** in fresh `run.log`
- Run completes or hits user cap without illegal memory / immediate abort
- Do not assume success from stale logs

---

## Path cheat sheet (read this first)

Four different paths are often confused. **Harness git = `hackathon-repo`; run outputs = legacy scratch `hackathon/`.**

| Role | Mac | Stellar login | Stellar compute |
|------|-----|---------------|-----------------|
| Harness git (`HARNESS_DIR`) | `~/ramses-development/mini-ramses-hackathon` | `/scratch/gpfs/moseley/hackathon-repo` | same (GPFS) |
| Legacy harness sync | — | `~/hackathon` (scripts only, may lag git) | — |
| Run outputs / scratch | — | `/scratch/gpfs/moseley/hackathon/...` | same |
| mini-ramses-dev | `~/ramses-development/mini-ramses-dev` | `~/mini-ramses-dev` | same |

**Always `git pull` in `$HARNESS_DIR` (`/scratch/gpfs/moseley/hackathon-repo`), NOT `~/hackathon`.** Plot scripts, namelists, and Makefiles live in the git checkout. The home copy is a stale rsync snapshot and must not be edited or pulled.

```bash
export HARNESS_DIR=/scratch/gpfs/moseley/hackathon-repo
export RUN_DIR=/scratch/gpfs/moseley/hackathon   # simulation workdirs only
cd "$HARNESS_DIR" && git fetch && git checkout new_branch && git pull --ff-only
```

**Scratch-only Slurm scripts:** ad-hoc jobs under `/scratch/gpfs/moseley/hackathon/` (e.g. `run_mhd_turb_l8.slurm`) may hardcode `~/hackathon` or the legacy scratch harness path. Before submitting, point `HARNESS_DIR` at `hackathon-repo` and invoke scripts from `$HARNESS_DIR/scripts/` (or fix the scratch copy manually on Stellar).

---

## Repos and branches

| Repo | Cluster path | Branch |
|------|--------------|--------|
| mini-ramses-dev | `~/mini-ramses-dev` | **`gpu_turb`** |
| mini-ramses-hackathon | `/scratch/gpfs/moseley/hackathon-repo` | **`new_branch`** or `main` |

- Harness GitHub: https://github.com/ermoseley/mini-ramses-hackathon
- Read: `handoff.md`, `AGENTS.md`, `CLUSTER.md`

---

## Login-node setup

    export CLUSTER=stellar
    export HARNESS_DIR=/scratch/gpfs/moseley/hackathon-repo
    export RUN_DIR=/scratch/gpfs/moseley/hackathon
    export MINIRAM=~/mini-ramses-dev

    cd $HARNESS_DIR
    git fetch && git checkout new_branch && git pull --ff-only
    bin/doctor.sh

    cd $MINIRAM
    git fetch && git checkout gpu_turb && git pull --ff-only

---

## Interactive GPU session

    ~/use alloc
    ~/use run bash -lc '...commands below...'
    ~/use release

Inside `~/use run bash -lc '...'`:

    export CLUSTER=stellar
    source /scratch/gpfs/moseley/hackathon-repo/bin/hackathon-env.sh
    module load nvhpc/25.5
    unset NVCOMPILER_TERM
    export NVHPC_CUDA_HOME=/opt/nvidia/hpc_sdk/Linux_x86_64/25.5/cuda/12.9
    export NVHPC_MATH_LIB=/opt/nvidia/hpc_sdk/Linux_x86_64/25.5/math_libs/lib64

    cd ~/mini-ramses-dev/bin
    make -f $HARNESS_DIR/makefiles/Makefile.a100 clean
    make -f $HARNESS_DIR/makefiles/Makefile.a100 \
      COMPILER=NVHPC CUDA_ARCH=sm_80 DEBUG=0 NHILBERT=1 \
      HYDRO=1 MHD=1 TURB=1 GRAV=0 NPSCAL=0 NPRE=4 NDIM=3 ramses
    cp -f ramses3d ramses3d.mhd.turb

    WORK=/scratch/gpfs/moseley/hackathon/mhd_turb_use_debug
    mkdir -p $WORK && cd $WORK
    source $HARNESS_DIR/hackathon_common.sh
    hackathon_ensure_mhd_turb_ics 6
    hackathon_stage_dmo_run_nml $HARNESS_DIR/namelists/mhd_turb.nml input.nml

    ldd ~/mini-ramses-dev/bin/ramses3d.mhd.turb | grep -E "25.5|cudafor"
    ~/mini-ramses-dev/bin/ramses3d.mhd.turb input.nml 2>&1 | tee run.log

**Build notes:**

- Serial `make` only (no `-j`)
- `TURB=1` needs FFTW — harness loads `fftw/nvhpc-21.5/3.3.9` via `hackathon_load_fftw`
- Never combine `NPRE=4` + `FASTMATH=1` on GPU
- Rebuild on GPU compute (`~/use run`), not login node, if binary misbehaves

---

## mhd-turb case summary

| Item | Value |
|------|-------|
| Namelist | `namelists/mhd_turb.nml` |
| Grid | 64³ unigrid (`levelmin=levelmax=6`) |
| Physics | Periodic, HLLD, uniform IC + **Bz=4**, driven turbulence |
| Binary | `ramses3d.mhd.turb` (`HYDRO=1 MHD=1 TURB=1`, `GRAV=0`, NPRE=4) |
| ICs | `$HARNESS_DIR/ics_mhd_turb/ic_mhd_turb_6_3d` (auto-generated) |
| Outputs | `tend=0.5`, `delta_tout=0.25` |

---

## Batch fallback (only if user approves)

    cd $HARNESS_DIR
    export MINIRAM=~/mini-ramses-dev
    BUILD_BINARIES=1 ./submit_profiles.sh mhd-turb

---

## Debugging checklist

1. Obsidian: [[mini-ramses — debug-playbook]]
2. `unset NVCOMPILER_TERM` after module load (false SIGILL)
3. Run from directory containing `ic_grafic` symlink (harness staging)
4. Verify `emag > 0` step 1; grep `Run completed` in fresh `run.log`
5. Never commit ICs or `output_*` to harness git

---

## SSH from Mac

    ~/hackathon/stellar_login.sh
    ~/hackathon/stellar_remote.sh 'hostname; squeue -u $USER'
