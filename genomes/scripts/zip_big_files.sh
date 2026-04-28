#!/bin/bash
#SBATCH --job-name=gzip_big6a4cc495e
#SBATCH --output=gzip_big_%j.out
#SBATCH --error=gzip_big_%j.err
#SBATCH --cpus-per-task=30
#SBATCH --mem=8G

module load pigz
success=1
base="/scratch_isilon/groups/compgen/data/Illumina_CryoZoo/genomes/data/"

# Find all files >100M
for f in $(find "$base" -type f -size +100M); do
    # Skip files that are already gzipped
    if [[ "$f" == *.gz ]]; then
        echo "Skipping already gzipped file: $f"
        continue
    fi

    echo "Compressing $f ..."
    pigz -p $SLURM_CPUS_PER_TASK "$f"
    if [ $? -ne 0 ]; then
        echo "ERROR compressing $f"
        success=0
    fi
done

# Final message
if [ $success -eq 1 ]; then
    echo "$(date): All eligible files larger than 100M have been successfully compressed!"
else
    echo "$(date): Some files failed to compress."
fi
