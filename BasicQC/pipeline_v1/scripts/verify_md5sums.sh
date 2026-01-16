#!/bin/bash

# SLURM directives (if required when submitting this as an individual job script)
#SBATCH --job-name=md5sums
#SBATCH --mem=5G
#SBATCH --partition=genD
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

# Check if correct number of arguments is provided
if [[ $# -ne 3 ]]; then
  echo "Usage: $0 <BASEPATH> <WORKDIR> <FASTQ_LIST>"
  exit 1
fi

# Read arguments from the main script or command line
BASEPATH="$1"
WORKDIR="$2"
FASTQ_LIST="$3"

# Find the MD5 checksum file
MD5_SUM_FILE=$(find "$BASEPATH" -name "*_md5s.txt" -print -quit)

if [[ -z $MD5_SUM_FILE ]]; then
  echo "Error: No MD5 checksum file found in $BASEPATH."
  exit 1
fi

# Verify MD5 checksums
echo "Starting MD5 checksum verification..."
cd "$BASEPATH"
if ! md5sum -c "$MD5_SUM_FILE" > "$WORKDIR/md5_check.log" 2>&1; then
  echo "Error: Some files failed MD5 verification. Check 'md5_check.log' for details."

  # Extract failed files
  failed_files=$(grep -v 'OK$' "$WORKDIR/md5_check.log" | awk -F: '{print $1}')

  # Print and log failed files
  echo "Failed files:"
  echo "$failed_files"
  echo "$failed_files" > "$WORKDIR/failed_files.log"

  # Filter out failed files from the FASTQ list
  cd "$WORKDIR"
  grep -Fxv -f <(echo "$failed_files") "$FASTQ_LIST" > fastq_list_filtered.txt
  mv fastq_list_filtered.txt "$FASTQ_LIST"
else
  echo "All files passed MD5 verification."
fi