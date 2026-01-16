#!/bin/bash

#SBATCH --job-name=run_multiqc          # Job name
#SBATCH --output=multiqc_%j.out    # Standard output log
#SBATCH --error=multiqc_%j.err     # Standard error log
#SBATCH --partition=genD               # Partition
#SBATCH --ntasks=1                     # Number of tasks
#SBATCH --cpus-per-task=5              # Number of CPUs
#SBATCH --mem=16G                      # Memory allocation

# Define required variables
WORKDIR="$1"         
BASEDIR=$(dirname "$WORKDIR")
PROJECT=$(basename "$WORKDIR")

echo "Running MultiQC for $PROJECT"
# Run MultiQC with FastQC, FastQScreen, and custom modules
multiqc "$WORKDIR" \
    --module fastqc \
    --module fastq_screen \
    --outdir "$WORKDIR" \
    --force \
    -i "$PROJECT" \
    --sample-names ${BASEDIR}/inputs/${PROJECT}.report_names.tsv\

# Optional: Rename the output file with a timestamp
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
echo "MultiQC report successfully generated in: ${WORKDIR}/${PROJECT}_multiqc_report.html"