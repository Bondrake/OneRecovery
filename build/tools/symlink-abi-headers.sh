#!/bin/bash
# Create symlinks for kernel ABI headers
# This directly creates symlinks without using patches

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

echo "Creating symlinks for ABI header files in $KERNEL_DIR"

# Make sure the destination directories exist
mkdir -p tools/arch/x86/lib tools/arch/x86/include/asm

# Define files to symlink
declare -a SYMLINKS=(
    "arch/x86/lib/insn.c:tools/arch/x86/lib/insn.c"
    "arch/x86/include/asm/inat.h:tools/arch/x86/include/asm/inat.h"
    "arch/x86/include/asm/insn.h:tools/arch/x86/include/asm/insn.h"
    "arch/x86/lib/inat.c:tools/arch/x86/lib/inat.c"
)

# Create each symlink
for pair in "${SYMLINKS[@]}"; do
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
    
    # Remove existing file if it exists
    rm -f "$dst"
    
    # Create the symlink
    # Use relative path for the symlink to make it more relocatable
    rel_path=$(echo "$src" | sed -e "s#^.*/\([^/]*/[^/]*/[^/]*/\)#../../../../\1#")
    ln -sf "$rel_path" "$dst"
    
    # Verify the symlink
    if [ -L "$dst" ]; then
        target=$(readlink "$dst")
        echo "SUCCESS: Created symlink $dst -> $target"
    else
        echo "ERROR: Failed to create symlink for $dst"
    fi
done

echo "ABI header symlinks created successfully"
exit 0