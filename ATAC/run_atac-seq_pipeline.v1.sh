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

# Create the output directory if it doesn't exist
mkdir -p "$OUTPUT_DIRECTORY"

# Create a temp file for the Slurm script
JOB_SCRIPT="$OUTPUT_DIRECTORY/run_atac-seq_pipeline_${REFGENIE_ALIAS}.sh"

# Write the Slurm script to the file
cat <<EOF > "$JOB_SCRIPT"
#!/bin/bash
#SBATCH -n 1
#SBATCH -N 1
#SBATCH -c 1
#SBATCH -J $REFGENIE_ALIAS.ATAC
#SBATCH -e ${REFGENIE_ALIAS}.%J.err
#SBATCH -o ${REFGENIE_ALIAS}.%J.out
#SBATCH --mem=100G
#SBATCH --partition "genD"

# Description: This script runs the nf-core RNA-seq pipeline for a selected set of samples.
# Read the first command line argument into a variable named resume
resume=\$1

# Check if resume is empty
if [ -z "\$resume" ]; then
    echo "Resume argument is empty. Generating sample info and parameter files"

    mkdir -p $OUTPUT_DIRECTORY

    # Parse NF_OPTIONS into an array
    IFS=',' read -r -a NF_OPTIONS_ARRAY <<< "$NF_OPTIONS"
    NF_OPTIONS_PARSED=""

    # Iterate over the array and construct the options string
    for option in "\${NF_OPTIONS_ARRAY[@]}"; do
        key=\$(echo \$option | cut -d'=' -f1)
        value=\$(echo \$option | cut -d'=' -f2)
        if [[ "\$value" == "true" || "\$value" == "false" ]]; then
            NF_OPTIONS_PARSED+="\"\$key\":\$value,"
        else
            NF_OPTIONS_PARSED+="\"\$key\":\"\$value\","
        fi
    done

    # Convert the options string to a valid JSON object
    NF_OPTIONS_PARSED=\$(echo "\$NF_OPTIONS_PARSED" | sed 's/,$//')
    echo \$NF_OPTIONS_PARSED

    # Step 1: Generate the nf-core sample info
    module load R
    echo "Generating nf-core sample info..."
    Rscript /home/groups/compgen/lwange/isilon/data/Illumina_CryoZoo/ATAC/scripts/generate_sample_info.R $SELECTED_SAMPLES_FILE $FULL_INFO_RDS_FILE $OUTPUT_DIRECTORY

    # Step 2: Generate the nf-core params file
    echo "Generating nf-core params file..."
    bash /home/groups/compgen/lwange/isilon/data/Illumina_CryoZoo/ATAC/scripts/generate_nf_core_params.sh $OUTPUT_DIRECTORY $REFGENIE_ALIAS \$NF_OPTIONS_PARSED
else
    echo "Resume argument is not empty. Resuming nf-core RNA-seq pipeline..."
fi
# Step 3: Run the nf-core RNA-seq pipeline
echo "Running nf-core RNA-seq pipeline..."
module load Java
cd $OUTPUT_DIRECTORY
nextflow run nf-core/atacseq -profile singularity -params-file $OUTPUT_DIRECTORY/nf_core_params.json -c /home/groups/compgen/lwange/isilon/lwange/singularity/atacseq/cnag2.config -resume --outdir $OUTPUT_DIRECTORY/map_2_${REFGENIE_ALIAS} --name "${REFGENIE_ALIAS,,}_atac" 
EOF

# Submit the job
sbatch "$JOB_SCRIPT"

