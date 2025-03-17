#!/bin/bash
#
# Build Linux kernel and create EFI file
# 
# This is now a wrapper around the cross-environment build system
# for better compatibility and maintainability.
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

# Check for cross-environment build script
if [ ! -f "./85_cross_env_build.sh" ]; then
    log "ERROR" "Cross-environment build script not found: ./85_cross_env_build.sh"
    log "ERROR" "Please ensure all build system scripts are available"
    exit 1
fi

# Make sure cross-environment build script is executable
chmod +x ./85_cross_env_build.sh

# Map legacy environment variables to modern build arguments
BUILD_ARGS=""

# Log the transition information
log "INFO" "04_build.sh is now a wrapper for the cross-environment build system"
log "INFO" "All functionality has been moved to 85_cross_env_build.sh"

# Map minimal kernel configuration
if [ "${INCLUDE_MINIMAL_KERNEL:-false}" = "true" ]; then
    BUILD_ARGS="$BUILD_ARGS --minimal-kernel"
    log "INFO" "Building minimal kernel version (optimized for size)"
else
    BUILD_ARGS="$BUILD_ARGS --standard-kernel"
    log "INFO" "Building standard kernel version"
fi

# Map ZFS support
if [ "${INCLUDE_ZFS:-true}" = "true" ]; then
    BUILD_ARGS="$BUILD_ARGS --with-zfs"
    log "INFO" "Including ZFS support"
else
    BUILD_ARGS="$BUILD_ARGS --without-zfs"
    log "INFO" "Excluding ZFS support"
fi

# Map BTRFS support
if [ "${INCLUDE_BTRFS:-false}" = "true" ]; then
    BUILD_ARGS="$BUILD_ARGS --with-btrfs"
    log "INFO" "Including BTRFS support"
else
    BUILD_ARGS="$BUILD_ARGS --without-btrfs"
    log "INFO" "Excluding BTRFS support"
fi

# Map compression settings
if [ "${INCLUDE_COMPRESSION:-true}" = "true" ]; then
    BUILD_ARGS="$BUILD_ARGS --with-compression"
    
    # Map compression tool if specified
    if [ -n "${COMPRESSION_TOOL:-}" ]; then
        BUILD_ARGS="$BUILD_ARGS --compression-tool=${COMPRESSION_TOOL}"
        log "INFO" "Using compression tool: ${COMPRESSION_TOOL}"
    fi
else
    BUILD_ARGS="$BUILD_ARGS --without-compression"
    log "INFO" "Compression disabled"
fi

# Map build performance options
if [ "${USE_CACHE:-false}" = "true" ]; then
    BUILD_ARGS="$BUILD_ARGS --use-cache"
fi

if [ "${USE_SWAP:-false}" = "true" ]; then
    BUILD_ARGS="$BUILD_ARGS --use-swap"
fi

if [ "${INTERACTIVE_CONFIG:-false}" = "true" ]; then
    BUILD_ARGS="$BUILD_ARGS --interactive-config"
fi

# Map build verbosity
if [ "${MAKE_VERBOSE:-0}" = "1" ] || [ "${VERBOSE:-false}" = "true" ]; then
    BUILD_ARGS="$BUILD_ARGS --make-verbose"
fi

# Map number of build jobs
if [ -n "${BUILD_JOBS:-}" ] && [ "${BUILD_JOBS:-0}" -gt 0 ]; then
    BUILD_ARGS="$BUILD_ARGS --jobs=${BUILD_JOBS}"
    log "INFO" "Using specified number of build jobs: ${BUILD_JOBS}"
fi

# Notify about the transition to the new build system
log "INFO" "Preparing to execute the cross-environment build script"
log "INFO" "Build arguments: $BUILD_ARGS"
log "INFO" ""
log "INFO" "NOTE: Future versions may remove this wrapper script."
log "INFO" "Please consider using 85_cross_env_build.sh directly."


# Record the start time to measure build duration
BUILD_START_TIME=$(date +%s)

# Change back to the build directory
cd ..

# Execute the cross-environment build script
log "INFO" "Executing cross-environment build script"
log "INFO" "Command: ./85_cross_env_build.sh $BUILD_ARGS"
./85_cross_env_build.sh $BUILD_ARGS

# Save the exit code
EXIT_CODE=$?

# Print a simple summary to indicate this was a wrapper
if [ $EXIT_CODE -eq 0 ]; then
    log "SUCCESS" "Cross-environment build completed successfully"
    
    # Calculate and display the total build time
    BUILD_END_TIME=$(date +%s)
    BUILD_DURATION=$((BUILD_END_TIME - BUILD_START_TIME))
    BUILD_MINUTES=$((BUILD_DURATION / 60))
    BUILD_SECONDS=$((BUILD_DURATION % 60))
    
    log "INFO" "Total build time: ${BUILD_MINUTES}m ${BUILD_SECONDS}s"
    log "INFO" "Build was executed using the cross-environment script"
else
    log "ERROR" "Cross-environment build failed with exit code: $EXIT_CODE"
    log "INFO" "For more details, review the output above or try running the cross-environment script directly:"
    log "INFO" "  ./85_cross_env_build.sh $BUILD_ARGS"
fi

# Exit with the same exit code
exit $EXIT_CODE
