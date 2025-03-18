#!/bin/bash
# Script to fix kernel ABI header mismatches
# This solves the common problem with tools/ headers not matching arch/ headers

set -e

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

echo "Fixing kernel ABI header mismatches in $KERNEL_DIR"

# Function to sync a specific header file
sync_file() {
    local src="$1"
    local dst="$2"
    
    if [ -f "$src" ] && [ -f "$dst" ]; then
        echo "Synchronizing: $dst"
        cp -f "$src" "$dst"
        return 0
    fi
    return 1
}

# Synchronize known problematic header files
sync_file "arch/x86/lib/insn.c" "tools/arch/x86/lib/insn.c"
sync_file "arch/x86/include/asm/inat.h" "tools/arch/x86/include/asm/inat.h"
sync_file "arch/x86/include/asm/insn.h" "tools/arch/x86/include/asm/insn.h"
sync_file "arch/x86/lib/inat.c" "tools/arch/x86/lib/inat.c"

# Find all header files in tools/arch that have equivalents in arch/
echo "Performing comprehensive ABI header synchronization"
find tools/arch -type f -name "*.h" -o -name "*.c" 2>/dev/null | while read tools_file; do
    # Get the relative path and construct the corresponding arch path
    rel_path="${tools_file#tools/}"
    arch_file="$rel_path"
    
    if [ -f "$arch_file" ]; then
        # Compare the files and update if different
        if ! cmp -s "$arch_file" "$tools_file"; then
            echo "Synchronizing mismatched file: $tools_file"
            cp -f "$arch_file" "$tools_file"
        fi
    fi
done

echo "ABI header synchronization complete"
exit 0