#!/usr/bin/env bash
set -euo pipefail

[[ $# == 8 ]] || { echo "Usage: $0 MASS EVENTS THREADS SEED GRIDPACK_LFN OUTPUT_ROOT EOS_LOG_DIR JOB_ID" >&2; exit 2; }
mass=$1; events=$2; threads=$3; seed=$4; gridpack_lfn=$5; output_root=$6; logdir=$7; job_id=$8
for value in "$mass" "$events" "$threads" "$seed"; do
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || { echo "Mass, events, threads and seed must be positive integers" >&2; exit 2; }
done
[[ "$gridpack_lfn" == /eos/cms/store/group/phys_exotica/Boosted_X_to_3gluons/gridpacks/run3/*tarball.tar.xz ]] || { echo "Unexpected gridpack path" >&2; exit 2; }
[[ "$output_root" == /store/user/zkou/MiniAODstore || "$output_root" == /store/user/zkou/MiniAODstore/* ]] || { echo "Expected IHEP MiniAODstore output root" >&2; exit 2; }
[[ -n "${_CONDOR_SCRATCH_DIR:-}" ]] || { echo "This script runs on a Condor worker" >&2; exit 2; }
[[ "$logdir" == /eos/user/z/zkou/xggg/logs/generation_2024/* && "$job_id" =~ ^[0-9]+\.[0-9]+$ ]] || exit 2
# Run the payload as a child so its log descriptors are closed before upload.
if [[ ${WZR_LOG_CHILD:-0} != 1 ]]; then
    export WZR_LOG_CHILD=1
    set +e
    bash "$0" "$@" > "${_CONDOR_SCRATCH_DIR}/worker.out" 2> "${_CONDOR_SCRATCH_DIR}/worker.err"
    status=$?
    set -e
    printf '%s\n' "$status" > "${_CONDOR_SCRATCH_DIR}/exit_status.txt"
    printf 'mass=%s\nseed=%s\njob_id=%s\n' "$mass" "$seed" "$job_id" > "${_CONDOR_SCRATCH_DIR}/job_info.txt"
    source /cvmfs/cms.cern.ch/cmsset_default.sh
    cd "${_CONDOR_SCRATCH_DIR}"
    # cmsDriver writes the full premix library into DIGIHLT_cfg.py (~80 MB).
    # The other stage configs stay in the log tarball.
    rm -f work/DIGIHLT_cfg.py
    files=(worker.out worker.err exit_status.txt job_info.txt)
    shopt -s nullglob
    files+=(work/*.log work/*_cfg.py)
    tar -czf logs.tar.gz "${files[@]}"
    uploaded=0
    for attempt in 1 2 3; do
        if xrdfs root://eosuser.cern.ch mkdir -p "$logdir" && xrdcp -f logs.tar.gz "root://eosuser.cern.ch/${logdir}/logs.tar.gz"; then
            uploaded=1
            break
        fi
        sleep 5
    done
    if [[ "$uploaded" != 1 ]]; then
        echo "Shared log upload failed; preserving production exit status ${status}" >&2
    fi
    exit "$status"
fi
source /cvmfs/cms.cern.ch/cmsset_default.sh
export SCRAM_ARCH=el9_amd64_gcc12
# Match the Summer24 WtoLNu McM releases; retain EL9 for the EL9 WZR gridpack.
gen_release=CMSSW_14_0_19
dr_release=CMSSW_14_0_21
mini_release=CMSSW_15_0_2
gt=140X_mcRun3_2024_realistic_v26
era=Run3_2024
work="${_CONDOR_SCRATCH_DIR}/work"
mkdir -p "$work" "${_CONDOR_SCRATCH_DIR}/fallback"
cd "$work"

# Held jobs are released after the MiniAOD is already on IHEP. Skip the
# production instead of rerunning and then failing on the existing file.
eos_url="root://cceos.ihep.ac.cn:1094"
sample="WZR_012j_NLO_WToLNu_ZRTo3Glu_M-${mass}_13p6TeV-pythia8"
dest_dir="${output_root}/V0/2024/MC/${sample}"
dest="${dest_dir}/${seed}.root"
if xrdfs "${eos_url}" stat "${dest}" >/dev/null 2>&1; then
    echo "MINIv6 already stored, skipping production: ${eos_url}/${dest}"
    exit 0
fi

# Stage the gridpack before cmsRun; the generic LHE wrapper untars it after changing directory.
xrdcp "root://eoscms.cern.ch/${gridpack_lfn}" "${work}/gridpack.tar.xz"
[[ -s "${work}/gridpack.tar.xz" ]] || { echo "Gridpack staging failed" >&2; exit 1; }

# As in the 2018 workflow, replace the mass token in the shared fragment.
# The selected gridpack is staged in scratch, so use that local path for cmsRun.
fragment="fragment_WZR_012j_NLO_WToLNu_ZRTo3Glu_M-${mass}_13p6TeV-pythia8.py"
python3 - "${_CONDOR_SCRATCH_DIR}/fragment.py" "$fragment" "$gridpack_lfn" "$work/gridpack.tar.xz" "$mass" "$events" <<'PY_FRAGMENT'
from pathlib import Path
import re, sys
source=Path(sys.argv[1]).read_text()
if source.count('__ZR_MASS__') != 2:
    raise SystemExit('Fragment must use __ZR_MASS__ in both gridpack path and Pythia mass')
source=source.replace('__ZR_MASS__',sys.argv[5])
if source.count(sys.argv[3]) != 1:
    raise SystemExit('Selected gridpack does not match the fragment for this mass')
source=source.replace(sys.argv[3],sys.argv[4])
source,count=re.subn(r'nEvents\s*=\s*cms\.untracked\.uint32\(\s*\d+\s*\)',
                     f'nEvents=cms.untracked.uint32({sys.argv[6]})',source,count=1)
if count != 1: raise SystemExit('Could not set ExternalLHEProducer nEvents')
Path(sys.argv[2]).write_text(source)
PY_FRAGMENT
scram project CMSSW "$gen_release"
mkdir -p "${gen_release}/src/Configuration/GenProduction/python"
cp "$fragment" "${gen_release}/src/Configuration/GenProduction/python/"
cd "${gen_release}/src"
eval "$(scram runtime -sh)"
scram b -j "$threads"
cd "$work"

# Use the same complete Summer24 PREMIX dataset as the central WtoLNu request.
IFS= read -r premix_dataset < "${_CONDOR_SCRATCH_DIR}/premix_dataset.txt"
[[ "$premix_dataset" == /Neutrino_E-10_gun/RunIIISummer24PrePremix-Premixlib2024_140X_mcRun3_2024_realistic_v26-v1/PREMIX ]] || {
    echo "Unexpected Summer24 premix dataset: $premix_dataset" >&2
    exit 1
}

# Give each job and CMSSW module independent seeds, including ExternalLHEProducer.
set_seeds() {
    local cfg=$1 stage=$2
    cat >> "$cfg" <<PY
import hashlib as _wzr_hashlib
if '${stage}' == 'GENSIM':
    process.source.firstLuminosityBlock = cms.untracked.uint32(${seed})
    process.source.numberEventsInLuminosityBlock = cms.untracked.uint32(${events})
if hasattr(process, 'RandomNumberGeneratorService'):
    for _wzr_name in process.RandomNumberGeneratorService.parameterNames_():
        _wzr_module = getattr(process.RandomNumberGeneratorService, _wzr_name)
        if hasattr(_wzr_module, 'initialSeed'):
            _wzr_key = '${mass}:${seed}:${stage}:' + _wzr_name
            _wzr_value = 1 + int.from_bytes(_wzr_hashlib.sha256(_wzr_key.encode()).digest()[:4], 'big') % 900000000
            _wzr_module.initialSeed.setValue(_wzr_value)
PY
}
run_step() {
    local stage=$1
    shift
    echo "===== ${stage} started $(date -u) ====="
    cmsDriver.py "$@" --conditions "$gt" --geometry DB:Extended --era "$era" \
        --customise Configuration/DataProcessing/Utils.addMonitoring \
        --mc --nThreads "$threads" -n "$events" --python_filename "${stage}_cfg.py" --no_exec \
        > "${stage}_driver.log" 2>&1 || { tail -c 4000 "${stage}_driver.log" >&2; return 1; }
    if [[ "$stage" == DIGIHLT ]]; then
        # The full DBS query prints a very large file list; the generated
        # configuration still retains the complete library.
        rm -f "${stage}_driver.log"
    fi
    set_seeds "${stage}_cfg.py" "$stage"
    cmsRun "${stage}_cfg.py" > "${stage}.log" 2>&1 || { tail -100 "${stage}.log" >&2; return 1; }
    echo "===== ${stage} finished $(date -u) ====="
}

run_step GENSIM "Configuration/GenProduction/python/${fragment}" \
    --step LHE,GEN,SIM --eventcontent RAWSIM,LHE --datatier GEN-SIM,LHE \
    --beamspot DBrealistic --fileout file:GENSIM.root
scram project CMSSW "$dr_release"
cd "${dr_release}/src"
eval "$(scram runtime -sh)"
cd "$work"
run_step DIGIHLT \
    --step DIGI,DATAMIX,L1,DIGI2RAW,HLT:2024v14 --procModifiers premix_stage2 \
    --datamix PreMix --pileup_input "dbs:${premix_dataset}" \
    --eventcontent PREMIXRAW --datatier GEN-SIM-RAW \
    --filein file:GENSIM.root --fileout file:DIGIHLT.root
rm -f GENSIM.root gridpack.tar.xz
run_step RECO \
    --step RAW2DIGI,L1Reco,RECO,RECOSIM --eventcontent AODSIM --datatier AODSIM \
    --filein file:DIGIHLT.root --fileout file:AOD.root
rm -f DIGIHLT.root
# Match the central Summer24 MiniAODv6 request's PAT release, GT, and era.
scram project CMSSW "$mini_release"
cd "${mini_release}/src"
eval "$(scram runtime -sh)"
cd "$work"
gt=150X_mcRun3_2024_realistic_v2
era=Run3_2024
run_step MINIAOD \
    --step PAT --eventcontent MINIAODSIM1 --datatier MINIAODSIM \
    --filein file:AOD.root --fileout file:MINIAOD.root
[[ -s MINIAOD.root ]] || { echo "MiniAOD output missing" >&2; exit 1; }

# Same IHEP EOS upload as the 2018 MiniAOD workflow.
xrdfs "${eos_url}" mkdir -p "${dest_dir}"
if xrdfs "${eos_url}" stat "${dest}" >/dev/null 2>&1; then
    echo "Destination already exists: ${eos_url}/${dest}" >&2
    exit 1
fi
if ! xrdcp MINIAOD.root "${eos_url}/${dest}"; then
    echo "IHEP EOS upload failed; saving MiniAOD on CERN EOS" >&2
    xrdfs root://eosuser.cern.ch mkdir -p "${logdir}/fallback"
    xrdcp MINIAOD.root "root://eosuser.cern.ch/${logdir}/fallback/MINIv6_${mass}_${seed}.root"
    exit 1
fi
echo "MINIv6: ${eos_url}/${dest}"
