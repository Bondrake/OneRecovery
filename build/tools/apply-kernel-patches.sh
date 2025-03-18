#!/bin/bash
# Apply custom kernel patches to fix common issues

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
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCH_DIR="$SCRIPT_DIR/custom-kernel-patches"

if [ ! -d "$KERNEL_DIR" ]; then
    echo "ERROR: Kernel directory not found: $KERNEL_DIR"
    exit 1
fi

if [ ! -d "$PATCH_DIR" ]; then
    echo "ERROR: Patch directory not found: $PATCH_DIR"
    mkdir -p "$PATCH_DIR"
    echo "Created empty patch directory: $PATCH_DIR"
    echo "Please add patches to this directory before running this script."
    exit 1
fi

# Enter kernel directory
cd "$KERNEL_DIR"

echo "Applying kernel patches from $PATCH_DIR"

# List all patches
PATCHES=$(find "$PATCH_DIR" -name "*.patch" | sort)

if [ -z "$PATCHES" ]; then
    echo "No patches found in $PATCH_DIR"
    exit 0
fi

# Apply each patch
for patch in $PATCHES; do
    patch_name=$(basename "$patch")
    echo "Applying patch: $patch_name"
    
    # Try to apply the patch, but don't fail if it's already applied
    if patch -p1 --dry-run < "$patch" &>/dev/null; then
        patch -p1 < "$patch"
        echo "Successfully applied: $patch_name"
    else
        # Check if patch is already applied
        if patch -p1 --reverse --dry-run < "$patch" &>/dev/null; then
            echo "Patch already applied: $patch_name"
        else
            echo "ERROR: Failed to apply patch: $patch_name"
            echo "The patch may need to be updated for this kernel version."
            exit 1
        fi
    fi
done

echo "All patches applied successfully"
exit 0