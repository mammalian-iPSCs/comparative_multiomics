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

# Split using colon as delimiter
alias="${REFGENIE_ALIAS%%:*}"
tag="${REFGENIE_ALIAS#*:}"

# get refgenie assets
GENOME_FASTA=$(refgenie seek $alias/fasta:$tag)


GENOME_GTF="$(refgenie seek $alias/toga_gtf)/geneAnnotation.gtf.gz"

echo "checking if the gtf and fasta match"
gtf_choice=$(bash /home/groups/compgen/lwange/Cryozoo_data/RNA-seq/scripts/check_fasta_gtf_match.sh $alias)

if [ "$gtf_choice" == "gtf1" ]; then
  echo "Proceeding with $GENOME_GTF"
elif [ "$gtf_choice" == "gtf2" ]; then
  echo "Proceeding with modified GTF"
  MODIFIED_GTF="$OUTPUT_DIRECTORY/${alias}_modified.gtf.gz"
  zcat "$GENOME_GTF" | sed -E 's/^(\S+)/\1.1/' | gzip > "$MODIFIED_GTF"
  GENOME_GTF="$MODIFIED_GTF"
else
  echo "Error: No match between fasta and gtf file found!"
  exit 1
fi

ADDITIONAL_FASTA=$(refgenie seek ercc/fasta) # hardcoded for now, if other sequences need to be added in the future adapt this


# Check if NF_OPTIONS_PARSED is not empty and set the options accordingly
if [ -n "$NF_OPTIONS_PARSED" ]; then
    NF_OPTIONS_PARSED=",$NF_OPTIONS_PARSED"
fi

if refgenie seek $alias/star_index:$tag; then
    # If the gencode_gtf asset exists, use it
    STAR_INDEX="$(refgenie seek $alias/star_index:$tag)"
    params=$(cat <<EOF
{
    "input": "$OUTPUT_DIRECTORY/pipeline_info.csv",
    "outdir": "$OUTPUT_DIRECTORY/map_2_${alias}",
    "multiqc_title": "map_2_${alias}",
    "fasta": "$GENOME_FASTA",
    "gtf": "$GENOME_GTF",
    "star_index":"$STAR_INDEX",
    "additional_fasta":"$ADDITIONAL_FASTA",
    "save_reference": true,
    "gencode": false $NF_OPTIONS_PARSED
}
EOF
)
else
    
params=$(cat <<EOF
{
    "input": "$OUTPUT_DIRECTORY/pipeline_info.csv",
    "outdir": "$OUTPUT_DIRECTORY/map_2_${REFGENIE_ALIAS}",
    "multiqc_title": "map_2_${REFGENIE_ALIAS}",
    "fasta": "$MODIFIED_FASTA",
    "gtf": "$GENOME_GTF",
    "save_reference": true,
    "additional_fasta":"$ADDITIONAL_FASTA",
    "gencode": false $NF_OPTIONS_PARSED
}
EOF
)

fi


# Write the parameters to a JSON file
echo "$params" > $OUTPUT_DIRECTORY/nf_core_params.json