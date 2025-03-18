#!/bin/bash
# Script to fix kernel ABI header mismatches
# This solves the common problem with tools/ headers not matching arch/ headers

# Force verbose output for debugging
set -x

# Function to display script usage
usage() {
    echo "Usage: $0 <kernel_source_dir>"
    echo "Example: $0 /path/to/linux-source"
    exit 1
}

# Check if kernel directory is provided
if [ $# -lt 1 ]; then
    usage
fi

KERNEL_DIR="$1"

if [ ! -d "$KERNEL_DIR" ]; then
    echo "ERROR: Kernel directory not found: $KERNEL_DIR"
    exit 1
fi

# Enter kernel directory
cd "$KERNEL_DIR"

echo "Fixing kernel ABI header mismatches in $KERNEL_DIR (pwd: $(pwd))"

# Make sure the destination directories exist
mkdir -p tools/arch/x86/lib tools/arch/x86/include/asm

# Known problematic files that need to be synchronized
declare -a FILES_TO_SYNC=(
    "arch/x86/lib/insn.c:tools/arch/x86/lib/insn.c"
    "arch/x86/include/asm/inat.h:tools/arch/x86/include/asm/inat.h"
    "arch/x86/include/asm/insn.h:tools/arch/x86/include/asm/insn.h"
    "arch/x86/lib/inat.c:tools/arch/x86/lib/inat.c"
)

# Process each file pair
for pair in "${FILES_TO_SYNC[@]}"; do
    src="${pair%%:*}"
    dst="${pair##*:}"
    
    echo "Processing: $src -> $dst"
    
    # Check source exists
    if [ ! -f "$src" ]; then
        echo "ERROR: Source file not found: $src"
        continue
    fi
    
    # Create destination directory if needed
    dst_dir=$(dirname "$dst")
    mkdir -p "$dst_dir"
    
    # Forcefully copy the file (overwrite if exists)
    cp -vf "$src" "$dst"
    
    # Verify the copy
    if [ -f "$dst" ]; then
        echo "SUCCESS: Synchronized $dst"
    else
        echo "ERROR: Failed to synchronize $dst"
    fi
    
    # Check if files match after copy
    if cmp -s "$src" "$dst"; then
        echo "VERIFIED: Files match"
    else
        echo "ERROR: Files still don't match after copy"
        echo "Source file contents:"
        head -n 5 "$src"
        echo "Destination file contents:"
        head -n 5 "$dst"
    fi
done

echo "ABI header synchronization complete"

# List all synchronized files for verification
ls -la tools/arch/x86/lib/insn.c tools/arch/x86/lib/inat.c tools/arch/x86/include/asm/inat.h tools/arch/x86/include/asm/insn.h

exit 0