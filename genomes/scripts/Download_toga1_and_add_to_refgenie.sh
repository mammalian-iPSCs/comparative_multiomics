#!/usr/bin/env bash
#SBATCH --job-name=toga1_refgenie
#SBATCH --output=logs/toga1_refgenie_%j.out
#SBATCH --error=logs/toga1_refgenie_%j.err
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
    module load SAMtools 2>/dev/null || true
fi

#########################
# Usage
#########################
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Download TOGA (v1) genomes + GTF annotations and add them to refgenie.
Refgenie genome names use the species name (e.g. Panthera_tigris_TOGA).

Uses the overview.table.tsv index from the TOGA server. Genomes are downloaded
from NCBI (via datasets CLI) for GCA_/GCF_ accessions, or via wget for
HTTP/FTP URLs. Assemblies with non-downloadable sources are skipped with a warning.

By default, assemblies that also exist in TOGA2 are skipped (use TOGA2 script
for those). Provide the TOGA2 assemblies_and_species.tsv via -2 to enable this.

Options:
  -a ASSEMBLIES     Comma-separated assembly names (e.g. HLaciJub2,HLailMel2)
                    If not provided, all assemblies in the TSV are processed.
  -t TSV_FILE       Path to TOGA v1 overview.table.tsv (default: download from server)
  -2 TOGA2_TSV      Path to TOGA2 assemblies_and_species.tsv — assemblies present
                    in this file are skipped (default: not set, no skipping)
  -l LOCAL_DIR      Use already-downloaded TOGA annotation data from this local dir
                    (e.g. /path/to/TOGA_annotations/download/TOGA)
  -r REFERENCE      Reference to use (default: human_hg38_reference)
  -o OUTDIR         Output directory for downloads (default: \$PWD/toga1_downloads)
  -m METADATA       Path to genome_metadata.tsv (default: \$PWD/genome_metadata.tsv)
  -g                Download genomes and add as fasta asset (default)
  -G                GTF-only mode: skip genome download, assume fasta already in refgenie
  -h                Show this help message

Fasta files are removed after successful refgenie registration.
Set CONDA_ENV_PATH at the top of this script for your environment.

Prerequisites:
  - refgenie in PATH (via CONDA_ENV_PATH)
  - SAMtools available in PATH or via module
  - datasets (NCBI) available for GCA_/GCF_ accessions
  - wget available
EOF
    exit 0
}

#########################
# Defaults
#########################
SELECT_ASSEMBLIES=""
TSV_FILE=""
TOGA2_TSV=""
LOCAL_DIR=""
REFERENCE="human_hg38_reference"
OUTDIR="$PWD/toga1_downloads"
METADATA_FILE="$PWD/genome_metadata.tsv"
DOWNLOAD_GENOMES=true

#########################
# Parse arguments
#########################
while getopts "a:t:2:l:r:o:m:gGh" opt; do
    case $opt in
        a) SELECT_ASSEMBLIES="$OPTARG" ;;
        t) TSV_FILE="$OPTARG" ;;
        2) TOGA2_TSV="$OPTARG" ;;
        l) LOCAL_DIR="$OPTARG" ;;
        r) REFERENCE="$OPTARG" ;;
        o) OUTDIR="$OPTARG" ;;
        m) METADATA_FILE="$OPTARG" ;;
        g) DOWNLOAD_GENOMES=true ;;
        G) DOWNLOAD_GENOMES=false ;;
        h) usage ;;
        *) usage ;;
    esac
done

#########################
# TOGA v1 base URL
#########################
BASE_URL="https://genome.senckenberg.de/download/TOGA"
TSV_URL="${BASE_URL}/${REFERENCE}/overview.table.tsv"

GENOME_DIR="$OUTDIR/genomes"
GTF_DIR="$OUTDIR/annotations"
TMPDIR_BASE="$OUTDIR/tmp"
mkdir -p "$GENOME_DIR" "$GTF_DIR" "$TMPDIR_BASE" logs

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

if [[ "$DOWNLOAD_GENOMES" == true ]] && ! command -v datasets &>/dev/null; then
    echo "WARNING: NCBI datasets CLI not found. GCA_/GCF_ accessions will fail."
    echo "         Install with: conda install -c conda-forge ncbi-datasets-cli"
fi

#########################
# Download or use provided TSV
#########################
if [[ -z "$TSV_FILE" ]]; then
    TSV_FILE="$OUTDIR/overview.table.tsv"
    if [[ ! -f "$TSV_FILE" ]] || [[ ! -s "$TSV_FILE" ]]; then
        echo "Downloading overview.table.tsv from TOGA server ..."
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

# Copy to local /tmp to avoid NFS stale-file-handle errors on shared clusters
LOCAL_TSV=$(mktemp /tmp/toga1_tsv.XXXXXX)
cp "$TSV_FILE" "$LOCAL_TSV"
trap 'rm -f "$LOCAL_TSV"' EXIT

#########################
# Build TOGA2 exclusion set (if provided)
# Uses dir_name column to extract assembly name — robust against column shifts
# caused by embedded tabs in the "Other species names" field.
#########################
declare -A TOGA2_SET
if [[ -n "$TOGA2_TSV" ]]; then
    if [[ ! -f "$TOGA2_TSV" ]]; then
        echo "ERROR: TOGA2 TSV not found: $TOGA2_TSV"
        exit 1
    fi
    # Normalize TOGA2 TSV line endings before parsing
    tr '\r' '\n' < "$TOGA2_TSV" | tr -s '\n' > "${TOGA2_TSV}.tmp" && mv "${TOGA2_TSV}.tmp" "$TOGA2_TSV"
    echo "Loading TOGA2 assembly list for exclusion ..."
    while IFS=$'\t' read -r dir_name _rest; do
        [[ "$dir_name" == "Directory Name" ]] && continue
        asm_name=$(echo "$dir_name" | awk -F'__' '{print $3}')
        [[ -n "$asm_name" ]] && TOGA2_SET["$asm_name"]=1
    done < "$TOGA2_TSV"
    echo "  Loaded ${#TOGA2_SET[@]} TOGA2 assemblies to exclude."
fi

#########################
# Build filter set
#########################
if [[ -n "$SELECT_ASSEMBLIES" ]]; then
    echo "Will process assemblies: $SELECT_ASSEMBLIES"
fi

#########################
# Known taxonomic order directories in TOGA v1
#########################
KNOWN_ORDERS="Afrotheria Carnivora Chiroptera Dermoptera Eulipotyphla Lagomorpha Metatheria Perissodactyla Pholidota Primates Prototheria Rodentia Ruminantia Scandentia Suina Tylopoda Whippomorpha Xenarthra"

declare -A ORDER_SET
for o in $KNOWN_ORDERS; do
    ORDER_SET["$o"]=1
done

extract_order() {
    local lineage="$1"
    IFS=';' read -ra PARTS <<< "$lineage"
    for part in "${PARTS[@]}"; do
        local trimmed
        trimmed=$(echo "$part" | xargs)
        if [[ -n "${ORDER_SET[$trimmed]+x}" ]]; then
            echo "$trimmed"
            return
        fi
    done
    echo ""
}

build_dir_name() {
    local species="$1"
    local common_name="$2"
    local assembly_name="$3"
    local sp_under="${species// /_}"
    local cn_under="${common_name// /_}"
    echo "${sp_under}__${cn_under}__${assembly_name}"
}

#########################
# Genome download function
# Handles NCBI accessions, HTTP/FTP URLs, and unknown sources
#########################
download_genome() {
    local assembly_name="$1"
    local source="$2"
    local outfile="$3"

    # Already have it
    if [[ -f "$outfile" ]]; then
        echo "[genome] Already exists: $outfile"
        return 0
    fi

    # Case 1: NCBI accession (GCA_ or GCF_)
    if [[ "$source" =~ ^GC[AF]_ ]]; then
        echo "[genome] Downloading from NCBI: $source"
        if ! command -v datasets &>/dev/null; then
            echo "[genome] ERROR: datasets CLI not available — cannot download $source"
            return 1
        fi

        local tmpdir="$TMPDIR_BASE/${assembly_name}_ncbi"
        rm -rf "$tmpdir"
        mkdir -p "$tmpdir"

        if ! datasets download genome accession "$source" \
                --include genome \
                --filename "$tmpdir/ncbi_dataset.zip" 2>/dev/null; then
            echo "[genome] WARNING: datasets download failed for $source"
            rm -rf "$tmpdir"
            return 1
        fi

        # Extract the fasta from the zip
        unzip -q -o "$tmpdir/ncbi_dataset.zip" -d "$tmpdir"
        local fasta_file
        fasta_file=$(find "$tmpdir/ncbi_dataset/data" -name "*.fna" -type f | head -1)

        if [[ -z "$fasta_file" || ! -f "$fasta_file" ]]; then
            echo "[genome] WARNING: No .fna file found in NCBI download for $source"
            rm -rf "$tmpdir"
            return 1
        fi

        gzip -c "$fasta_file" > "$outfile"
        rm -rf "$tmpdir"
        echo "[genome] Done: $outfile"
        return 0

    # Case 2: HTTP or HTTPS URL
    elif [[ "$source" =~ ^https?:// ]]; then
        echo "[genome] Downloading from URL: $source"
        local tmpdir="$TMPDIR_BASE/${assembly_name}_url"
        rm -rf "$tmpdir"
        mkdir -p "$tmpdir"
        local tmpfile="$tmpdir/download"

        if ! wget -q --no-check-certificate -c "$source" -O "$tmpfile"; then
            echo "[genome] WARNING: wget failed for $source"
            rm -rf "$tmpdir"
            return 1
        fi

        # Detect file type and extract fasta
        if file "$tmpfile" | grep -q 'Zip archive'; then
            unzip -q -o "$tmpfile" -d "$tmpdir/extracted"
            local fasta_file
            fasta_file=$(find "$tmpdir/extracted" -type f \( -name "*.fa" -o -name "*.fasta" -o -name "*.fna" -o -name "*.fa.gz" -o -name "*.fasta.gz" -o -name "*.fna.gz" \) | head -1)
            if [[ -z "$fasta_file" ]]; then
                echo "[genome] WARNING: No fasta file found in downloaded zip from $source"
                rm -rf "$tmpdir"
                return 1
            fi
            if [[ "$fasta_file" =~ \.gz$ ]]; then
                cp "$fasta_file" "$outfile"
            else
                gzip -c "$fasta_file" > "$outfile"
            fi
        elif file "$tmpfile" | grep -q 'gzip'; then
            cp "$tmpfile" "$outfile"
        else
            # Assume plain fasta
            gzip -c "$tmpfile" > "$outfile"
        fi

        rm -rf "$tmpdir"
        echo "[genome] Done: $outfile"
        return 0

    # Case 3: FTP URL
    elif [[ "$source" =~ ^ftp:// ]]; then
        echo "[genome] Downloading from FTP: $source"
        local tmpdir="$TMPDIR_BASE/${assembly_name}_ftp"
        rm -rf "$tmpdir"
        mkdir -p "$tmpdir"

        # Try to get fasta files from the FTP directory
        if ! wget -q -r -np -nd -A "*.fa.gz,*.fasta.gz,*.fna.gz,*.fa,*.fasta,*.fna" \
                -P "$tmpdir" "$source" 2>/dev/null; then
            echo "[genome] WARNING: FTP download failed for $source"
            rm -rf "$tmpdir"
            return 1
        fi

        local fasta_file
        fasta_file=$(find "$tmpdir" -type f \( -name "*.fa" -o -name "*.fasta" -o -name "*.fna" -o -name "*.fa.gz" -o -name "*.fasta.gz" -o -name "*.fna.gz" \) | head -1)
        if [[ -z "$fasta_file" ]]; then
            echo "[genome] WARNING: No fasta file found from FTP: $source"
            rm -rf "$tmpdir"
            return 1
        fi
        if [[ "$fasta_file" =~ \.gz$ ]]; then
            cp "$fasta_file" "$outfile"
        else
            gzip -c "$fasta_file" > "$outfile"
        fi

        rm -rf "$tmpdir"
        echo "[genome] Done: $outfile"
        return 0

    # Case 4: Unknown source (plain text like "DNA Zoo Consortium")
    else
        echo "[genome] WARNING: Cannot auto-download from source: '$source'"
        echo "[genome]          Manual download required for $assembly_name."
        return 1
    fi
}

#########################
# Process TSV
#########################
PROCESSED=0
SKIPPED=0
FAILED=0

# TOGA v1 TSV columns (tab-separated):
# 1: Species             (e.g. Acinonyx jubatus)
# 2: Common name         (e.g. cheetah)
# 3: Species Taxonomy ID
# 4: Taxonomic Lineage   (e.g. Mammalia; Theria; ...; Carnivora; ...)
# 5: Assembly name       (e.g. HLaciJub2)
# 6: NCBI accession / source
# 7: contig N50 (bp)
# 8: scaffold N50 (bp)
while IFS=$'\t' read -r species common_name taxonomy_id lineage assembly_name accession _contig_n50 _scaffold_n50; do
    # Skip header
    [[ "$species" == "Species" ]] && continue

    # Filter by selected assemblies
    if [[ -n "$SELECT_ASSEMBLIES" ]]; then
        if ! echo ",$SELECT_ASSEMBLIES," | grep -qF ",$assembly_name,"; then
            continue
        fi
    fi

    # Skip if assembly exists in TOGA2
    if [[ -n "$TOGA2_TSV" ]] && [[ -n "${TOGA2_SET[$assembly_name]+x}" ]]; then
        echo "[skip] $assembly_name — present in TOGA2 (use TOGA2 script instead)"
        continue
    fi

    # Resolve taxonomic order
    order=$(extract_order "$lineage")
    if [[ -z "$order" ]]; then
        echo "[skip] $assembly_name — could not determine order from lineage: $lineage"
        ((SKIPPED++)) || true
        continue
    fi

    # Build directory name
    dir_name=$(build_dir_name "$species" "$common_name" "$assembly_name")

    # Human-readable refgenie genome name (e.g. Panthera_tigris_TOGA)
    refgenie_name=$(echo "$species" | tr ' ' '_')_TOGA

    echo ""
    echo "========================================"
    echo "Processing: $assembly_name ($species - $common_name)"
    echo "  Refgenie name: $refgenie_name"
    echo "  Order: $order | Source: $accession"
    echo "  Directory: $dir_name"
    echo "========================================"

    #########################
    # 1. Download genome (if enabled)
    #########################
    FASTA_GZ="$GENOME_DIR/${assembly_name}.fa.gz"
    GENOME_OK=false
    GENOME_SOURCE="none"

    if [[ "$DOWNLOAD_GENOMES" == true ]]; then
        # Check if fasta already in refgenie
        if refgenie list -g "$refgenie_name" 2>/dev/null | grep -q "fasta"; then
            echo "[genome] fasta already in refgenie for $refgenie_name — skipping download."
            GENOME_OK=true
            GENOME_SOURCE="already in refgenie"
        elif download_genome "$assembly_name" "$accession" "$FASTA_GZ"; then
            GENOME_OK=true
            # Determine source type for metadata
            if [[ "$accession" =~ ^GC[AF]_ ]]; then
                GENOME_SOURCE="NCBI ($accession)"
            elif [[ "$accession" =~ ^https?:// ]]; then
                GENOME_SOURCE="URL ($accession)"
            elif [[ "$accession" =~ ^ftp:// ]]; then
                GENOME_SOURCE="FTP ($accession)"
            else
                GENOME_SOURCE="$accession"
            fi
        else
            echo "[genome] Could not obtain genome for $assembly_name — continuing with GTF only."
            GENOME_SOURCE="FAILED ($accession)"
        fi
    else
        # -G mode: just check refgenie
        if refgenie list -g "$refgenie_name" 2>/dev/null | grep -q "fasta"; then
            GENOME_OK=true
            GENOME_SOURCE="already in refgenie"
        else
            echo "[skip] $refgenie_name — no fasta in refgenie and genome download disabled (-G)"
            ((SKIPPED++)) || true
            continue
        fi
    fi

    #########################
    # 2. Add fasta to refgenie (if downloaded and not already there), then clean up
    #########################
    if [[ "$GENOME_OK" == true ]] && [[ -f "$FASTA_GZ" ]]; then
        if ! refgenie list -g "$refgenie_name" 2>/dev/null | grep -q "fasta"; then
            echo "[refgenie] Building fasta asset for $refgenie_name ..."
            refgenie build "${refgenie_name}/fasta" --files fasta="$FASTA_GZ" \
                --genome-description "${species} (${common_name}), ${accession}" -R
            echo "[refgenie] fasta asset added."
            rm -f "$FASTA_GZ"
            echo "[cleanup] Removed $FASTA_GZ"
        fi
    fi

    #########################
    # 3. Get GTF annotation
    #########################
    # Check if toga_gtf already exists
    if refgenie list -g "$refgenie_name" 2>/dev/null | grep -q "toga_gtf"; then
        echo "[refgenie] toga_gtf already exists for $refgenie_name — skipping."
        # Still record metadata if not yet recorded
        record_metadata \
            "$assembly_name" "$species" "$common_name" "$accession" \
            "$taxonomy_id" "$lineage" "$GENOME_SOURCE" \
            "TOGA v1 (already in refgenie)" "$REFERENCE"
        ((SKIPPED++)) || true
        continue
    fi

    GTF_FILE="$GTF_DIR/${assembly_name}_toga_hg38.gtf"
    ANNOTATION_SOURCE=""

    if [[ -f "$GTF_FILE" ]]; then
        echo "[gtf] Already exists locally: $GTF_FILE"
        ANNOTATION_SOURCE="TOGA v1 (local: $GTF_FILE)"
    elif [[ -n "$LOCAL_DIR" ]]; then
        LOCAL_GTF="$LOCAL_DIR/$REFERENCE/$order/$dir_name/geneAnnotation.gtf.gz"
        if [[ -f "$LOCAL_GTF" ]]; then
            echo "[gtf] Extracting from local: $LOCAL_GTF"
            gunzip -c "$LOCAL_GTF" > "$GTF_FILE"
            ANNOTATION_SOURCE="TOGA v1 (local: $LOCAL_GTF)"
        else
            echo "[gtf] WARNING: GTF not found at $LOCAL_GTF — skipping."
            ((FAILED++)) || true
            continue
        fi
    else
        GTF_URL="${BASE_URL}/${REFERENCE}/${order}/${dir_name}/geneAnnotation.gtf.gz"
        echo "[gtf] Downloading from: $GTF_URL"
        if ! wget -q --no-check-certificate -c "$GTF_URL" -O "${GTF_FILE}.gz"; then
            echo "[gtf] WARNING: Failed to download GTF for $assembly_name — skipping."
            rm -f "${GTF_FILE}.gz"
            ((FAILED++)) || true
            continue
        fi
        gunzip -f "${GTF_FILE}.gz"
        ANNOTATION_SOURCE="TOGA v1 ($GTF_URL)"
    fi

    #########################
    # 4. Add GTF to refgenie as toga_gtf
    #########################
    if [[ -f "$GTF_FILE" ]]; then
        echo "[refgenie] Adding toga_gtf asset for $refgenie_name ..."
        refgenie add "${refgenie_name}/toga_gtf" --path "$GTF_FILE" -R
        echo "[refgenie] toga_gtf asset added."
        ((PROCESSED++)) || true
    else
        echo "[refgenie] GTF file missing — skipping."
        ((FAILED++)) || true
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
        "$GENOME_SOURCE" \
        "$ANNOTATION_SOURCE" \
        "$REFERENCE"

    echo "[done] $assembly_name complete."

done < "$LOCAL_TSV"

# Clean up tmp directory
rm -rf "$TMPDIR_BASE"

echo ""
echo "========================================"
echo "Summary: Processed=$PROCESSED, Skipped=$SKIPPED, Failed=$FAILED"
echo "Metadata: $METADATA_FILE"
echo "========================================"
echo "All done!"
