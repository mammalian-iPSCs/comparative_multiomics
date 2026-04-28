#!/bin/bash

#SBATCH -J get_SRA_fq
#SBATCH -q normal
#SBATCH -D /scratch_isilon/groups/compgen/data/Illumina_CryoZoo/ATAC/test1/LCLs_chimp/
#SBATCH -N 1 # number of nodes
#SBATCH -n 1 # number of tasks
#SBATCH -o slurm.%N.%j.out # STDOUT
#SBATCH -e slurm.%N.%j.err # STDERR

module load Java

/scratch_isilon/groups/compgen/data/Illumina_PGDP_Phase2/Phase2_CNAG/sarek/nextflow-23.04.3-all run nf-core/fetchngs \
--input "/scratch_isilon/groups/compgen/data/Illumina_CryoZoo/ATAC/test1/LCLs_chimp/ids.csv" \
--outdir "/scratch_isilon/groups/compgen/data/Illumina_CryoZoo/ATAC/test1/LCLs_chimp/fastq/" \
-profile singularity \
-c "/scratch_isilon/groups/compgen/data/Illumina_CryoZoo/ATAC/atac_pipe/cnag2.config"