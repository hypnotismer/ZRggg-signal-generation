# WZR Summer24 signal production

Produce 2024 signal samples for `pp → W± ZR`, with `W → eν/μν` and `ZR → ggg`, at 13.6 TeV. The workflow uses prebuilt Run 3 gridpacks and runs GEN-SIM, digitisation and HLT, reconstruction, and MiniAODv6 on HTCondor.

Supported ZR masses are **50, 75, 100, 125, 150, 175, 200, 225 and 250 GeV**. MadGraph cards are provided in `cards/`; the shared Pythia fragment configures the three-gluon decay and FxFx merging.

## Usage

Run in a CMS-enabled CERN environment with HTCondor, a CMS grid certificate, and access to the gridpacks referenced by the shared fragment, IHEP EOS, and CERN EOS.

Create the CMS proxy from the repository directory:

```bash
./x509up-gen
```

Submit jobs using:

```bash
./submit_summer24.sh MASS NEVENTS SEED [NJOBS]
```

- `MASS`: ZR mass in GeV.
- `NEVENTS`: input generation events per job; fewer events may remain after matching/filtering.
- `SEED`: first job seed.
- `NJOBS`: number of jobs, defaulting to 1. Seeds increase consecutively from `SEED`.

For example, submit one 100 GeV job with 100 input events:

```bash
./submit_summer24.sh 100 100 1
```

Or submit 100 jobs with 100 input events each, using seeds 1–100:

```bash
./submit_summer24.sh 100 100 1 100
condor_q -nobatch "$USER"
```

Use a new seed range for additional jobs at the same mass. Each job requests 4 CPUs, 10 GB memory and 30 GB scratch in the `nextweek` queue. Set `WZR_THREADS` before submission to change the CPU/thread count.

MiniAOD files are uploaded to:

```text
root://cceos.ihep.ac.cn:1094//store/user/zkou/MiniAODstore/V0/2024/MC/WZR_012j_NLO_WToLNu_ZRTo3Glu_M-<MASS>_13p6TeV-pythia8/<SEED>.root
```

Set `WZR_OUTPUT_ROOT` to change the output root to a subdirectory of `/store/user/zkou/MiniAODstore`.

Submission files are kept under `jobs/`. The submit command prints the CERN EOS log directory, where the worker uploads `logs.tar.gz`. If an IHEP upload fails, the worker saves the MiniAOD file in that log directory's `fallback/` subdirectory.
