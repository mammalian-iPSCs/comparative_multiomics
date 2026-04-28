#!/bin/bash

# Check if the correct number of arguments is provided
if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <selected_samples_file> <full_info_rds_file> <output_directory> <refgenie_alias> [nf_options]"
    exit 1
fi

# Arguments
SELECTED_SAMPLES_FILE=$1
FULL_INFO_RDS_FILE=$2
OUTPUT_DIRECTORY=$3
REFGENIE_ALIAS=$4
NF_OPTIONS=${5:-}

#SBATCH -n 1
#SBATCH -N 1
#SBATCH -c 1
#SBATCH -J $REFGENIE_ALIAS ## change to run name
#SBATCH -e %x.%J.err ## change to run name
#SBATCH -o %x.%J.out ## change to run name
#SBATCH --mem=100G
#SBATCH --partition "genD"

# Description: This script runs the nf-core RNA-seq pipeline for a selected set of samples.
# Usage: ./run_rna-seq_pipeline.sh <selected_samples_file> <full_info_rds_file> <output_directory> <refgenie_alias> [nf_options]

# Check if the correct number of arguments is provided
if [ "$#" -lt 4 ]; then
    echo "Usage: $0 <selected_samples_file> <full_info_rds_file> <output_directory> <refgenie_alias> [nf_options]"
    exit 1
fi

# Arguments
SELECTED_SAMPLES_FILE=$1
FULL_INFO_RDS_FILE=$2
OUTPUT_DIRECTORY=$3
REFGENIE_ALIAS=$4
NF_OPTIONS=${5:-}

mkdir -p $OUTPUT_DIRECTORY
# Parse NF_OPTIONS into an array
IFS=',' read -r -a NF_OPTIONS_ARRAY <<< "$NF_OPTIONS"
NF_OPTIONS_PARSED=""

# Iterate over the array and construct the options string
for option in "${NF_OPTIONS_ARRAY[@]}"; do
    key=$(echo $option | cut -d'=' -f1)
    value=$(echo $option | cut -d'=' -f2)
    if [[ "$value" == "true" || "$value" == "false" ]]; then
        NF_OPTIONS_PARSED+="\"$key\":$value,"
    else
        NF_OPTIONS_PARSED+="\"$key\":\"$value\","
    fi
done

# Convert the options string to a valid JSON obj
NF_OPTIONS_PARSED=$(echo "$NF_OPTIONS_PARSED" | sed 's/,$//')
echo $NF_OPTIONS_PARSED

# Step 1: Generate the nf-core sample info
module load R
echo "Generating nf-core sample info..."
Rscript /home/groups/compgen/lwange/isilon/data/Illumina_CryoZoo/RNA-seq/scripts/generate_sample_info.R $SELECTED_SAMPLES_FILE $FULL_INFO_RDS_FILE $OUTPUT_DIRECTORY

# Step 2: Generate the nf-core params file
echo "Generating nf-core params file..."
# Assuming you have a script or command to generate the params file, replace the following line with the actual command
bash /home/groups/compgen/lwange/isilon/data/Illumina_CryoZoo/RNA-seq/scripts/generate_nf_core_params.sh $OUTPUT_DIRECTORY $REFGENIE_ALIAS $NF_OPTIONS_PARSED

# Step 3: Run the nf-core RNA-seq pipeline

# Assuming you have the nf-core RNA-seq pipeline installed, replace the following line with the actual command
echo "Running nf-core RNA-seq pipeline..."
module load Java
cd $OUTPUT_DIRECTORY
nextflow run nf-core/rnaseq -profile singularity -params-file $OUTPUT_DIRECTORY/nf_core_params.json -c "/scratch_isilon/groups/compgen/lwange/singularity/rnaseq/cnag_rna-seq.config" --outdir $OUTPUT_DIRECTORY/map_2_${REFGENIE_ALIAS} 
