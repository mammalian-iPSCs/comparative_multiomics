#!/bin/bash
#SBATCH --job-name=refgenie_build   # Job name
#SBATCH --output=refgenie_build_%j.out  # Standard output log (with job ID)
#SBATCH --error=refgenie_build_%j.err   # Standard error log (with job ID)
#SBATCH --ntasks=1                 # Number of tasks (typically 1 for bash scripts)
#SBATCH --cpus-per-task=4          # Number of CPU cores to use
#SBATCH --mem=30G                   # Memory allocation (adjust as needed)
#SBATCH --partition=genD       # Partition to use (adjust to your cluster's config)

# Enable strict error checking
set -euo pipefail

# Input arguments
# Resolve the path if it contains wildcards
fasta=$(ls $1)
alias=$2

# Use specified number of CPUs for gzip or derived from SLURM
threads=${SLURM_CPUS_PER_TASK:-1}  # Default to 1 if not set

# Check if the input FASTA file is gzipped
if file "$fasta" | grep -q 'gzip compressed'; then
    echo "$fasta is already gzipped."
    fasta_gz="$fasta"
    gzip=true
else
    echo "$fasta is not gzipped. Compressing with $threads threads..."
    gzip=false
    gzip -c "$fasta" > "${fasta}.gz" & 
    gzip_pid=$!
    fasta_gz="${fasta}.gz"
fi

# Load required modules
module load SAMtools                # Load SAMtools for refgenie dependencies

# Check existing genomes and assets in refgenie
echo "Checking existing genomes and assets in refgenie..."
refgenie list

if [ "$gzip" != true ]; then
    # Wait for gzip to finish
    wait "$gzip_pid"
fi


# Run refgenie build with the compressed fasta file
echo "Building refgenie asset for alias: $alias"
refgenie build "$alias/fasta" --files fasta="${fasta_gz}" -R

# Check if the asset has been added correctly to refgenie
echo "Check if the asset has been added correctly to refgenie..."
refgenie list

echo "All done!"