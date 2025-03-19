#!/bin/bash
#
# OneFileLinux cleanup script
# Removes build artifacts and temporary files
#

# Define script name for error handling
SCRIPT_NAME=$(basename "$0")

# Source the core library first (required)
if [ ! -f "./80_common.sh" ]; then
    echo "ERROR: Critical library file not found: ./80_common.sh"
    exit 1
fi
source ./80_common.sh

# Source all library scripts using the source_libraries function
source_libraries "."

# Initialize script with standard header (prints banner)
initialize_script

# Confirm cleanup with the user
if [ "${FORCE_CLEANUP:-false}" != "true" ]; then
    read -p "This will remove all build artifacts. Are you sure? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Cleanup cancelled by user"
        exit 0
    fi
fi

log "INFO" "Cleaning up build artifacts..."

# Clean up Alpine minirootfs
if [ -d "alpine-minirootfs" ] || [ -f "alpine-minirootfs*.tar.gz" ]; then
    log "INFO" "Removing Alpine minirootfs..."
    rm -rf alpine-minirootfs*
fi

# Clean up Linux kernel source
if [ -d "linux" ] || [ -d "linux-*" ] || [ -f "linux-*.tar.xz" ]; then
    log "INFO" "Removing Linux kernel source..."
    rm -rf linux*
fi

# Clean up ZFS source
if [ -d "zfs" ] || [ -d "zfs-*" ] || [ -f "zfs-*.tar.gz" ]; then
    log "INFO" "Removing ZFS source..."
    rm -rf zfs*
fi

# Clean up OneFileLinux output
if [ -f "OneFileLinux.efi" ]; then
    log "INFO" "Removing OneFileLinux.efi..."
    rm -f OneFileLinux.efi
fi

# Clean up build artifacts
if [ -f ".build_progress" ]; then
    log "INFO" "Removing build progress file..."
    rm -f .build_progress
fi

# Clean up extraction markers
log "INFO" "Removing extraction markers..."
find . -name ".extraction_complete" -type f -delete

# Clean up temporary files
log "INFO" "Removing temporary files..."
rm -f *.tmp
rm -f build_error.log

log "SUCCESS" "Cleanup completed successfully"