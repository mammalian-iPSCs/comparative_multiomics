#!/usr/bin/env Rscript

# Load libraries
install_if_missing <- function(packages) {
  to_install <- packages[!(packages %in% installed.packages()[, "Package"])]
  if (length(to_install) > 0) {
    message("Installing missing packages: ", paste(to_install, collapse = ", "))
    install.packages(to_install, repos = "http://cran.r-project.org")
  } else {
    message("All required packages are already installed.")
  }
}

# List of required libraries
required_packages <- c("tidyverse", "patchwork", "readxl","janitor")

# Check and install missing libraries
install_if_missing(required_packages)

# Load the libraries
lapply(required_packages, library, character.only = TRUE)

theme_set(theme_minimal())

# Retrieve command-line arguments
args <- commandArgs(trailingOnly = TRUE)

# Check if the correct number of arguments is provided
if (length(args) != 4) {
  stop("Error: This script requires exactly three input arguments.\nUsage: Rscript plotQC.R <meta_data.txt> <project> <path> <type>")
}

# Assign inputs to variables
meta_data <- args[1]  # path to sample info
project <- args[2]
path <- args[3]
type <- args[4]
# 
# meta_data <- "/Users/lucas/scratch/data/Illumina_CryoZoo/test_sample_info.txt"
# project <- "test"
# path <- "/Users/lucas/scratch/data/Illumina_CryoZoo/BasicQC/test/"
# type <- "WGS"

setwd(path)

# If the inputs are file paths, read them
if (file.exists(meta_data)) {
  meta_df <- read_delim(meta_data)
  cat("Loaded data from", meta_data, "\n")
}

fastq_info<-paste0(path,"/",project,".xls")

if (file.exists(fastq_info)) {
  fastq_df <- read_xls(fastq_info,skip=2)
  fastq_df<-clean_names(fastq_df)
  cat("Loaded data from", fastq_info, "\n")
}

samplestats_info<-paste0(path,"/",project,"_Sample_Stats.xls")

if (file.exists(samplestats_info)) {
  samplestats_info_df <- read_xls(samplestats_info)
  samplestats_info_df<-clean_names(samplestats_info_df)
  samplestats_info_df<-samplestats_info_df %>% filter(!is.na(number_of_fl_is))
  cat("Loaded data from", samplestats_info, "\n")
}

####

p1<-ggplot(samplestats_info_df)+
  geom_boxplot(aes(x=8,y=yield_gb),outlier.shape = NA,width=10,notch = T,alpha=0.5)+
  geom_point(aes(x= number_of_fl_is,y=yield_gb,colour = factor(number_of_fl_is)),show.legend = F)+
  geom_hline(yintercept = 60,col="red")+
  xlab("number of flowcells")

p2<-samplestats_info_df %>%
  select(avg_phi_x_error_r1,avg_phi_x_error_r2,number_of_fl_is) %>%
  distinct() %>%
  ggplot(aes(x= avg_phi_x_error_r1,y=avg_phi_x_error_r2))+
  geom_abline(slope = 1)+
  geom_point(aes(x= avg_phi_x_error_r1,y=avg_phi_x_error_r2,col=factor(number_of_fl_is)))+
  labs(colour="number of flowcells")+
  xlim(0.2,0.35)+
  ylim(0.2,0.35)
p.comb<-p1+p2
ggsave(filename = "yield_vs_error.pdf",device="pdf",plot = p.comb,path = paste0(path,"/Rplots/"),dpi = 300,width = 12)



####
if (type=="WGS"){
  p.theoreticalcov<-left_join(meta_df,samplestats_info_df,by=c("cnag_id"="sample_barcode","library_id"="sample_name")) %>%
    mutate(theoretical_coverage=yield_gb/genome_size) %>%
    ggplot() +
    geom_point(aes(x=reorder(species,theoretical_coverage),y=theoretical_coverage))+
    geom_hline(yintercept = 30)+
    coord_flip()+
    labs(x="")

  ggplot2::ggsave(plot=p.theoreticalcov,filename="theoretical_cov.pdf",device = "pdf",path = paste0(path,"/Rplots/"),dpi = 300)
}
