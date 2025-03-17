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

# Set proper ownership for build directories, excluding special directories
log_info() {
    echo "[INFO] $1"
}

log_warn() {
    echo "[WARN] $1"
}

log_info "Setting up build environment..."
# Instead of changing ownership of all mounted volumes (which is slow),
# we'll change Docker's approach to use the host user's UID/GID directly

# Ensure runtime directories exist and have correct permissions
mkdir -p /onerecovery/build /onerecovery/output /onerecovery/.buildcache
chmod 755 /onerecovery/build /onerecovery/output /onerecovery/.buildcache

# Set ownership of the .buildcache directory which is a Docker volume with persistence
# This is necessary for proper ccache operation
chown -R builder:builder /onerecovery/.buildcache 2>/dev/null || true

# For mounted host volumes (build and output), we skip ownership changes
# This is much faster and works better with bind mounts from the host
log_info "Using host's ownership for mounted volumes"

# Ensure specific directories exist with correct permissions
if [ -d "/onerecovery/build/alpine-minirootfs" ]; then
    log_info "Setting up special directories in alpine-minirootfs..."
    
    # Create and set permissions for key directories
    if [ -d "/onerecovery/build/alpine-minirootfs/proc" ]; then
        chmod 555 "/onerecovery/build/alpine-minirootfs/proc" 2>/dev/null || log_warn "Could not set permissions on /proc (this is normal in Docker)"
    fi
    
    if [ -d "/onerecovery/build/alpine-minirootfs/var/empty" ]; then
        chmod 555 "/onerecovery/build/alpine-minirootfs/var/empty" 2>/dev/null || log_warn "Could not set permissions on /var/empty (this is normal in Docker)"
    fi
fi

# Add environment variable to indicate we're in a Docker environment
export IN_DOCKER_CONTAINER=true

# Set up performance optimizations
log_info "Setting up build performance optimizations"

# Configure ccache for better performance
export CCACHE_DIR=/onerecovery/.buildcache/ccache
export PATH=/usr/lib/ccache:$PATH

# Check if we have enough memory for parallel builds
if [ -f "/proc/meminfo" ]; then
    available_memory_kb=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
    if [ "$available_memory_kb" -gt 0 ]; then
        available_memory_gb=$(awk "BEGIN {printf \"%.1f\", $available_memory_kb/1024/1024}")
        log_info "Available memory: ${available_memory_gb}GB"
        
        # Calculate optimal number of jobs based on memory
        # Each job needs about 2GB for kernel compilation
        optimal_jobs=$(awk "BEGIN {print int($available_memory_kb/1024/1024/2)}")
        # Ensure at least 1 job and get the minimum of this and the number of CPUs
        cpu_count=$(nproc 2>/dev/null || echo 2)
        optimal_jobs=$(( optimal_jobs < 1 ? 1 : optimal_jobs ))
        optimal_jobs=$(( optimal_jobs > cpu_count ? cpu_count : optimal_jobs ))
        
        log_info "Automatically using $optimal_jobs parallel jobs based on available memory"
        export BUILD_JOBS=$optimal_jobs
        
        # Add to BUILD_ARGS if not already specified
        if [ -n "$BUILD_ARGS" ] && [[ "$BUILD_ARGS" != *"--jobs="* ]]; then
            BUILD_ARGS="$BUILD_ARGS --jobs=$optimal_jobs"
        fi
    fi
fi

# Initialize ccache with optimal settings
ccache -M 5G 2>/dev/null || true
ccache -o compression=true 2>/dev/null || true
ccache -o compression_level=6 2>/dev/null || true
ccache -z 2>/dev/null || true

# Define a lightweight extraction function for bootstrapping
# This is used before we can access our library functions
bootstrap_extraction() {
    local src_file="$1"
    local dest_dir="$2"
    
    echo "Bootstrapping extraction of $src_file to $dest_dir"
    
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
    
    # Copy files to final location
    cp -a "$TEMP_EXTRACT_DIR"/* "$dest_dir"/ || true
    
    # Clean up
    rm -rf "$TEMP_EXTRACT_DIR"/*
    
    # Set permissions
    chown -R builder:builder "$dest_dir"
    
    echo "Bootstrapping extraction completed to $dest_dir"
    return 0
}

# Export the function for bootstrapping
export -f bootstrap_extraction

# Set working directory
cd /onerecovery/build

# Define function to run build
run_build() {
    # Check for the core library script (85_cross_env_build.sh is optional since we'll handle it separately)
    if [ -f "80_common.sh" ] && [ -f "81_error_handling.sh" ] && [ -f "82_build_helper.sh" ] && [ -f "83_config_helper.sh" ]; then
        # Use the library-based build system for consistent builds
        echo "Using library-based build system"
        
        # Make all library scripts executable
        chmod +x 80_common.sh
        chmod +x 81_error_handling.sh
        chmod +x 82_build_helper.sh
        chmod +x 83_config_helper.sh
        
        # Make sure the cross-environment build script exists and is executable
        if [ -f "85_cross_env_build.sh" ]; then
            chmod +x 85_cross_env_build.sh
            echo "Found cross-environment build script: 85_cross_env_build.sh"
        else
            echo "WARNING: Cross-environment build script not found in container"
            echo "Searching for the script in the build directory..."
            
            # Find the script in the mounted volumes
            SCRIPT_PATH=$(find /onerecovery -name "85_cross_env_build.sh" -type f 2>/dev/null | head -n 1)
            
            if [ -n "$SCRIPT_PATH" ]; then
                echo "Found script at: $SCRIPT_PATH"
                echo "Creating symlink to make script accessible"
                ln -sf "$SCRIPT_PATH" ./85_cross_env_build.sh
                chmod +x 85_cross_env_build.sh
            else
                echo "ERROR: Critical file not found: 85_cross_env_build.sh"
                echo "Please ensure the build directory is correctly mounted"
            fi
        fi
        
        # Use unified build script with cross-environment support
        
        # Add common options for better performance
        if [ -n "$BUILD_ARGS" ]; then
            # Add our performance options if not already included
            if [[ "$BUILD_ARGS" != *"--use-cache"* ]]; then
                BUILD_ARGS="$BUILD_ARGS --use-cache"
            fi
            if [[ "$BUILD_ARGS" != *"--use-swap"* && "$BUILD_ARGS" != *"--no-swap"* ]]; then
                BUILD_ARGS="$BUILD_ARGS --use-swap"
            fi
            
            echo "Running: ./85_cross_env_build.sh $BUILD_ARGS"
            
            # Display ccache stats before build
            echo "CCache statistics before build:"
            ccache -s
            
            # Run the build
            ./85_cross_env_build.sh $BUILD_ARGS
            
            # Display ccache stats after build
            echo "CCache statistics after build:"
            ccache -s
        else
            echo "Running: ./85_cross_env_build.sh with default options"
            echo "CCache statistics before build:"
            ccache -s
            ./85_cross_env_build.sh --use-cache --use-swap
            echo "CCache statistics after build:"
            ccache -s
        fi
    else
        # Fall back to legacy build scripts
        echo "Cross-environment build scripts not found, using legacy build system"
        
        # Handle special alpine extraction issues
        if [ -f "alpine-minirootfs-3.21.3-x86_64.tar.gz" ]; then
            echo "Pre-extracting Alpine minirootfs as root"
            # Remove existing directory if it exists
            if [ -d "alpine-minirootfs" ]; then
                rm -rf alpine-minirootfs
            fi
            
            # Create directory with proper permissions
            mkdir -p alpine-minirootfs
            
            # Use bootstrap extraction first, then we can use library functions
            bootstrap_extraction "alpine-minirootfs-3.21.3-x86_64.tar.gz" "alpine-minirootfs"
            
            # Mark extraction as complete
            touch "alpine-minirootfs/.extraction_complete"
            
            echo "Set proper permissions on Alpine minirootfs"
        fi
        
        # Run the legacy build command
        if [ -n "$BUILD_ARGS" ]; then
            echo "Running: ./build.sh $BUILD_ARGS"
            ./build.sh $BUILD_ARGS
        else
            echo "Running: ./build.sh"
            ./build.sh
        fi
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