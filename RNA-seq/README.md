# RNA-seq Processing

RNA-seq data is processed using the [nf-core/rnaseq](https://nf-co.re/rnaseq) pipeline. Genome references and indices are managed via [refgenie](http://refgenie.databio.org/).

ERCC spike-in sequences are included in all runs via `refgenie seek ercc/fasta`.

## Usage

```bash
sbatch run_rna-seq_pipeline.v2.sh \
    <selected_samples_file> \
    <full_info_rds_file> \
    <output_directory> \
    <refgenie_alias> \
    [nf_options]
```

| Argument | Description |
|---|---|
| `selected_samples_file` | Text file listing sample IDs to process |
| `full_info_rds_file` | RDS file with full sample metadata (e.g. `CGLZOO_RNA.rds`) |
| `output_directory` | Directory where results and intermediate files are written |
| `refgenie_alias` | Refgenie genome alias (e.g. `Panthera_leo`; use `alias:tag` for TOGA genomes) |
| `nf_options` | Optional extra nf-core parameters as comma-separated `key=value` pairs |

**Example:**
```bash
sbatch run_rna-seq_pipeline.v2.sh \
    Samples_map2Bos_taurus.txt \
    /path/to/CGLZOO_RNA.rds \
    /path/to/RNA-seq/Batch1_HQ_Genomes/map2Bos_taurus \
    Bos_taurus
```

## Pipeline steps

1. **Sample sheet generation** (`scripts/generate_sample_info.R`) — reads the sample list and RDS metadata, writes `pipeline_info.csv` for nf-core input.
2. **Parameter file generation** (`scripts/generate_nf_core_params.sh` / `generate_nf_core_params_toga.sh`) — queries refgenie for fasta, GTF, and pre-built STAR index paths, adds the ERCC spike-in fasta, and writes `nf_core_params.json`.
3. **nf-core/rnaseq run** — submitted as a SLURM job (partition `genD`, QOS `marathon`) using singularity, reading parameters from `nf_core_params.json`.

## Refgenie assets used

| Asset | HQ genomes | TOGA genomes |
|---|---|---|
| `fasta` | yes | yes |
| `gencode_gtf` | yes | — |
| `toga_gtf` | — | yes |
| `star_index` | yes | yes |
| `ercc/fasta` (spike-in) | yes | yes |
