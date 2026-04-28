#!/bin/bash
# Input file with paths and aliases
input_file="fasta_list2.csv"

# Loop through each line in the input file
# Loop through each line in the input file
while IFS=',' read -r fasta alias; do
    # Submit a Slurm job
    sbatch --job-name="refgenie_$alias" \
           --output="logs/${alias}_%j.out" \
           --error="logs/${alias}_%j.err" \
           Add_genomes.sh "$fasta" "$alias"

    echo "Submitted job for $alias ($fasta)"
done < "$input_file"