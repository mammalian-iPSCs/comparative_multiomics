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
# User-configurable paths — edit these for your environment
#########################
CONDA_ENV_PATH="/home/groups/compgen/lwange/.conda/envs/genomes/bin"
UCSC_BIN_PATH="/home/groups/compgen/lwange/ucsc-bin-env/bin"
export PATH="${CONDA_ENV_PATH}:${UCSC_BIN_PATH}:$PATH"

#########################
# Load cluster modules if available
#########################
if command -v module &>/dev/null; then
    module load Java   2>/dev/null || true
    module load SAMtools 2>/dev/null || true
fi

#########################
# Usage
#########################
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Download TOGA2 genomes (2bit -> fasta) and GTF annotations, then add them to refgenie.
Refgenie genome names use the species name (e.g. Panthera_tigris_TOGA) rather than
the internal assembly code.

Options:
  -a ASSEMBLIES   Comma-separated list of assembly names (e.g. HLaciJub2,HLailMel2)
                  If not provided, all assemblies in the TSV are processed.
  -t TSV_FILE     Path to assemblies_and_species.tsv (default: download from TOGA2 server)
  -r REFERENCE    TOGA2 reference to use for annotations (default: reference_human_hg38)
  -c CLASS        Taxonomic class: Mammalia, Aves, CEC (default: Mammalia)
  -o OUTDIR       Output directory for downloaded files (default: \$PWD/toga2_downloads)
  -m METADATA     Path to genome_metadata.tsv (default: \$PWD/genome_metadata.tsv)
  -G              GTF-only mode: skip genome download, assume fasta already in refgenie
  -h              Show this help message

Refgenie genome name is derived from species name: e.g. Panthera_tigris_TOGA.
Fasta files are removed after successful refgenie registration.
Set CONDA_ENV_PATH and UCSC_BIN_PATH at the top of this script for your environment.

Prerequisites:
  - refgenie in PATH (via CONDA_ENV_PATH)
  - twoBitToFa (UCSC kent tools, via UCSC_BIN_PATH)
  - SAMtools available in PATH or via module
  - wget available
EOF
    exit 0
}

#########################
# Defaults
#########################
SELECT_ASSEMBLIES=""
TSV_FILE=""
REFERENCE="reference_human_hg38"
TAXON_CLASS="Mammalia"
OUTDIR="$PWD/toga2_downloads"
METADATA_FILE="$PWD/genome_metadata.tsv"
DOWNLOAD_GENOMES=true

#########################
# Parse arguments
#########################
while getopts "a:t:r:c:o:m:Gh" opt; do
    case $opt in
        a) SELECT_ASSEMBLIES="$OPTARG" ;;
        t) TSV_FILE="$OPTARG" ;;
        r) REFERENCE="$OPTARG" ;;
        c) TAXON_CLASS="$OPTARG" ;;
        o) OUTDIR="$OPTARG" ;;
        m) METADATA_FILE="$OPTARG" ;;
        G) DOWNLOAD_GENOMES=false ;;
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

record_metadata() {
    local assembly_name="$1" species="$2" common_name="$3" accession="$4"
    local taxonomy_id="$5" lineage="$6" genome_source="$7"
    local annotation_source="$8" annotation_ref="$9"

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
# Check prerequisites
#########################
for cmd in wget refgenie; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd not found in PATH."
        echo "       Set CONDA_ENV_PATH at the top of this script to your conda env."
        exit 1
    fi
done

if [[ "$DOWNLOAD_GENOMES" == true ]] && ! command -v twoBitToFa &>/dev/null; then
    echo "ERROR: twoBitToFa not found in PATH."
    echo "       Set UCSC_BIN_PATH at the top of this script to your UCSC tools directory."
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

# Normalize line endings (\r\n or \r-only -> \n)
tr '\r' '\n' < "$TSV_FILE" | tr -s '\n' > "${TSV_FILE}.tmp" && mv "${TSV_FILE}.tmp" "$TSV_FILE"

# Copy to local /tmp to avoid NFS stale-file-handle errors on shared clusters
LOCAL_TSV=$(mktemp /tmp/toga2_tsv.XXXXXX)
cp "$TSV_FILE" "$LOCAL_TSV"
trap 'rm -f "$LOCAL_TSV"' EXIT

#########################
# Build filter set
#########################
if [[ -n "$SELECT_ASSEMBLIES" ]]; then
    echo "Will process assemblies: $SELECT_ASSEMBLIES"
fi

#########################
# Process TSV
#########################
PROCESSED=0
SKIPPED=0
FAILED=0

# TOGA2 TSV: tab-separated, \r-only line endings (normalized above).
# dir_name format: Species__common_name__HLassembly__accession
# "Other species names" column may contain embedded tabs — only name the first
# three fields and derive assembly_name/accession from dir_name instead.
while IFS=$'\t' read -r dir_name species common_name _rest; do
    [[ "$dir_name" == "Directory Name" ]] && continue

    assembly_name=$(echo "$dir_name" | awk -F'__' '{print $3}')
    accession=$(echo "$dir_name"     | awk -F'__' '{print $4}')
    [[ -z "$assembly_name" ]] && continue

    if [[ -n "$SELECT_ASSEMBLIES" ]]; then
        if ! echo ",$SELECT_ASSEMBLIES," | grep -qF ",$assembly_name,"; then
            continue
        fi
    fi

    # Human-readable refgenie genome name (e.g. Panthera_tigris_TOGA)
    refgenie_name=$(echo "$species" | tr ' ' '_')_TOGA

    echo ""
    echo "========================================"
    echo "Processing: $assembly_name ($species - $common_name)"
    echo "  Refgenie name: $refgenie_name"
    echo "  Directory: $dir_name"
    echo "========================================"

    #########################
    # 1. Download genome (2bit) and convert to fasta
    #########################
    FASTA_GZ="$GENOME_DIR/${assembly_name}.fa.gz"
    TWOBIT_FILE="$GENOME_DIR/${assembly_name}.2bit"

    if [[ "$DOWNLOAD_GENOMES" == true ]]; then
        if refgenie list -g "$refgenie_name" 2>/dev/null | grep -q "fasta"; then
            echo "[genome] fasta already in refgenie for $refgenie_name — skipping download."
        elif [[ -f "$FASTA_GZ" ]]; then
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
        # 2. Add fasta to refgenie, then clean up
        #########################
        if [[ -f "$FASTA_GZ" ]]; then
            if refgenie list -g "$refgenie_name" 2>/dev/null | grep -q "fasta"; then
                echo "[refgenie] fasta already exists for $refgenie_name — skipping build."
            else
                echo "[refgenie] Building fasta asset for $refgenie_name ..."
                refgenie build "${refgenie_name}/fasta" --files fasta="$FASTA_GZ" \
                    --genome-description "${species} (${common_name}), ${accession}" -R
                echo "[refgenie] fasta asset added."
                rm -f "$FASTA_GZ"
                echo "[cleanup] Removed $FASTA_GZ"
            fi
        fi
    else
        # -G mode: GTF only — require fasta already in refgenie
        if ! refgenie list -g "$refgenie_name" 2>/dev/null | grep -q "fasta"; then
            echo "[skip] $refgenie_name — no fasta in refgenie and genome download disabled (-G)"
            ((SKIPPED++)) || true
            continue
        fi
        echo "[genome] -G mode: using existing fasta for $refgenie_name"
    fi

    #########################
    # 3. Download GTF annotation
    #########################
    GTF_FILE="$GTF_DIR/${assembly_name}_toga2_hg38.gtf"

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
    # 4. Add GTF as custom toga_gtf asset
    #########################
    if [[ -f "$GTF_FILE" ]]; then
        if refgenie list -g "$refgenie_name" 2>/dev/null | grep -q "toga_gtf"; then
            echo "[refgenie] toga_gtf already exists for $refgenie_name — skipping."
        else
            echo "[refgenie] Adding toga_gtf asset for $refgenie_name ..."
            refgenie add "${refgenie_name}/toga_gtf" --path "$GTF_FILE" -R
            echo "[refgenie] toga_gtf asset added."
        fi
    else
        echo "[refgenie] No GTF file available for $assembly_name — skipping toga_gtf."
    fi

    #########################
    # 5. Record metadata
    #########################
    record_metadata \
        "$assembly_name" "$species" "$common_name" "$accession" \
        "" "" \
        "TOGA2 (2bit: ${GENOME_BASE_URL}/${dir_name}/)" \
        "TOGA2 (${GTF_BASE_URL}/${dir_name}/query_annotation.gtf.gz)" \
        "$REFERENCE"

    ((PROCESSED++)) || true
    echo "[done] $assembly_name complete."

done < "$LOCAL_TSV"

echo ""
echo "========================================"
echo "Summary: Processed=$PROCESSED, Skipped=$SKIPPED, Failed=$FAILED"
echo "Metadata: $METADATA_FILE"
echo "========================================"
echo "All done!"
