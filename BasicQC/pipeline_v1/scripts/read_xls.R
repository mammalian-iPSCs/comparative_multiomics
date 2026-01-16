#!/usr/bin/env Rscript
library(readxl)

# Arguments passed to R
args <- commandArgs(trailingOnly = TRUE)
xls_path <- args[1]
fastq_list <- args[2]
path <- args[3] ## path to fastq files
# Read the Excel file
xls_data <- read_excel(xls_path, skip = 2)

# Create fastq file paths
fastqs <- c(paste0(path,"/",xls_data$FLI, '_', 1, '.fastq.gz'), paste0(path,"/",xls_data$FLI, '_', 2, '.fastq.gz'))

# Write the output
writeLines(fastqs, fastq_list)