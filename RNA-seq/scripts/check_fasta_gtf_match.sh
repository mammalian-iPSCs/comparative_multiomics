#!/bin/bash

# This script activates the "genomes" Conda environment.
# It is intended to be used as part of a workflow for checking 
# the match between FASTA and GTF files.
#
# Usage:
#   bash check_fasta_gtf_match.sh <refgenie_alias>
#
# Ensure that the "genomes" Conda environment is properly configured 
# before running this script.
source ~/.bashrc
conda activate genomes
alias=$1
silent=$2

fasta=$(refgenie seek $alias/fasta)
gtf="$(refgenie seek $alias/toga_gtf)/geneAnnotation.gtf.gz"
# Extract chromosome names from FASTA (remove '>')
grep '^>' $fasta | sed 's/^>//' | cut -f1 -d' ' | sort > $alias.fasta_chroms.txt
#sed 's/\.[0-9]*\b//' "$fasta" | grep '^>'| sed 's/^>//' | cut -f1 -d' ' | sort > $alias.fasta_chroms2.txt

# Extract chromosome names from gzipped GTF
zcat $gtf | awk '$1 !~ /^#/ {print $1}' | sort | uniq > $alias.gtf_chroms.txt
zcat $gtf | awk '$1 !~ /^#/ {print $1}' | sort | uniq | sed -E 's/^(\S+)/\1.1/' > $alias.gtf_chroms2.txt

# Find matching chromosome names
matches=$(comm -12 $alias.fasta_chroms.txt $alias.gtf_chroms.txt | wc -l)
matches2=$(comm -12 $alias.fasta_chroms.txt $alias.gtf_chroms2.txt | wc -l)

if [ -n "$silent" ]; then
  echo "fasta names:"
  head -50 $alias.fasta_chroms.txt
  echo "gtf names:"
  head -50 $alias.gtf_chroms.txt
  echo "Matches chromosome names (original): $matches"
  echo "Matches chromosome names (modified): $matches2"
  echo "Total number of sequences in FASTA: $(wc -l < $alias.fasta_chroms.txt)"
  echo "Total number of sequences in GTF: $(wc -l < $alias.gtf_chroms.txt)"
fi

# Clean up temporary files
#rm $alias.fasta_chroms.txt $alias.gtf_chroms.txt $alias.gtf_chroms2.txt

# Exit with error if fewer than 10 match
if [ "$matches" -ge 10 ] && [ "$matches" -ge "$matches2" ]; then
  echo "gtf1"
  exit 0
elif [ "$matches2" -ge 10 ]; then
  echo "gtf2"
  exit 0
else
  echo "none"
  exit 1
fi
