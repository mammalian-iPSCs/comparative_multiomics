#!/bin/bash
# update_genome_list.sh
source ~/.bashrc
conda activate genomes

README=../README.md

# Extract everything above a marker in the README
awk '/^<!-- GENOMES_START -->/ {exit} {print}' "$README" > README.tmp

# Add the new genome list section
{
  echo "<!-- GENOMES_START -->"
  echo "## Available Genomes"
  echo '```'
  refgenie list
  echo '```'
} >> README.tmp

# Replace the original README
mv README.tmp "$README"