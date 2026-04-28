#!/usr/bin/env Rscript
library(tidyverse)

# Print a message indicating that the packages were loaded successfully
print("Packages loaded successfully")

# Check if the required arguments are provided
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 3) {
    stop("Error: Missing arguments. Usage: Rscript generate_sample_info.R <selected_samples> <full_info_rds> <output_directory>")
}

# Assign arguments to variables
selected_samples <- args[1] ## cnag_ids ofselected samples (file for testing the script:selected_samples="/home/groups/compgen/lwange/isilon/data/Illumina_CryoZoo/RNA-seq/Batch1_HQ_Genomes/Samples_map2Panthera_leo.txt")
full_info <- args[2] ## Rds file with fastqs (filefor testing: full_info="/home/groups/compgen/lwange/isilon/data/Illumina_CryoZoo/CGLZOO_ATAC.rds")
output_directory<- args[3] ## path to save the sample_info.csv file

# Print the arguments to verify they are correct
print(paste("Selected samples file:", selected_samples))
print(paste("Full info RDS file:", full_info))
print(paste("Output directory:", output_directory))


selected_samples <- read.delim(selected_samples, header = FALSE, stringsAsFactors = FALSE)$V1

pipeline_info <- readRDS(full_info) %>%
    ungroup() %>%
    filter(cnag_id %in% selected_samples) %>%
    select(cnag_id, paths) %>%
    separate(paths, into = c("fastq_1", "fastq_2"), sep = "\\[1-2\\]", remove = TRUE) %>%
    mutate(fastq_2 = paste0(fastq_1, "_2.fastq.gz"),
            fastq_1 = paste0(fastq_1, "_1.fastq.gz"),
            replicate = 1)%>%
    rename(sample=cnag_id)%>%
    filter(!is.na(sample)) %>%
    distinct()
  if(nrow(pipeline_info)>0){
    write_csv(pipeline_info,paste0(output_directory,"/pipeline_info.csv"))}
