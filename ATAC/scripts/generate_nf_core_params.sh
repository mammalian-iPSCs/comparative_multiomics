#!/bin/bash

# Description: This script generates the parameters file to run the nf-core rna-seq pipeline
# Usage: generate_nf_core_params.sh <selected_samples_file> <full_info_rds_file> <output_directory> <refgenie_alias> [nf_options]

# Check if the correct number of arguments is provided
source ~/.bashrc
conda activate basicQC
unset PYTHONPATH
if [ "$#" -lt 2 ]; then
    echo "Usage: $0 <OUTPUT_DIRECTORY> <REFGENIE_ALIAS> [NF_OPTIONS_PARSED]"
    exit 1
fi

# Arguments
OUTPUT_DIRECTORY=$1
REFGENIE_ALIAS=$2
NF_OPTIONS_PARSED=${3:-""}

# get refgenie assets
GENOME_FASTA=$(refgenie seek $REFGENIE_ALIAS/fasta)
GENOME_GTF=$(refgenie seek $REFGENIE_ALIAS/gencode_gtf)

MITO_NAME=$(comm -12 <(zcat $GENOME_GTF | grep "COX1" | awk '{print $1}' | sort -u) \
                      <(zcat $GENOME_GTF | grep "CYTB" | awk '{print $1}' | sort -u))

if [[ -n "$MITO_NAME" ]]; then
    echo "Mitochondrial chromosome identified based on CYTB and COX1: $MITO_NAME"
else
    echo "No common chromosome found for COX1 and CYTB"
fi


# Check if NF_OPTIONS_PARSED is not empty and set the options accordingly
if [ -n "$NF_OPTIONS_PARSED" ]; then
    NF_OPTIONS_PARSED=",$NF_OPTIONS_PARSED"
fi


#### Check these parameters
params=$(cat <<EOF
{
    "input": "$OUTPUT_DIRECTORY/pipeline_info.csv",
    "outdir": "$OUTPUT_DIRECTORY/map_2_${REFGENIE_ALIAS}",
    "multiqc_title": "map_2_${REFGENIE_ALIAS}",
    "fasta": "$GENOME_FASTA",
    "gtf": "$GENOME_GTF",
    "save_reference": true,
    "mito_name" : "$MITO_NAME", 
    "read_length": 150 $NF_OPTIONS_PARSED
}
EOF
)


# Write the parameters to a JSON file
echo "$params" > $OUTPUT_DIRECTORY/nf_core_params.json