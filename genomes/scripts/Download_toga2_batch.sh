#!/bin/bash
# Submit one SLURM job per assembly for TOGA2 download + refgenie registration.
#
# Usage:
#   ./Download_toga2_batch.sh HLaciJub2,HLailMel2,HLaddNas1
#   ./Download_toga2_batch.sh            # processes ALL assemblies (careful!)
#
# Optional env vars:
#   GTF_ONLY=1   Pass -G flag (add GTF to existing assembly, skip genome download)

set -euo pipefail

ASSEMBLIES="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="$(dirname "$SCRIPT_DIR")/toga2_downloads"
METADATA_FILE="$(dirname "$SCRIPT_DIR")/genome_metadata.tsv"
TSV_FILE="$OUTDIR/assemblies_and_species.tsv"

mkdir -p "$OUTDIR" logs

if [[ -z "$ASSEMBLIES" ]]; then
    echo "WARNING: No assemblies specified — this will process ALL ~700+ species!"
    echo "Press Ctrl+C within 5s to cancel..."
    sleep 5
fi

# Download and normalize TSV once, then pass to each job via -t.
# This avoids parallel jobs racing to modify the same NFS file simultaneously.
if [[ ! -f "$TSV_FILE" ]] || [[ ! -s "$TSV_FILE" ]]; then
    echo "Downloading assemblies_and_species.tsv ..."
    wget --no-check-certificate \
        "https://genome.senckenberg.de/download/TOGA2/assemblies_and_species.tsv" \
        -O "$TSV_FILE"
    tr '\r' '\n' < "$TSV_FILE" | tr -s '\n' > "${TSV_FILE}.tmp" && mv "${TSV_FILE}.tmp" "$TSV_FILE"
fi

# Build optional flags
EXTRA_FLAGS="-t $TSV_FILE"
if [[ -n "${GTF_ONLY:-}" ]]; then
    EXTRA_FLAGS="$EXTRA_FLAGS -G"
fi

# Submit one job per assembly so they can run in parallel
if [[ -n "$ASSEMBLIES" ]]; then
    IFS=',' read -ra ASSEMBLY_ARRAY <<< "$ASSEMBLIES"
    for asm in "${ASSEMBLY_ARRAY[@]}"; do
        sbatch --job-name="toga2_${asm}" \
               --output="logs/toga2_${asm}_%j.out" \
               --error="logs/toga2_${asm}_%j.err" \
               "$SCRIPT_DIR/Download_toga2_and_add_to_refgenie.sh" \
               -a "$asm" -o "$OUTDIR" -m "$METADATA_FILE" $EXTRA_FLAGS
        echo "Submitted job for $asm"
    done
else
    # Single job for all assemblies
    sbatch --job-name="toga2_all" \
           --output="logs/toga2_all_%j.out" \
           --error="logs/toga2_all_%j.err" \
           "$SCRIPT_DIR/Download_toga2_and_add_to_refgenie.sh" \
           -o "$OUTDIR" -m "$METADATA_FILE" $EXTRA_FLAGS
    echo "Submitted single job for all assemblies"
fi
