#!/bin/bash
# Submit one SLURM job per assembly for TOGA2 download + refgenie registration.
#
# Usage:
#   ./Download_toga2_batch.sh HLaciJub2,HLailMel2,HLaddNas1
#   ./Download_toga2_batch.sh            # processes ALL assemblies (careful!)

set -euo pipefail

ASSEMBLIES="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="$(dirname "$SCRIPT_DIR")/toga2_downloads"
METADATA_FILE="$(dirname "$SCRIPT_DIR")/genome_metadata.tsv"

mkdir -p logs

if [[ -z "$ASSEMBLIES" ]]; then
    echo "WARNING: No assemblies specified — this will process ALL ~700+ species!"
    echo "Press Ctrl+C within 5s to cancel..."
    sleep 5
fi

# Submit one job per assembly so they can run in parallel
if [[ -n "$ASSEMBLIES" ]]; then
    IFS=',' read -ra ASSEMBLY_ARRAY <<< "$ASSEMBLIES"
    for asm in "${ASSEMBLY_ARRAY[@]}"; do
        sbatch --job-name="toga2_${asm}" \
               --output="logs/toga2_${asm}_%j.out" \
               --error="logs/toga2_${asm}_%j.err" \
               "$SCRIPT_DIR/Download_toga2_and_add_to_refgenie.sh" \
               -a "$asm" -o "$OUTDIR" -m "$METADATA_FILE"
        echo "Submitted job for $asm"
    done
else
    # Single job for all assemblies
    sbatch --job-name="toga2_all" \
           --output="logs/toga2_all_%j.out" \
           --error="logs/toga2_all_%j.err" \
           "$SCRIPT_DIR/Download_toga2_and_add_to_refgenie.sh" \
           -o "$OUTDIR" -m "$METADATA_FILE"
    echo "Submitted single job for all assemblies"
fi
