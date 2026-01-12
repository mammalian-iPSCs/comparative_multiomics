#!/bin/bash
# BasicQC Nextflow Pipeline - Test Script
# Run these tests stepwise on the cluster

# Set paths (adjust if needed)
PIPELINE_DIR="/scratch_isilon/groups/compgen/data/Illumina_CryoZoo/BasicQC/nf-basicqc"
FASTQ_SCREEN_CONF="/scratch_isilon/groups/compgen/data/Illumina_CryoZoo/genomes/FastQ_Screen_Genomes/fastq_screen.conf"
KRAKEN2_DB="/scratch_isilon/groups/compgen/data/Illumina_CryoZoo/genomes/kraken"

cd $PIPELINE_DIR

#------------------------------------------------------------------------------
# STEP 0: Verify syntax (can run locally or on cluster)
#------------------------------------------------------------------------------
echo "=== Step 0: Verify pipeline syntax ==="
nextflow run main.nf --help

#------------------------------------------------------------------------------
# STEP 1: Stub run - test workflow logic with placeholder outputs
#------------------------------------------------------------------------------
echo "=== Step 1: Stub run (test workflow without real execution) ==="
nextflow run main.nf \
    --input test/test_samplesheet.csv \
    --outdir test/results_stub \
    --skip_fastq_screen \
    --skip_kraken2 \
    -stub

#------------------------------------------------------------------------------
# STEP 2: Test FastQC only (fastest, no external DBs needed)
#------------------------------------------------------------------------------
echo "=== Step 2: Test FastQC only ==="
nextflow run main.nf \
    --input test/test_samplesheet.csv \
    --outdir test/results_fastqc \
    --skip_fastq_screen \
    --skip_kraken2 \
    -profile singularity

#------------------------------------------------------------------------------
# STEP 3: Test FastQC + FastQ Screen
#------------------------------------------------------------------------------
echo "=== Step 3: Test FastQC + FastQ Screen ==="
nextflow run main.nf \
    --input test/test_samplesheet.csv \
    --outdir test/results_fastq_screen \
    --fastq_screen_conf $FASTQ_SCREEN_CONF \
    --skip_kraken2 \
    -profile singularity

#------------------------------------------------------------------------------
# STEP 4: Test FastQC + Kraken2 (with small subsample)
#------------------------------------------------------------------------------
echo "=== Step 4: Test FastQC + Kraken2 ==="
nextflow run main.nf \
    --input test/test_samplesheet.csv \
    --outdir test/results_kraken2 \
    --skip_fastq_screen \
    --kraken2_db $KRAKEN2_DB \
    --kraken2_subsample 100000 \
    -profile singularity

#------------------------------------------------------------------------------
# STEP 5: Full pipeline test (local execution)
#------------------------------------------------------------------------------
echo "=== Step 5: Full pipeline (local) ==="
nextflow run main.nf \
    --input test/test_samplesheet.csv \
    --outdir test/results_full \
    --fastq_screen_conf $FASTQ_SCREEN_CONF \
    --kraken2_db $KRAKEN2_DB \
    --kraken2_subsample 100000 \
    -profile singularity

#------------------------------------------------------------------------------
# STEP 6: Full pipeline on SLURM
#------------------------------------------------------------------------------
echo "=== Step 6: Full pipeline (SLURM) ==="
nextflow run main.nf \
    --input test/test_samplesheet.csv \
    --outdir test/results_slurm \
    --fastq_screen_conf $FASTQ_SCREEN_CONF \
    --kraken2_db $KRAKEN2_DB \
    --kraken2_subsample 100000 \
    -profile singularity,slurm

echo "=== All tests complete ==="
