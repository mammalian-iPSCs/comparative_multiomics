#!/bin/bash
# Submit one SLURM job per assembly for TOGA1 download + refgenie registration.
#
# Usage:
#   ./Download_toga1_batch.sh HLaciJub2,HLailMel2,HLaddNas1
#   ./Download_toga1_batch.sh            # processes ALL assemblies (careful!)
#
# Optional env vars passed through to the per-assembly script:
#   TOGA2_TSV   Path to TOGA2 assemblies_and_species.tsv for exclusion (-2 flag)
#   LOCAL_DIR   Path to local TOGA annotation directory (-l flag)

set -euo pipefail

ASSEMBLIES="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OUTDIR="$(dirname "$SCRIPT_DIR")/toga1_downloads"
METADATA_FILE="$(dirname "$SCRIPT_DIR")/genome_metadata.tsv"

mkdir -p logs

if [[ -z "$ASSEMBLIES" ]]; then
    echo "WARNING: No assemblies specified — this will process ALL assemblies in the TSV!"
    echo "Press Ctrl+C within 5s to cancel..."
    sleep 5
fi

# Build optional flags to pass through
EXTRA_FLAGS=""
if [[ -n "${TOGA2_TSV:-}" ]]; then
    EXTRA_FLAGS="$EXTRA_FLAGS -2 $TOGA2_TSV"
fi
if [[ -n "${LOCAL_DIR:-}" ]]; then
    EXTRA_FLAGS="$EXTRA_FLAGS -l $LOCAL_DIR"
fi

# Submit one job per assembly so they can run in parallel
if [[ -n "$ASSEMBLIES" ]]; then
    IFS=',' read -ra ASSEMBLY_ARRAY <<< "$ASSEMBLIES"
    for asm in "${ASSEMBLY_ARRAY[@]}"; do
        sbatch --job-name="toga1_${asm}" \
               --output="logs/toga1_${asm}_%j.out" \
               --error="logs/toga1_${asm}_%j.err" \
               "$SCRIPT_DIR/Download_toga1_and_add_to_refgenie.sh" \
               -a "$asm" -o "$OUTDIR" -m "$METADATA_FILE" $EXTRA_FLAGS
        echo "Submitted job for $asm"
    done
else
    # Single job for all assemblies
    sbatch --job-name="toga1_all" \
           --output="logs/toga1_all_%j.out" \
           --error="logs/toga1_all_%j.err" \
           "$SCRIPT_DIR/Download_toga1_and_add_to_refgenie.sh" \
           -o "$OUTDIR" -m "$METADATA_FILE" $EXTRA_FLAGS
    echo "Submitted single job for all assemblies"
fi
