# ATAC-seq Processing

ATAC-seq data is processed using the [nf-core/atacseq](https://nf-co.re/atacseq) pipeline. Genome references and indices are managed via [refgenie](http://refgenie.databio.org/).

## Usage

```bash
sbatch run_atac-seq_pipeline.v1.sh \
    <selected_samples_file> \
    <full_info_rds_file> \
    <output_directory> \
    <refgenie_alias> \
    [nf_options]
```

| Argument | Description |
|---|---|
| `selected_samples_file` | Text file listing sample IDs to process |
| `full_info_rds_file` | RDS file with full sample metadata (e.g. `CGLZOO_02.rds`) |
| `output_directory` | Directory where results and intermediate files are written |
| `refgenie_alias` | Refgenie genome alias (e.g. `Panthera_leo`; use `alias:tag` for TOGA genomes) |
| `nf_options` | Optional extra nf-core parameters as comma-separated `key=value` pairs |

**Example:**
```bash
sbatch run_atac-seq_pipeline.v1.sh \
    Samples_map2Panthera_leo.txt \
    /path/to/CGLZOO_02.rds \
    /path/to/ATAC/map2Panthera_leo \
    Panthera_leo
```

## Pipeline steps

1. **Sample sheet generation** (`scripts/generate_sample_info.R`) — reads the sample list and RDS metadata, writes `pipeline_info.csv` for nf-core input.
2. **Parameter file generation** (`scripts/generate_nf_core_params.sh` / `generate_nf_core_params_toga.sh`) — queries refgenie for fasta and GTF paths, auto-detects the mitochondrial chromosome name from COX1 and CYTB entries in the GTF, and writes `nf_core_params.json`.
3. **nf-core/atacseq run** — submitted as a SLURM job using singularity, reading parameters from `nf_core_params.json`.

## Refgenie assets used

| Asset | HQ genomes | TOGA genomes |
|---|---|---|
| `fasta` | yes | yes |
| `gencode_gtf` | yes | — |
| `toga_gtf` | — | yes |
