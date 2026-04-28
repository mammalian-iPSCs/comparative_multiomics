#!/bin/bash
# Input file with paths and aliases
input_file="gtf_list2.csv"
assets="star_index"

# Loop through each line in the input file
while IFS=',' read -r alias gtf; do
    # Submit a Slurm job
    sbatch --job-name="refgenie_add_asset_$alias" \
           --output="logs/add_asset_${alias}_%j.out" \
           --error="logs/add_asset_${alias}_%j.err" \
           Add_refgenie_asset.sh "$alias" "$assets" 

    echo "Submitted job for asset $assets ($alias)"
done < "$input_file"