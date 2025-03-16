#!/bin/bash
# Docker entrypoint script for OneRecovery builder
set -e

# Fixed uid/gid or take from environment
USER_ID=${USER_ID:-1000}
GROUP_ID=${GROUP_ID:-1000}

echo "Starting with UID: $USER_ID, GID: $GROUP_ID"

# Make sure we have a /tmp directory with proper permissions
mkdir -p /tmp
chmod 1777 /tmp

# Create a fresh work directory with all permissions for extraction
TEMP_EXTRACT_DIR="/onerecovery/extract_temp"
mkdir -p "$TEMP_EXTRACT_DIR"
chmod 777 "$TEMP_EXTRACT_DIR"

# Make sure we have build directories
mkdir -p /onerecovery/build
mkdir -p /onerecovery/output
mkdir -p /onerecovery/.buildcache

# Get build directory absolute path
BUILD_DIR=$(cd /onerecovery/build && pwd)

# Update the builder user's uid/gid if needed
if [ "$USER_ID" != "1000" ] || [ "$GROUP_ID" != "1000" ]; then
    echo "Updating builder user to match host UID/GID"
    
    # First, set alpine-minirootfs directory to root if it exists
    if [ -d "$BUILD_DIR/alpine-minirootfs" ]; then
        chown -R root:root "$BUILD_DIR/alpine-minirootfs" || true
    fi
    
    # Update user
    deluser builder
    addgroup -g $GROUP_ID builder
    adduser -D -u $USER_ID -G builder builder
    echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder
fi

# Set proper ownership for build directories
chown -R builder:builder /onerecovery

# Add environment variable to indicate we're in a Docker environment
export IN_DOCKER_CONTAINER=true

# Define a function to handle special extraction cases
handle_extraction() {
    local src_file="$1"
    local dest_dir="$2"
    
    echo "Special handling for extraction of $src_file to $dest_dir"
    
    # Create destination directory first
    mkdir -p "$dest_dir"
    
    # Use temp directory for intermediate extraction
    mkdir -p "$TEMP_EXTRACT_DIR"
    
    # Extract as root first to a temp location
    if [[ "$src_file" == *.tar.gz ]]; then
        tar -xzf "$src_file" -C "$TEMP_EXTRACT_DIR"
    elif [[ "$src_file" == *.tar.xz ]]; then
        # For .tar.xz files, must decompress and extract separately
        xz -dc "$src_file" | tar -x -C "$TEMP_EXTRACT_DIR"
    fi
    
    # Check if extraction succeeded
    if [ $? -ne 0 ] || [ -z "$(ls -A "$TEMP_EXTRACT_DIR")" ]; then
        echo "WARNING: Initial extraction failed, trying alternative method"
        # Try using tar with xf directly
        if [[ "$src_file" == *.tar.xz ]]; then
            tar -xf "$src_file" -C "$TEMP_EXTRACT_DIR" --no-same-owner
        fi
    fi
    
    # Check again if extraction succeeded
    if [ -z "$(ls -A "$TEMP_EXTRACT_DIR")" ]; then
        echo "ERROR: All extraction methods failed for $src_file"
        return 1
    fi
    
    # Copy files to final location with correct permissions
    cp -a "$TEMP_EXTRACT_DIR"/* "$dest_dir"/ || true
    
    # Clean up
    rm -rf "$TEMP_EXTRACT_DIR"/*
    
    # Set permissions
    chown -R builder:builder "$dest_dir"
    
    # Verify final directory has content
    if [ -z "$(ls -A "$dest_dir")" ]; then
        echo "ERROR: Failed to extract content to $dest_dir"
        return 1
    fi
    
    echo "Extraction completed successfully to $dest_dir"
    return 0
}

# Export the function so it's available in child processes
export -f handle_extraction

# Set working directory
cd /onerecovery/build

# Define function to run build
run_build() {
    # Handle special alpine extraction issues
    if [ -f "alpine-minirootfs-3.21.3-x86_64.tar.gz" ] && [ ! -d "alpine-minirootfs" ]; then
        echo "Pre-extracting Alpine minirootfs as root"
        mkdir -p alpine-minirootfs
        handle_extraction "alpine-minirootfs-3.21.3-x86_64.tar.gz" "alpine-minirootfs"
    fi
    
    # Run the build command
    if [ -n "$BUILD_ARGS" ]; then
        echo "Running: ./build.sh $BUILD_ARGS"
        ./build.sh $BUILD_ARGS
    else
        echo "Running: ./build.sh"
        ./build.sh
    fi
}

# Run the command as the builder user
if [ $# -eq 0 ]; then
    # Default command if none provided
    exec su-exec builder bash -c "cd /onerecovery/build && run_build"
else
    # Run whatever command was passed
    exec su-exec builder "$@"
fi