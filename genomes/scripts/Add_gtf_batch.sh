#!/bin/bash
# Input file with paths and aliases
input_file="gtf_list.csv"

# Loop through each line in the input file
while IFS=',' read -r alias gtf; do
    # Submit a Slurm job
    sbatch --job-name="refgenie_add_gtf_$alias" \
           --output="logs/add_gtf_${alias}_%j.out" \
           --error="logs/add_gtf_${alias}_%j.err" \
           Add_refgenie_asset.sh "$alias" "toga_gtf" "$gtf" 

    echo "Submitted job for $alias ($gtf)"
done < "$input_file"