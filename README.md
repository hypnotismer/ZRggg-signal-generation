# WZR Summer24 private signal production

This directory produces the **signal sample** from existing Run 3 gridpacks. Gridpack generation is maintained separately in `Run3_gridpack_generation`.

## Summer24 chain

The processing choices follow the original McM scripts for `WtoLNu-2Jets_Bin-1J-PTLNu-100to200_TuneCP5_13p6TeV_amcatnloFXFX-pythia8`. Copies of those scripts are in `/afs/cern.ch/user/z/zkou/eos/xggg/WtoLNu_2Jets_1J_PTLNu100to200_McM_original/`.

| Stage | CMSSW | Conditions | Step |
| --- | --- | --- | --- |
| GEN-SIM | `CMSSW_14_0_19` | `140X_mcRun3_2024_realistic_v26` | `LHE,GEN,SIM` |
| Premix, HLT and RECO | `CMSSW_14_0_21` | `140X_mcRun3_2024_realistic_v26` | `DIGI,DATAMIX,L1,DIGI2RAW,HLT:2024v14`, then `RAW2DIGI,L1Reco,RECO,RECOSIM` |
| MiniAODv6 | `CMSSW_15_0_2` | `150X_mcRun3_2024_realistic_v2` | `PAT`, `MINIAODSIM1` |

All stages use `Run3_2024`, `DB:Extended`, and the monitoring customisation from the McM commands. The private WZR gridpack was built for EL9, so the Condor worker uses `el9_amd64_gcc12` and EL9 nodes; the McM jobs used EL8 with the same GCC and CMSSW releases. The central request also includes validation and DQM jobs, which are outside this GEN-to-MiniAOD chain.

The premix input is the complete Summer24 v26 dataset recorded in `premix_dataset.txt`:

`/Neutrino_E-10_gun/RunIIISummer24PrePremix-Premixlib2024_140X_mcRun3_2024_realistic_v26-v1/PREMIX`

The worker passes it directly as `--pileup_input dbs:/...`, following the original W+jets `get_setup` command. There is no private selection of a subset of files. The old `premix_files.txt` cache is not used. The 2018 `HIG-RunIISummer20UL18DIGIPremix-03567.patch` applies to the UL18 premix setup and is not used here.

## Fragment and gridpack

The shared fragment is `fragment_WZR_012j_NLO_WToLNu_ZRTo3Glu_M-*_13p6TeV-pythia8.py`. As in the 2018 workflow, it contains the `__ZR_MASS__` token. `submit_summer24.sh` selects the matching Run 3 gridpack for masses 50, 75, 100, 125, 150, 175, 200, 225 or 250 GeV. The worker stages that gridpack locally and substitutes its path and mass in the fragment. Each mass needs an existing gridpack from the separate generation workflow.

## Submit

From this directory, create the proxy with `./x509up-gen`, then submit a sample (arguments: `MASS NEVENTS SEED`):

```bash
./submit_summer24.sh 100 100 1
condor_q -nobatch "$USER"
```

The submit script validates `x509up`, writes the job description, and submits immediately. CMSSW processing takes place on the worker. Its default request is 4 CPUs, 10 GB memory, 30 GB scratch, and the `nextweek` queue. `WZR_THREADS` overrides the CPU/thread count. The complete DBS premix query can take time on the worker and produces a large generated DIGI/HLT configuration.

Output is uploaded to IHEP EOS under:

`root://cceos.ihep.ac.cn:1094//store/user/zkou/MiniAODstore/V0/2024/MC/WZR_012j_NLO_WToLNu_ZRTo3Glu_M-100_13p6TeV-pythia8/1.root`

Set `WZR_OUTPUT_ROOT` before submission to change the root directory under `/store/user/zkou/MiniAODstore`. Job files remain under `jobs/M100_S1/`. Workers upload `logs.tar.gz` directly via XRootD to `/eos/user/z/zkou/xggg/logs/generation_2024/<job directory>/`, overwriting the shared archive when another job finishes. Archives contain stdout, stderr, exit status, mass/seed/job identifiers, stage logs and generated configurations. Condor stdout/stderr use `/dev/null`; no Condor event log is written. Failed IHEP uploads save MiniAOD under the EOS log directory’s `fallback/`. Logs are uploaded when the worker exits; hard termination may prevent upload. A failed shared-log upload does not change the production exit status.

## Validation

`cmsDriver.py --no_exec` configuration generation succeeded for all four stages using the three McM CMSSW releases, including a DIGI/HLT configuration with the full DBS premix list. This checks configuration generation, not a complete new-event run.

The earlier real one-event and 100-event runs, plus the standard NanoAOD compatibility checks, are documented in `validation/miniv6/REPORT.md`. Those runs used `CMSSW_14_0_25` and `CMSSW_15_0_20`, before this McM alignment; their output files remain available for comparison but do not validate the newly aligned chain.
