#!/usr/bin/env Rscript
library(readr)
library(stringr)
library(tidyverse)
library(janitor)

# Check if the required arguments are provided
args <- commandArgs(trailingOnly = TRUE)
if (length(args) < 2) {
  stop("Error: Missing arguments. Usage: Rscript make_sample_lists.R <selected_samples.csv> <full_info_rds>")
}

samples<-args[1]
fastq_list<-args[2]
path<-str_remove(samples,pattern="sample_to_genome.csv")

samples<-"/Users/lucas/scratch/data/Illumina_CryoZoo/ATAC/map2TOGA/sample_to_genome.csv"
fastq_list<-"/Users/lucas/scratch/data/Illumina_CryoZoo/CGLZOO_ATAC.rds"

samples_df<-read_csv(samples)
samples_df<-clean_names(samples_df)
fastq_list_df<-readRDS(fastq_list)

i="Gorilla_gorilla_TOGA"
for (i in unique(samples_df$genome_toga)){

tmp<-subset(samples_df,genome_toga==i) %>%
    left_join(fastq_list_df,by="animal_id") %>%
    select(cnag_id) %>%
    distinct() %>%
    filter(!is.na(cnag_id))
  if(nrow(tmp)>0){
    write_delim(paste0(path,i,"_Samples.txt"),col_names = F)
    }
}
