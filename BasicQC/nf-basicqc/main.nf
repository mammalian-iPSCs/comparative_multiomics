#!/usr/bin/env nextflow

/*
========================================================================================
    BasicQC Pipeline
========================================================================================
    A Nextflow pipeline for basic QC of Illumina FASTQ files
    - FastQC: Quality control metrics
    - FastQ Screen: Species/contamination detection
    - Kraken2: Taxonomic classification
    - MultiQC: Aggregate reports
----------------------------------------------------------------------------------------
*/

nextflow.enable.dsl = 2

// Import modules
include { FASTQC          } from './modules/fastqc'
include { FASTQ_SCREEN    } from './modules/fastq_screen'
include { SEQTK_SUBSAMPLE } from './modules/seqtk_subsample'
include { KRAKEN2         } from './modules/kraken2'
include { MULTIQC         } from './modules/multiqc'

/*
========================================================================================
    HELP MESSAGE
========================================================================================
*/

def helpMessage() {
    log.info"""
    =========================================
     BasicQC Pipeline v1.0
    =========================================
    Usage:
      nextflow run main.nf --input samplesheet.csv --outdir results

    Mandatory arguments:
      --input           Path to input samplesheet (CSV format)
      --outdir          Output directory for results

    Optional arguments:
      --fastq_screen_conf   Path to fastq_screen configuration file
      --kraken2_db          Path to Kraken2 database
      --kraken2_subsample   Number of reads to subsample for Kraken2 (default: 5000000)
      --skip_fastqc         Skip FastQC step
      --skip_fastq_screen   Skip FastQ Screen step
      --skip_kraken2        Skip Kraken2 step
      -profile              Configuration profile (singularity, docker, conda)

    Samplesheet format (CSV):
      sample,fastq_1,fastq_2
      sample1,/path/to/sample1_R1.fastq.gz,/path/to/sample1_R2.fastq.gz
      sample2,/path/to/sample2_R1.fastq.gz,/path/to/sample2_R2.fastq.gz
    """.stripIndent()
}

// Show help message
if (params.help) {
    helpMessage()
    exit 0
}

/*
========================================================================================
    VALIDATE INPUTS
========================================================================================
*/

// Check mandatory parameters
if (!params.input) {
    error "Please provide an input samplesheet with --input"
}

if (!params.outdir) {
    error "Please provide an output directory with --outdir"
}

// Check input file exists
input_file = file(params.input)
if (!input_file.exists()) {
    error "Input samplesheet not found: ${params.input}"
}

/*
========================================================================================
    INPUT CHANNEL
========================================================================================
*/

def parse_samplesheet(samplesheet) {
    Channel
        .fromPath(samplesheet)
        .splitCsv(header: true)
        .map { row ->
            def sample = row.sample
            def fastq_1 = file(row.fastq_1)
            def fastq_2 = row.fastq_2 ? file(row.fastq_2) : null

            if (!fastq_1.exists()) {
                error "FASTQ file not found: ${row.fastq_1}"
            }
            if (fastq_2 && !fastq_2.exists()) {
                error "FASTQ file not found: ${row.fastq_2}"
            }

            return fastq_2 ? tuple(sample, [fastq_1, fastq_2]) : tuple(sample, [fastq_1])
        }
}

/*
========================================================================================
    MAIN WORKFLOW
========================================================================================
*/

workflow {

    // Parse samplesheet and create input channel
    ch_reads = parse_samplesheet(params.input)

    // Initialize empty channels for MultiQC
    ch_multiqc_files = Channel.empty()

    //
    // MODULE: FastQC
    //
    if (!params.skip_fastqc) {
        FASTQC(ch_reads)
        ch_multiqc_files = ch_multiqc_files.mix(FASTQC.out.zip)
    }

    //
    // MODULE: FastQ Screen
    //
    if (!params.skip_fastq_screen) {
        // Check for fastq_screen config
        if (!params.fastq_screen_conf) {
            log.warn "No FastQ Screen config provided (--fastq_screen_conf). Skipping FastQ Screen."
        } else {
            ch_fastq_screen_conf = file(params.fastq_screen_conf)
            FASTQ_SCREEN(ch_reads, ch_fastq_screen_conf)
            ch_multiqc_files = ch_multiqc_files.mix(FASTQ_SCREEN.out.txt)
        }
    }

    //
    // MODULE: Kraken2 (with subsampling)
    //
    if (!params.skip_kraken2) {
        if (!params.kraken2_db) {
            log.warn "No Kraken2 database provided (--kraken2_db). Skipping Kraken2."
        } else {
            ch_kraken2_db = file(params.kraken2_db)

            // Subsample reads before Kraken2 for efficiency
            SEQTK_SUBSAMPLE(ch_reads, params.kraken2_subsample)

            // Run Kraken2 on subsampled reads
            KRAKEN2(SEQTK_SUBSAMPLE.out.reads, ch_kraken2_db)
            ch_multiqc_files = ch_multiqc_files.mix(KRAKEN2.out.report)
        }
    }

    //
    // MODULE: MultiQC
    //
    ch_multiqc_files
        .collect()
        .set { ch_multiqc_input }

    MULTIQC(ch_multiqc_input)
}

/*
========================================================================================
    COMPLETION
========================================================================================
*/

workflow.onComplete {
    log.info ""
    log.info "Pipeline completed at: ${workflow.complete}"
    log.info "Execution status: ${workflow.success ? 'OK' : 'failed'}"
    log.info "Results saved to: ${params.outdir}"
    log.info ""
}
