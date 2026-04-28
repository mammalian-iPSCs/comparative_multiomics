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
STAR_INDEX=$(refgenie seek $REFGENIE_ALIAS/star_index)
ADDITIONAL_FASTA=$(refgenie seek ercc/fasta) # hardcoded for now, if other sequences need to be added in the future adapt this


# Check if NF_OPTIONS_PARSED is not empty and set the options accordingly
if [ -n "$NF_OPTIONS_PARSED" ]; then
    NF_OPTIONS_PARSED=",$NF_OPTIONS_PARSED"
fi

params=$(cat <<EOF
{
    "input": "$OUTPUT_DIRECTORY/pipeline_info.csv",
    "outdir": "$OUTPUT_DIRECTORY/map_2_${REFGENIE_ALIAS}",
    "multiqc_title": "map_2_${REFGENIE_ALIAS}",
    "fasta": "$GENOME_FASTA",
    "gtf": "$GENOME_GTF",
    "star_index":"$STAR_INDEX",
    "additional_fasta":"$ADDITIONAL_FASTA",
    "gencode": false $NF_OPTIONS_PARSED
}
EOF
)


# Write the parameters to a JSON file
echo "$params" > $OUTPUT_DIRECTORY/nf_core_params.json