#!/bin/bash

input_file="species_ids2.txt"

while IFS=$'\t' read -r species accession; do
    species_clean=${species// /_}  # Replace spaces with underscores for filenames
    job_name="download_${species_clean}_${accession}"

    sbatch --job-name="$job_name" --output="${species_clean}_${accession}.out" --time=2:00:00 --mem=4G --wrap="datasets download genome accession $accession --filename ${species_clean}_${accession}.zip"

    echo "Submitted job for $species ($accession) with job name: $job_name"
done < "$input_file"