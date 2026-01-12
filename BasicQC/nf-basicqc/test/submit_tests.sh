#!/bin/bash
#SBATCH --job-name=nf_basicqc_test
#SBATCH --output=nf_basicqc_test_%j.out
#SBATCH --error=nf_basicqc_test_%j.err
#SBATCH --partition=genD
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=2
#SBATCH --mem=8G
#SBATCH --qos=normal
#SBATCH --time=12:00:00

# BasicQC Nextflow Pipeline - Test Suite
# Submit with: sbatch submit_tests.sh

# Set paths
PIPELINE_DIR="/scratch_isilon/groups/compgen/data/Illumina_CryoZoo/BasicQC/nf-basicqc"
FASTQ_SCREEN_CONF="/scratch_isilon/groups/compgen/data/Illumina_CryoZoo/genomes/FastQ_Screen_Genomes/fastq_screen.conf"
KRAKEN2_DB="/scratch_isilon/groups/compgen/data/Illumina_CryoZoo/genomes/kraken"

cd $PIPELINE_DIR

echo "$(date) Starting BasicQC pipeline tests"
echo "========================================="

# Load nextflow if needed (uncomment/modify as needed for your cluster)
# module load nextflow
# module load singularity

#------------------------------------------------------------------------------
# TEST 1: FastQC only
#------------------------------------------------------------------------------
echo "$(date) === Test 1: FastQC only ==="
nextflow run main.nf \
    --input test/test_samplesheet.csv \
    --outdir test/results_fastqc \
    --skip_fastq_screen \
    --skip_kraken2 \
    -profile singularity,slurm \
    -resume

#------------------------------------------------------------------------------
# TEST 2: FastQC + FastQ Screen
#------------------------------------------------------------------------------
echo "$(date) === Test 2: FastQC + FastQ Screen ==="
nextflow run main.nf \
    --input test/test_samplesheet.csv \
    --outdir test/results_fastq_screen \
    --fastq_screen_conf $FASTQ_SCREEN_CONF \
    --skip_kraken2 \
    -profile singularity,slurm \
    -resume

#------------------------------------------------------------------------------
# TEST 3: FastQC + Kraken2
#------------------------------------------------------------------------------
echo "$(date) === Test 3: FastQC + Kraken2 ==="
nextflow run main.nf \
    --input test/test_samplesheet.csv \
    --outdir test/results_kraken2 \
    --skip_fastq_screen \
    --kraken2_db $KRAKEN2_DB \
    --kraken2_subsample 100000 \
    -profile singularity,slurm \
    -resume

#------------------------------------------------------------------------------
# TEST 4: Full pipeline
#------------------------------------------------------------------------------
echo "$(date) === Test 4: Full pipeline ==="
nextflow run main.nf \
    --input test/test_samplesheet.csv \
    --outdir test/results_full \
    --fastq_screen_conf $FASTQ_SCREEN_CONF \
    --kraken2_db $KRAKEN2_DB \
    --kraken2_subsample 100000 \
    -profile singularity,slurm \
    -resume

echo "$(date) === All tests complete ==="
echo "Check results in: $PIPELINE_DIR/test/"
