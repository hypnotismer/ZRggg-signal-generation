#!/usr/bin/env bash
set -euo pipefail
if [[ $# != 3 && $# != 4 ]]; then
    echo "Usage: $0 MASS NEVENTS SEED [NJOBS]" >&2
    exit 2
fi
mass=$1; events=$2; seed=$3; njobs=${4:-1}
case "$mass" in 50|75|100|125|150|175|200|225|250) ;; *) echo "Unsupported mass: $mass" >&2; exit 2 ;; esac
for value in "$events" "$seed" "$njobs"; do
    [[ "$value" =~ ^[1-9][0-9]*$ ]] || { echo "NEVENTS, SEED and NJOBS must be positive integers" >&2; exit 2; }
done
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
[[ -s "${here}/premix_dataset.txt" ]] || { echo "Missing ${here}/premix_dataset.txt" >&2; exit 1; }
proxy_file="${here}/x509up"
[[ -f "$proxy_file" ]] || { echo "Missing $proxy_file; run ./x509up-gen from this directory" >&2; exit 1; }
proxy_lifetime=$(voms-proxy-info -file "$proxy_file" -timeleft 2>/dev/null) || { echo "Invalid CMS proxy: $proxy_file" >&2; exit 1; }
[[ -f "$proxy_file" && "$proxy_lifetime" =~ ^[0-9]+$ && "$proxy_lifetime" -gt 7200 ]] || {
    echo "CMS proxy must be valid for more than two hours; renew by running ./x509up-gen from this directory" >&2
    exit 1
}
threads=${WZR_THREADS:-4}
[[ "$threads" =~ ^[1-9][0-9]*$ ]] || { echo "WZR_THREADS must be a positive integer" >&2; exit 2; }
output_root=${WZR_OUTPUT_ROOT:-/store/user/zkou/MiniAODstore}
[[ "$output_root" == /store/user/zkou/MiniAODstore || "$output_root" == /store/user/zkou/MiniAODstore/* ]] || { echo "WZR_OUTPUT_ROOT must be under /store/user/zkou/MiniAODstore" >&2; exit 2; }
fragment_source="${here}/fragment_WZR_012j_NLO_WToLNu_ZRTo3Glu_M-*_13p6TeV-pythia8.py"
[[ -s "$fragment_source" ]] || { echo "Shared fragment missing: $fragment_source" >&2; exit 1; }
gridpack=$(python3 - "$fragment_source" "$mass" <<'PY_GRIDPACK'
from pathlib import Path
import re,sys
text=Path(sys.argv[1]).read_text()
match=re.search(r"args\s*=\s*cms\.vstring\(\s*'([^']+)'\s*\)",text)
if not match or match.group(1).count('__ZR_MASS__') != 1:
    raise SystemExit('Expected one mass token in fragment gridpack path')
print(match.group(1).replace('__ZR_MASS__',sys.argv[2]))
PY_GRIDPACK
)
[[ -s "$gridpack" ]] || { echo "Gridpack missing: $gridpack" >&2; exit 1; }
sample="WZR_012j_NLO_WToLNu_ZRTo3Glu_M-${mass}_13p6TeV-pythia8"
dest_dir="${output_root}/V0/2024/MC/${sample}"
export X509_USER_PROXY="$proxy_file"
xrdfs root://cceos.ihep.ac.cn:1094 mkdir -p "$dest_dir"
last_seed=$((seed + njobs - 1))
if [[ "$njobs" == 1 ]]; then
    jobdir="${here}/jobs/M${mass}_S${seed}"
else
    jobdir="${here}/jobs/M${mass}_S${seed}_N${njobs}"
fi
if ! mkdir -p "${here}/jobs" || ! mkdir -m 700 "$jobdir" 2>/dev/null; then
    echo "Job directory exists: ${jobdir}; inspect its status before resubmitting" >&2
    exit 1
fi
trap 'if [[ ! -f "${jobdir}/summer24.sub" ]]; then rmdir "$jobdir" 2>/dev/null || true; fi' EXIT
logdir="/eos/user/z/zkou/xggg/logs/generation_2024/$(basename "$jobdir")"
xrdfs root://eosuser.cern.ch mkdir -p "$logdir"
cp "${here}/premix_dataset.txt" "${jobdir}/premix_dataset.txt"
cp "$fragment_source" "${jobdir}/fragment.py"
# The schedd/access point cannot read the login node's /tmp proxy path.
install -m 600 "$proxy_file" "${jobdir}/x509up"
seq "$seed" "$last_seed" > "${jobdir}/seeds.txt"
cat > "${jobdir}/summer24.sub" <<JDL
universe = vanilla
executable = ${here}/run_summer24_worker.sh
arguments = ${mass} ${events} ${threads} \$(SEED) ${gridpack} ${output_root} ${logdir} \$(ClusterId).\$(ProcId)
initialdir = ${jobdir}
should_transfer_files = YES
when_to_transfer_output = ON_EXIT
transfer_input_files = ${jobdir}/fragment.py,${jobdir}/premix_dataset.txt
transfer_output_files = ""
x509userproxy = ${jobdir}/x509up
request_cpus = ${threads}
request_memory = 10000
request_disk = 30000000
requirements = (OpSysAndVer == "AlmaLinux9")
+ProjectName = "cms.org.cern"
+JobFlavour = "nextweek"
on_exit_hold = (ExitBySignal == True) || (ExitCode != 0)
output = /dev/null
error = /dev/null
queue SEED from ${jobdir}/seeds.txt
JDL
condor_submit "${jobdir}/summer24.sub"
echo "Job directory: ${jobdir}"
echo "Log directory: ${logdir}"
echo "Seeds: ${seed}..${last_seed} (${njobs} jobs, ${events} events each)"
echo "Expected MiniAODv6: root://cceos.ihep.ac.cn:1094/${dest_dir}/<seed>.root"
