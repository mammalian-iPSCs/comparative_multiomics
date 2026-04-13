#!/usr/bin/env bash
#SBATCH --job-name=toga2_refgenie
#SBATCH --output=logs/toga2_refgenie_%j.out
#SBATCH --error=logs/toga2_refgenie_%j.err
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=4
#SBATCH --mem=30G
#SBATCH --partition=genD

set -euo pipefail

#########################
# Conda env
#########################
export PATH="/home/groups/compgen/lwange/.conda/envs/genomes/bin:$HOME/ucsc-bin-env/bin:$PATH"

#########################
# Usage
#########################
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Download TOGA2 genomes (2bit -> fasta) and GTF annotations, then add them to refgenie.

Options:
  -a ASSEMBLIES   Comma-separated list of assembly names to process (e.g. HLaciJub2,HLailMel2)
                  If not provided, all assemblies in the TSV are processed.
  -t TSV_FILE     Path to assemblies_and_species.tsv (default: download from TOGA2 server)
  -r REFERENCE    TOGA2 reference to use for annotations (default: reference_human_hg38)
  -c CLASS        Taxonomic class for genome downloads: Mammalia, Aves, CEC (default: Mammalia)
  -o OUTDIR       Output directory for downloaded files (default: \$PWD/toga2_downloads)
  -m METADATA     Path to genome_metadata.tsv (default: \$PWD/genome_metadata.tsv)
  -h              Show this help message

The fasta is added as refgenie asset "fasta" and the GTF as custom asset "toga_gtf".
Assembly provenance is recorded in genome_metadata.tsv.

Prerequisites:
  - conda environment with refgenie active
  - twoBitToFa (UCSC kent tools) available in PATH or via module
  - SAMtools available in PATH or via module
  - wget available
EOF
    exit 0
}
module load Java
module load SAMtools
#eval "$(conda shell.bash hook)"
#conda activate genomes
#########################
# Defaults
#########################
SELECT_ASSEMBLIES=""
TSV_FILE=""
REFERENCE="reference_human_hg38"
TAXON_CLASS="Mammalia"
OUTDIR="$PWD/toga2_downloads"
METADATA_FILE="$PWD/genome_metadata.tsv"

#########################
# Parse arguments
#########################
while getopts "a:t:r:c:o:m:h" opt; do
    case $opt in
        a) SELECT_ASSEMBLIES="$OPTARG" ;;
        t) TSV_FILE="$OPTARG" ;;
        r) REFERENCE="$OPTARG" ;;
        c) TAXON_CLASS="$OPTARG" ;;
        o) OUTDIR="$OPTARG" ;;
        m) METADATA_FILE="$OPTARG" ;;
        h) usage ;;
        *) usage ;;
    esac
done

#########################
# TOGA2 base URLs
#########################
BASE_URL="https://genome.senckenberg.de/download/TOGA2"
GENOME_BASE_URL="${BASE_URL}/Genomes/${TAXON_CLASS}"
GTF_BASE_URL="${BASE_URL}/TOGA2/${REFERENCE}"
TSV_URL="${BASE_URL}/assemblies_and_species.tsv"

GENOME_DIR="$OUTDIR/genomes"
GTF_DIR="$OUTDIR/annotations"
mkdir -p "$GENOME_DIR" "$GTF_DIR" logs

#########################
# Metadata tracking
#########################
# genome_metadata.tsv columns:
# assembly_name  species  common_name  accession  taxonomy_id  lineage  genome_source  annotation_source  annotation_reference  date_added
METADATA_HEADER="assembly_name\tspecies\tcommon_name\taccession\ttaxonomy_id\tlineage\tgenome_source\tannotation_source\tannotation_reference\tdate_added"

if [[ ! -f "$METADATA_FILE" ]]; then
    echo -e "$METADATA_HEADER" > "$METADATA_FILE"
    echo "[metadata] Created $METADATA_FILE"
fi

# Append a row to the metadata file (skip if assembly_name already present)
record_metadata() {
    local assembly_name="$1"
    local species="$2"
    local common_name="$3"
    local accession="$4"
    local taxonomy_id="$5"
    local lineage="$6"
    local genome_source="$7"
    local annotation_source="$8"
    local annotation_ref="$9"

    # Skip if already recorded
    if grep -qP "^${assembly_name}\t" "$METADATA_FILE" 2>/dev/null; then
        echo "[metadata] $assembly_name already in metadata — skipping."
        return
    fi

    local date_added
    date_added=$(date +%Y-%m-%d)

    printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$assembly_name" "$species" "$common_name" "$accession" \
        "$taxonomy_id" "$lineage" "$genome_source" "$annotation_source" \
        "$annotation_ref" "$date_added" >> "$METADATA_FILE"

    echo "[metadata] Recorded $assembly_name in $METADATA_FILE"
}

#########################
# Load modules if available
#########################
if command -v module &>/dev/null; then
    module load SAMtools 2>/dev/null || true
fi

# Check prerequisites
for cmd in wget refgenie; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd not found in PATH. Please install or load the module."
        exit 1
    fi
done

# Check for twoBitToFa
if ! command -v twoBitToFa &>/dev/null; then
    echo "ERROR: twoBitToFa not found in PATH."
    echo "Install UCSC kent tools or load the appropriate module."
    exit 1
fi

#########################
# Download or use provided TSV
#########################
if [[ -z "$TSV_FILE" ]]; then
    TSV_FILE="$OUTDIR/assemblies_and_species.tsv"
    if [[ ! -f "$TSV_FILE" ]] || [[ ! -s "$TSV_FILE" ]]; then
        echo "Downloading assemblies_and_species.tsv from TOGA2 ..."
        wget --no-check-certificate "$TSV_URL" -O "$TSV_FILE"
    fi
fi

if [[ ! -f "$TSV_FILE" ]]; then
    echo "ERROR: TSV file not found: $TSV_FILE"
    exit 1
fi

if [[ ! -s "$TSV_FILE" ]]; then
    echo "ERROR: TSV file is empty: $TSV_FILE"
    echo "       Check that the URL is reachable: $TSV_URL"
    exit 1
fi

#########################
# Build filter set
#########################
declare -A FILTER_SET
if [[ -n "$SELECT_ASSEMBLIES" ]]; then
    IFS=',' read -ra FILTER_ARRAY <<< "$SELECT_ASSEMBLIES"
    for a in "${FILTER_ARRAY[@]}"; do
        FILTER_SET["$a"]=1
    done
    echo "Will process assemblies: ${!FILTER_SET[*]}"
fi

#########################
# Process TSV
#########################
PROCESSED=0
SKIPPED=0
FAILED=0

# TOGA2 TSV columns (tab-separated):
# 1: Directory Name  2: Species  3: Common name  4: Other species names
# 5: Species Taxonomy ID  6: Taxonomic Lineage  7: Assembly name
# 8: NCBI accession  9: Source of assembly  10+: rest
while IFS=$'\t' read -r dir_name species common_name _other taxonomy_id lineage assembly_name accession _rest; do
    # Skip header
    [[ "$dir_name" == "Directory Name" ]] && continue

    # Filter by selected assemblies
    if [[ -n "$SELECT_ASSEMBLIES" ]]; then
        if [[ -z "${FILTER_SET[$assembly_name]+x}" ]]; then
            continue
        fi
    fi

    echo ""
    echo "========================================"
    echo "Processing: $assembly_name ($species - $common_name)"
    echo "  Directory: $dir_name"
    echo "========================================"

    #########################
    # 1. Download genome (2bit) and convert to fasta
    #########################
    FASTA_GZ="$GENOME_DIR/${assembly_name}.fa.gz"
    TWOBIT_FILE="$GENOME_DIR/${assembly_name}.2bit"

    if [[ -f "$FASTA_GZ" ]]; then
        echo "[genome] Already exists: $FASTA_GZ — skipping download."
    else
        GENOME_URL="${GENOME_BASE_URL}/${dir_name}/${assembly_name}.2bit"
        echo "[genome] Downloading 2bit from: $GENOME_URL"
        if ! wget -q --no-check-certificate -c "$GENOME_URL" -O "$TWOBIT_FILE"; then
            echo "[genome] WARNING: Failed to download genome for $assembly_name — skipping."
            rm -f "$TWOBIT_FILE"
            ((FAILED++)) || true
            continue
        fi

        echo "[genome] Converting 2bit -> fasta -> gzipped fasta ..."
        twoBitToFa "$TWOBIT_FILE" /dev/stdout | gzip -c > "$FASTA_GZ"
        rm -f "$TWOBIT_FILE"
        echo "[genome] Done: $FASTA_GZ"
    fi

    #########################
    # 2. Download GTF annotation
    #########################
    GTF_FILE="$GTF_DIR/${assembly_name}_toga_hg38.gtf"

    if [[ -f "$GTF_FILE" ]]; then
        echo "[gtf] Already exists: $GTF_FILE — skipping download."
    else
        GTF_URL="${GTF_BASE_URL}/${dir_name}/query_annotation.gtf.gz"
        echo "[gtf] Downloading GTF from: $GTF_URL"
        if ! wget -q --no-check-certificate -c "$GTF_URL" -O "${GTF_FILE}.gz"; then
            echo "[gtf] WARNING: Failed to download GTF for $assembly_name — skipping GTF."
            rm -f "${GTF_FILE}.gz"
        else
            gunzip -f "${GTF_FILE}.gz"
            echo "[gtf] Done: $GTF_FILE"
        fi
    fi

    #########################
    # 3. Add fasta to refgenie
    #########################
    echo "[refgenie] Building fasta asset for $assembly_name ..."
    if refgenie list -g "$assembly_name" 2>/dev/null | grep -q "fasta"; then
        echo "[refgenie] fasta asset already exists for $assembly_name — skipping."
    else
        refgenie build "${assembly_name}/fasta" --files fasta="$FASTA_GZ" \
            --genome-description "${species} (${common_name}), ${accession}" -R
        echo "[refgenie] fasta asset added."
    fi

    #########################
    # 4. Add GTF as custom toga_gtf asset
    #########################
    if [[ -f "$GTF_FILE" ]]; then
        echo "[refgenie] Adding toga_gtf asset for $assembly_name ..."
        if refgenie list -g "$assembly_name" 2>/dev/null | grep -q "toga_gtf"; then
            echo "[refgenie] toga_gtf asset already exists for $assembly_name — skipping."
        else
            refgenie add "${assembly_name}/toga_gtf" --path "$GTF_FILE" -R
            echo "[refgenie] toga_gtf asset added."
        fi
    else
        echo "[refgenie] No GTF file available for $assembly_name — skipping toga_gtf."
    fi

    #########################
    # 5. Record metadata
    #########################
    record_metadata \
        "$assembly_name" \
        "$species" \
        "$common_name" \
        "$accession" \
        "$taxonomy_id" \
        "$lineage" \
        "TOGA2 (2bit: ${GENOME_BASE_URL}/${dir_name}/)" \
        "TOGA2 (${GTF_BASE_URL}/${dir_name}/query_annotation.gtf.gz)" \
        "$REFERENCE"

    ((PROCESSED++)) || true
    echo "[done] $assembly_name complete."

done < "$TSV_FILE"

echo ""
echo "========================================"
echo "Summary: Processed=$PROCESSED, Skipped=$SKIPPED, Failed=$FAILED"
echo "Metadata: $METADATA_FILE"
echo "========================================"
echo "All done!"
