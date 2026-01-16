#### Script recovered after deletion by mistake might be buggy ####

#!/bin/bash
# Redirect all output and errors to a log file
exec >runQC_output.${3}.log 2>&1

echo "$(date) Starting script" 

# Check for input arguments
if [[ $# -ne 4 ]]; then
  echo "Usage: $0 </path/to/input/> <project (e.g. CGLZOO_01)> <type (e.g. RNA-seq)> </path/to/output/>"
  exit 1
fi
## bash runQC_1.2.sh /scratch_isilon/groups/compgen/data_transfer CGLZOO_01 RNA-seq /scratch_isilon/groups/compgen/data/Illumina_CryoZoo/BasicQC

# Input arguments
BASEPATH="$1"
PROJECT="$2"
TYPE="$3"
OUTDIR="$4"

FASTQ_XLS="${BASEPATH}/${PROJECT}/${PROJECT}.xls"
FASTQ_LIST="${OUTDIR}/${PROJECT}/${PROJECT}_fastq_list.txt"

# Create the main project directory in the QC directory
cd $OUTDIR
mkdir -p "$PROJECT"
WORKDIR=$OUTDIR/$PROJECT

# Define subfolder names
SUBFOLDERS=("fastqc" "fastq_screen" "logs" "slurm")

# Create subfolders within the project directory
for subfolder in "${SUBFOLDERS[@]}"; do
  mkdir -p "$PROJECT/$subfolder"
done

echo "Project directory structure created:"
tree "$PROJECT" 2>/dev/null || ls -R "$PROJECT"

# Run the R script to create the FASTQ list
module load R
Rscript scripts/read_xls.R "$FASTQ_XLS" "$FASTQ_LIST" "$BASEPATH"

# Check if the FASTQ list was created
if [[ ! -f "$FASTQ_LIST" ]]; then
  echo "Error: Failed to create FASTQ list from $FASTQ_XLS"
  exit 1
fi

echo "$(date) checking md5sums" 
sbatch -J md5sums_${PROJECT} scripts/verify_md5sums.sh $BASEPATH $WORKDIR $FASTQ_LIST

# SLURM job template
JOB_TEMPLATE="#!/bin/bash
#SBATCH --job-name={JOB_NAME}
#SBATCH --output=${PROJECT}/logs/{JOB_NAME}.out
#SBATCH --error=${PROJECT}/logs/{JOB_NAME}.err
#SBATCH --partition=genD   # Adjust partition as needed
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=5
#SBATCH --mem=10G             # Adjust memory as needed

module load FastQC  # Load necessary modules here

# Task 1: Running FastQC
echo 'Running FastQC on {FASTQ_FILE}'
fastqc -o ${WORKDIR}/fastqc/ {FASTQ_FILE}

# Task 2: Running fastq_screen
echo 'Running fastq_screen on {FASTQ_FILE}'
fastq_screen --conf /scratch_isilon/groups/compgen/data/Illumina_CryoZoo/genomes/FastQ_Screen_Genomes/FastQ_Screen_Genomes/fastq_screen.conf --threads 10 --outdir ${WORKDIR}/fastq_screen/ {FASTQ_FILE}
"

# Loop through each FASTQ file and submit a job
# Loop through each FASTQ file and submit a job
while read -r FASTQ; do
  # Check if the FASTQ file exists
  if [[ ! -f "$FASTQ" ]]; then
    echo "Warning: FASTQ file '$FASTQ' not found. Skipping..."
    continue
  fi

  # Generate a unique job name based on the FASTQ file
  JOB_NAME=$(basename "$FASTQ" .fastq.gz)

  # Create a temporary SLURM script for this FASTQ file
  JOB_SCRIPT="${PROJECT}/slurm/${JOB_NAME}.sh"
  echo "${JOB_TEMPLATE}" | sed \
    -e "s|{JOB_NAME}|$JOB_NAME|g" \
    -e "s|{FASTQ_FILE}|$FASTQ|g" \
    -e "s|{WORKDIR}|$WORKDIR|g" > "$JOB_SCRIPT"

  # Submit the job to SLURM
  sbatch "$JOB_SCRIPT"

  echo "Job for $FASTQ submitted as $JOB_NAME"
done < "$FASTQ_LIST"