#!/bin/bash

masses=(50 75 100 125 150 175 200 225 250)
sample=WZR_012j_NLO_WToLNu
script_dir=$(cd "$(dirname "$0")" && pwd)

postfix=(_run_card.dat _customizecards.dat _proc_card.dat _extramodels.dat _madspin_card.dat)

echo ${masses[*]}

for mass in ${masses[*]}; do
    echo generating cards for M = $mass GeV

    width=$(awk -v mass="$mass" 'BEGIN {printf "%.6f", 0.01 * mass}')
    target=${sample}_M${mass}

    mkdir -p "${script_dir}/${target}"

    for ((i=0;i<${#postfix[@]};i+=1)); do
        sed -e "s/<MASS>/${mass}/g" -e "s/<WIDTH>/${width}/g" \
            "${script_dir}/${sample}${postfix[$i]}" > "${script_dir}/${target}/${target}${postfix[$i]}"
    done
done
