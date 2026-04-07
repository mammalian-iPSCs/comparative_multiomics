#!/bin/bash
#SBATCH --job-name=refgenie_add_asset   # Job name
#SBATCH --output=refgenie_add_asset_%j.out  # Standard output log (with job ID)
#SBATCH --error=refgenie_add_asset_%j.err   # Standard error log (with job ID)
#SBATCH --ntasks=1                 # Number of tasks (typically 1 for bash scripts)
#SBATCH --cpus-per-task=10          # Number of CPU cores to use
#SBATCH --mem=150G                   # Memory allocation (adjust as needed)
#SBATCH --partition=genD       # Partition to use (adjust to your cluster's config)

# Enable strict error checking
set -euo pipefail


threads=${SLURM_CPUS_PER_TASK:-1}  # Default to 1 if not set
# Get RAM allocation in GB
# for STAR Genome Indexing the memory allocation was buggy so I specifically specify it here
if [[ -n "$SLURM_MEM_PER_NODE" ]]; then
    ram=$(( SLURM_MEM_PER_NODE * 1024 * 1024))th
elif [[ -n "$SLURM_MEM_PER_CPU" ]]; then
    ram=$(( (SLURM_MEM_PER_CPU * threads) * 1024 * 1024 ))
else
    ram=0
fi
ram=$(echo "$ram" | tr -cd '0-9')

# Now do the calculation (80% of RAM)
availRAM=$(awk "BEGIN { printf \"%.0f\", $ram * 0.8 }")
echo "Threads: $threads"
echo "RAM:     ${availRAM}B"
echo "version 1.5"
# Input arguments
alias=$1
assets=$2 
tag=$3
if [ "${4:-}" ]; then
    path=$(ls -d "$4")
else
    path=""
fi
# Check if the mandatory arguments are provided
if [ -z "$alias" ] || [ -z "$assets" ]; then
    echo "Usage: $0 <alias> <assets> [path] [tag]"
    exit 1
fi

## Add more assets when needed

IFS=',' read -r -a asset_array <<< "$assets"

# Check existing genomes and assets in refgenie
echo "Checking existing genomes and assets in refgenie..."
refgenie list -g $alias

for asset in "${asset_array[@]}"; do
    if [ "$asset" = "bowtie2_index" ]; then
        # Load required modules
        echo "Loading Bowtie2 module..."
        module load Bowtie2

        # Run refgenie build
        echo "Building refgenie $asset for alias: $alias"
        refgenie build "$alias/$asset:$tag" --files fasta="$alias/fasta" -R

        echo "Bowtie2 index build done!"
    fi

    if [ "$asset" = "star_index" ]; then
        # Load required modules
        echo "Loading STAR module..."
        module load STAR

        ## calculate genomeChrBinNbits
        contigs=$( refgenie seek $alias/fasta:$tag | sed 's/\.fa$/.chrom.sizes/' | xargs wc -l | awk '{print $1}')
        genome=$(awk '{sum += $2} END {print sum}' "$(refgenie seek $alias/fasta:$tag | sed 's/\.fa$/.chrom.sizes/')")
        echo "contigs: $contigs"
        echo "genome: $genome"
        adj_value=$(echo "$genome / $contigs" | bc)
        # Ensure adj_value is computed correctly
        if [ "$(echo "$adj_value < 150" | bc)" -eq 1 ]; then
            adj_value=150
        fi
        # Compute genomeChrBinNbits correctly
        genomeChrBinNbits=$(echo "scale=10; l($adj_value)/l(2)" | bc -l | awk '{printf "%.0f", ($1 < 18 ? $1 : 18)}')

        echo "genomeChrBinNbits: $genomeChrBinNbits"

        # Run refgenie build
        echo "Building refgenie $asset for alias: $alias"
        refgenie build "$alias/$asset:$tag" --files fasta="$alias/fasta:$tag" --params threads=$threads --params genomeChrBinNbits=$genomeChrBinNbits --params limitGenomeGenerateRAM=$availRAM -R -N

        echo "STAR index build done!"
    fi

    if [ "$asset" = "gencode_gtf" ]; then
    # Step 1: Use provided path if available
    if [ -n "$path" ]; then
        echo "Using provided path: $path"
        gtf_file="$path"
    else
        # Step 2: If no path, look for a .gtf file
        echo "No path provided. Looking for a .gtf file..."
        gtf_file=$(find "$alias" -type f -name "*.gtf" | head -n 1)

        if [ -z "$gtf_file" ]; then
            echo "No .gtf file found, looking for a .gff file..."
            
            # Step 3: If no GTF, look for a GFF file
            gff_file=$(find "$alias" -type f -name "*.gff" | head -n 1)

            if [ -z "$gff_file" ]; then
                echo "No .gtf, .gff, or path provided for alias: $alias"
                exit 1
            else
                # Step 4: Convert GFF to GTF using gffread
                gtf_file="${gff_file}.gtf"
                echo "Converting $gff_file to GTF..."
                gffread -E -T --t-adopt --gene2exon --force-exons -o "$gtf_file" "$gff_file"
            fi
        else
            echo "Using found GTF file: $gtf_file"
        fi
    fi

    # Step 5: Ensure the GTF file exists after conversion or assignment
    if [ ! -f "$gtf_file" ]; then
        echo "GTF file generation failed!"
        exit 1
    fi

    # Step 6: Compress the GTF file
    echo "Compressing GTF file..."
    gzip -f "$gtf_file"
    gtf_file_gz="${gtf_file}.gz"

    if [ ! -f "$gtf_file_gz" ]; then
        echo "GTF file compression failed!"
        exit 1
    fi

    # Step 7: Build the refgenie asset
    echo "Building refgenie $asset for alias: $alias"
    refgenie build "$alias/$asset:$tag" --files gencode_gtf="$gtf_file_gz" -R -N

    echo "GENCODE GTF build done!"
    fi


    if [ "$asset" = "toga_gtf" ]; then
        ## this adds custom assets like in this case gtf files produced by TOGA
        # Check if path is provided
        if [ -z "$path" ]; then
            echo "Path for TOGA GTF directory not provided!"
            exit 1
        fi
            # Run refgenie add
        echo "Adding refgenie $asset for alias: $alias"
        refgenie add "$alias/$asset:$tag" --path "$path" -R

        echo "Custom asset has been added!"
    fi
done

 # Check if the asset has been added correctly to refgenie
echo "Checking if the asset has been added correctly to refgenie..."
refgenie list -g $alias

echo "All done!"
# End of script