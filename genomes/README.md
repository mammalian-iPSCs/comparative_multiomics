# Genome Management

All reference genomes and annotations are managed with [refgenie](http://refgenie.databio.org/). The currently registered genomes and assets are listed in the [main README](../README.md#genomes).

Provenance for all genomes is tracked in [`genome_metadata.tsv`](genome_metadata.tsv).

---

## Adding TOGA genomes

TOGA1 and TOGA2 annotations are served from the Senckenberg server (`genome.senckenberg.de`). Each script downloads the genome fasta and GTF annotation, registers both as refgenie assets (`fasta` and `toga_gtf`), and appends a row to `genome_metadata.tsv`.

### TOGA2 (preferred for species available in both)

Genomes are distributed as `.2bit` files (requires `twoBitToFa` from UCSC kent tools).

**Single assembly:**
```bash
sbatch scripts/Download_toga2_and_add_to_refgenie.sh -a HLaciJub2
```

**Multiple assemblies in parallel:**
```bash
scripts/Download_toga2_batch.sh HLaciJub2,HLailMel2,HLaddNas1
```

**All assemblies (~700+ species, careful):**
```bash
scripts/Download_toga2_batch.sh
```

Key options for `Download_toga2_and_add_to_refgenie.sh`:

| Flag | Default | Description |
|---|---|---|
| `-a` | all | Comma-separated assembly names to process |
| `-t` | downloaded | Path to `assemblies_and_species.tsv` |
| `-r` | `reference_human_hg38` | TOGA2 reference to use for annotations |
| `-c` | `Mammalia` | Taxonomic class for genome downloads (`Mammalia`, `Aves`, `CEC`) |
| `-o` | `./toga2_downloads` | Output directory |
| `-m` | `./genome_metadata.tsv` | Metadata file |

### TOGA1 (for species not in TOGA2)

Genomes are downloaded from NCBI (via `datasets` CLI) for GCA/GCF accessions, or via `wget` for HTTP/FTP URLs. Sources like "DNA Zoo Consortium" cannot be automated and require manual download.

**Single assembly:**
```bash
sbatch scripts/Download_toga1_and_add_to_refgenie.sh -a HLgorGor7
```

**Multiple assemblies in parallel:**
```bash
scripts/Download_toga1_batch.sh HLgorGor7,HLhipAmp3
```

To skip assemblies already covered by TOGA2, pass the `assemblies_and_species.tsv` via `-2` or the `TOGA2_TSV` env var:
```bash
TOGA2_TSV=/path/to/assemblies_and_species.tsv \
scripts/Download_toga1_batch.sh HLgorGor7,HLhipAmp3
```

If TOGA annotations have already been downloaded locally (e.g. from a bulk transfer), use `-l` to point to the local directory instead of downloading from the server:
```bash
sbatch scripts/Download_toga1_and_add_to_refgenie.sh \
    -a HLgorGor7 \
    -l /path/to/TOGA_annotations/download/TOGA
```

Key options for `Download_toga1_and_add_to_refgenie.sh`:

| Flag | Default | Description |
|---|---|---|
| `-a` | all | Comma-separated assembly names |
| `-t` | downloaded | Path to `overview.table.tsv` |
| `-2` | not set | TOGA2 `assemblies_and_species.tsv` — matching assemblies are skipped |
| `-l` | not set | Local TOGA annotation directory (skip server download) |
| `-r` | `human_hg38_reference` | TOGA1 reference |
| `-G` | off | Skip genome download (GTF only; assumes fasta already in refgenie) |
| `-o` | `./toga1_downloads` | Output directory |
| `-m` | `./genome_metadata.tsv` | Metadata file |

---

## Adding non-TOGA genomes

For genomes with Gencode/Ensembl/NCBI annotations (not TOGA), the workflow is:

**1. Download genome and annotation from NCBI:**
```bash
conda activate ncbi_datasets
datasets download genome accession GCF_XXXXXXXXX.X --include genome,gtf
```

**2. Add fasta to refgenie:**
```bash
# Single genome
sbatch scripts/Add_genomes.sh path/to/genome.fna Species_name

# Multiple genomes from a CSV (columns: fasta_path,alias)
scripts/Add_genomes_batch.sh   # reads fasta_list2.csv
```
`Add_genomes.sh` handles gzip compression automatically if the input is not already gzipped.

**3. Build additional assets (GTF, indices):**
```bash
# Single genome, one or more comma-separated assets
sbatch scripts/Add_refgenie_asset.sh <alias> <assets> [tag] [gtf_path]

# Examples
sbatch scripts/Add_refgenie_asset.sh Panthera_leo gencode_gtf
sbatch scripts/Add_refgenie_asset.sh Panthera_leo star_index
sbatch scripts/Add_refgenie_asset.sh Panthera_leo bowtie2_index
sbatch scripts/Add_refgenie_asset.sh Panthera_leo gencode_gtf,star_index

# Multiple genomes from a CSV (columns: alias,gtf_path)
scripts/Add_gtf_batch.sh   # reads gtf_list.csv
```

Supported assets in `Add_refgenie_asset.sh`:

| Asset | Tool required | Notes |
|---|---|---|
| `gencode_gtf` | `gffread` (GFF→GTF only) | Finds `.gtf`/`.gff` automatically under `<alias>/`, or use explicit path |
| `star_index` | STAR | Auto-calculates `genomeChrBinNbits` from contig count and genome size |
| `bowtie2_index` | Bowtie2 | |
| `toga_gtf` | — | Custom asset; requires explicit path to GTF directory |

---

## Updating the genome list in the main README

After adding new genomes, regenerate the genome table in the main `README.md`:

```bash
cd genomes
bash update_genome_list.sh
```

This replaces everything after the `<!-- GENOMES_START -->` marker with a fresh `refgenie list` output.

---

## Genome metadata

[`genome_metadata.tsv`](genome_metadata.tsv) records provenance for all registered genomes. It is updated automatically by the TOGA download scripts and should be updated manually when adding non-TOGA genomes.

Columns:

| Column | Description |
|---|---|
| `assembly_name` | Refgenie alias |
| `species` | Binomial species name |
| `common_name` | Common name |
| `accession` | NCBI accession or equivalent |
| `taxonomy_id` | NCBI taxonomy ID |
| `lineage` | Semicolon-separated taxonomic lineage |
| `genome_source` | Where the fasta was obtained |
| `annotation_source` | Where the GTF was obtained |
| `annotation_reference` | Reference genome used for TOGA (e.g. `human_hg38_reference`) |
| `date_added` | Date the entry was recorded (YYYY-MM-DD) |

---

## Archived notes

<details>
<summary>Original README (manual commands used during initial setup)</summary>

```
### Downloading a genome

conda activate ncbi_datasets

# dataset command from ncbi

## download gtf directly instead of gff!!

mkdir Panthera_leo
datasets download genome accession GCF_018350215.1 --include gtf

mkdir Canis_lupus
datasets download genome accession GCF_011100685.1 --include gtf,rna,cds,protein,genome,seq-report

mkdir Notamacropus_eugeni
datasets download genome accession GCA_028372415.1 --include gff3,rna,cds,protein,genome,seq-report ## Notamacropus eugeni

mkdir Loxodonta_africana
cd Loxodonta_africana
datasets download genome accession GCF_030014295.1 --include gff3,rna,cds,protein,genome,seq-report 
datasets download genome accession GCF_030014295.1 --include gtf

mkdir Anolis_carolinensis 
cd Anolis_carolinensis
datasets download genome accession GCF_035594765.1 --include gff3,rna,cds,protein,genome,seq-report 
datasets download genome accession GCF_035594765.1 --include gtf
cd ../
mkdir Caretta_caretta
cd Caretta_caretta
datasets download genome accession GCF_023653815.1 --include gff3,rna,cds,protein,genome,seq-report 
datasets download genome accession GCF_023653815.1 --include gtf
cd ../
mkdir Bombina_bombina
cd Bombina_bombina
datasets download genome accession GCF_027579735.1 --include gff3,rna,cds,protein,genome,seq-report 
datasets download genome accession GCF_027579735.1 --include gtf
cd ../

mkdir Equus_caballus
cd Equus_caballus
datasets download genome accession GCF_041296265.1 --include gff3,rna,cds,protein,genome,seq-report
datasets download genome accession GCF_041296265.1 --include gtf

mkdir Bos_taurus
datasets download genome accession GCF_002263795.3 --include gtf

cd Pan_troglodytes
datasets download genome accession GCF_000001515.7 --include gtf

datasets download genome accession GCF_028858775.2 --include gtf,rna,cds,protein,genome,seq-report

cd Callithrix_jacchus
datasets download genome accession GCF_011100555.1 --include gtf


# Add genomes to refgenie
conda activate basicQC

sbatch Add_genomes.sh Canis_lupus/ncbi_dataset/data/GCF_011100685.1/GCF_011100685.1_UU_Cfam_GSD_1.0_genomic.fna Canis_lupus 
sbatch Add_genomes.sh Panthera_leo/ncbi_dataset/data/GCF_018350215.1/GCF_018350215.1_P.leo_Ple1_pat1.1_genomic.fna Panthera_leo
sbatch Add_genomes.sh Caretta_caretta/ncbi_dataset/data/GCF_023653815.1/GCF_023653815.1_GSC_CCare_1.0_genomic.fna Caretta_caretta
sbatch Add_genomes.sh Anolis_carolinensis/ncbi_dataset/data/GCF_035594765.1/GCF_035594765.1_rAnoCar3.1.pri_genomic.fna Anolis_carolinensis
sbatch Add_genomes.sh Bombina_bombina/ncbi_dataset/data/GCF_027579735.1/GCF_027579735.1_aBomBom1.pri_genomic.fna Bombina_bombina
sbatch Add_genomes.sh Panthera_leo/ncbi_dataset/data/GCF_018350215.1/GCF_018350215.1_P.leo_Ple1_pat1.1_genomic.fna Panthera_leo
sbatch Add_genomes.sh Notamacropus_eugeni/ncbi_dataset/data/GCA_028372415.1/GCA_028372415.1_mMacEug1.pri_genomic.fna Notamacropus_eugeni
sbatch Add_genomes.sh Gallus_gallus/ncbi_dataset/data/GCF_016699485.2/GCF_016699485.2_bGalGal1.mat.broiler.GRCg7b_genomic.fna Gallus_gallus
sbatch Add_genomes.sh Loxodonta_africana/ncbi_dataset/data/GCF_030014295.1/GCF_030014295.1_mLoxAfr1.hap2_genomic.fna Loxodonta_africana
sbatch Add_genomes.sh Equus_caballus/ncbi_dataset/data/GCF_041296265.1/GCF_041296265.1_TB-T2T_genomic.fna Equus_caballus

sbatch scripts/Add_genomes.sh ncbi_dataset/data/*/GCF_000001515.7_Pan_tro_3.0_genomic.fna panTro5_GCF_000001515.7
sbatch scripts/Add_genomes.sh ncbi_dataset/data/*/GCF_000151905.2_gorGor4_genomic.fna  gorGor4_GCF_000151905.2
sbatch scripts/Add_genomes.sh ncbi_dataset/data/*/GCA_000001545.3_P_pygmaeus_2.0.2_genomic.fna ponAbe2_GCA_000001545.3
sbatch scripts/Add_genomes.sh ncbi_dataset/data/*/GCF_000772875.2_Mmul_8.0.1_genomic.fna rheMac8_GCF_000772875.2

## Add asset
conda activate genomes
todo: remove gencode_gtf assets for everything but Canis_lupus and Panthera_leo
assets: star_index, bowtie2_index, gencode_gtf
sbatch Add_refgenie_asset.sh Canis_lupus gencode_gtf 
sbatch Add_refgenie_asset.sh Panthera_leo gencode_gtf
sbatch Add_refgenie_asset.sh Caretta_caretta gencode_gtf
sbatch Add_refgenie_asset.sh Anolis_carolinensis gencode_gtf
sbatch Add_refgenie_asset.sh Equus_caballus gencode_gtf
sbatch Add_refgenie_asset.sh Bos_taurus gencode_gtf
sbatch Add_refgenie_asset.sh Callithrix_jacchus gencode_gtf
sbatch Add_refgenie_asset.sh Gallus_gallus gencode_gtf

sbatch Add_refgenie_asset.sh Loxodonta_africana gencode_gtf,star_index
sbatch Add_refgenie_asset.sh Bombina_bombina gencode_gtf,star_index
sbatch Add_refgenie_asset.sh Notamacropus_eugeni star_index

####### manual way instead of Add_genomes.sh script
# fasta files have to be gzipped for refgenie

gzip -c Callithrix_jacchus/ncbi_dataset/data/GCF_011100555.1/GCF_011100555.1_mCalJa1.2.pat.X_genomic.fna > Callithrix_jacchus/ncbi_dataset/data/GCF_011100555.1/GCF_011100555.1_mCalJa1.2.pat.X_genomic.fna.gz

gzip -c Bos_taurus/GCF_002263795.3/GCF_002263795.3_ARS-UCD2.0_genomic.fna > Bos_taurus/GCF_002263795.3/GCF_002263795.3_ARS-UCD2.0_genomic.fna.gz

gzip -c Gallus_gallus/ncbi_dataset/data/GCF_016699485.2/GCF_016699485.2_bGalGal1.mat.broiler.GRCg7b_genomic.fna > Gallus_gallus/ncbi_dataset/data/GCF_016699485.2/GCF_016699485.2_bGalGal1.mat.broiler.GRCg7b_genomic.fna.gz

gzip -c Canis_lupus/ncbi_dataset/data/GCF_011100685.1/GCF_011100685.1_UU_Cfam_GSD_1.0_genomic.fna > Canis_lupus/ncbi_dataset/data/GCF_011100685.1/GCF_011100685.1_UU_Cfam_GSD_1.0_genomic.fna.gz


### Adding a genome to refgenie

conda activate basicQC 

refgenie list  ## to check which genomes and assets are already there

module load SAMtools

refgenie build alias/fasta --files fasta=fasta.fq.gz ## --requirements to know what files are required to build a certain asset

refgenie build -R Callithrix_jacchus/fasta --files fasta=Callithrix_jacchus/ncbi_dataset/data/GCF_011100555.1/GCF_011100555.1_mCalJa1.2.pat.X_genomic.fna.gz

refgenie build Canis_lupus/fasta --files fasta=Canis_lupus/GCF_011100685.1/GCF_011100685.1_UU_Cfam_GSD_1.0_genomic.fna.gz

refgenie build Bos_taurus/fasta --files fasta=Bos_taurus/GCF_002263795.3/GCF_002263795.3_ARS-UCD2.0_genomic.fna.gz


## Add assets

sbatch --dependency afterok:34455053 Add_refgenie_asset.sh Loxodonta_africana bowtie2_index

make sure the relevant programms to generate the asset are available. i.e. samtools for fasta or bowtie2 to builed a bowtie2_index , STAR for star_index etc.


# Add genome to FastQ-Screen

conda activate basicQC

fastq_screen add_genome 'Database name','Genome path and basename','Notes'


## run fastqScreen

module load Bowtie2

sbatch -c 10 --mem 20G --partition=genD --wrap "fastq_screen --conf /scratch_isilon/groups/compgen/data/Illumina_CryoZoo/genomes/FastQ_Screen_Genomes/FastQ_Screen_Genomes/fastq_screen.conf --threads 10 --outdir /scratch_isilon/groups/compgen/data/Illumina_CryoZoo/BasicQC/CGLZOO_01/fastq_screen /scratch_isilon/groups/compgen/data_transfer/CGLZOO_01/20241128/FASTQ/HFYMJDSXC_1_8bp-UDP0032_1.fastq.gz"
```

</details>
