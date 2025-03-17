#!/bin/bash
#
# Download Alpine Linux, Linux kernel, and ZFS sources
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

# Define component versions
alpineminirootfsfile="alpine-minirootfs-3.21.3-x86_64.tar.gz"
linuxver="linux-6.12.19"
zfsver="2.3.0"

# Define download URLs
ALPINE_URL="http://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/$alpineminirootfsfile"
KERNEL_URL="http://cdn.kernel.org/pub/linux/kernel/v6.x/$linuxver.tar.xz"
ZFS_URL="https://github.com/openzfs/zfs/releases/download/zfs-${zfsver}/zfs-${zfsver}.tar.gz"

# Function to download and verify a file
download_and_verify() {
    local url=$1
    local file=$(basename "$url")
    local component=$2
    
    # Use cache if enabled
    if [ "${USE_CACHE:-false}" = "true" ]; then
        local cache_file="$CACHE_DIR/sources/$file"
        
        if [ -f "$cache_file" ]; then
            log "INFO" "Using cached $component from $cache_file"
            
            # Copy from cache to working directory
            cp "$cache_file" ./ || {
                log "WARNING" "Failed to copy from cache, will download instead"
                download_file "$url" "$file" "$component"
            }
        else
            # Download and store in cache
            log "INFO" "Downloading $component from $url (will cache)"
            
            wget -c4 "$url" || {
                log "ERROR" "Failed to download $component from $url"
                return 1
            }
            
            # Store in cache
            mkdir -p "$CACHE_DIR/sources"
            cp "$file" "$cache_file" || log "WARNING" "Failed to cache $file"
        fi
    else
        # Regular download without caching
        download_file "$url" "$file" "$component"
    fi
    
    log "SUCCESS" "Downloaded $component successfully"
    return 0
}

# Function to download file without caching
download_file() {
    local url=$1
    local file=$2
    local component=$3
    
    log "INFO" "Downloading $component from $url"
    
    # Skip download if file already exists and --resume flag is used
    if [ "$RESUME_MODE" = true ] && [ -f "$file" ]; then
        log "INFO" "File $file already exists, skipping download"
    else
        wget -c4 "$url" || {
            log "ERROR" "Failed to download $component from $url"
            return 1
        }
    fi
    
    return 0
}

# Function to check if running in a container
is_container() {
    # First check the environment variable set by the entrypoint script
    if [ "${IN_DOCKER_CONTAINER}" = "true" ]; then
        return 0
    fi
    
    # Fallback to traditional detection methods
    grep -q "docker\|container" /proc/1/cgroup 2>/dev/null || [ -f "/.dockerenv" ]
    return $?
}

# Function to extract using busybox tar
extract_with_busybox() {
    local file=$1
    local target=$2
    local strip=$3
    
    log "INFO" "Using busybox tar for extraction"
    if [ "$strip" -gt 0 ]; then
        busybox tar -xf "$file" -C "$target" --strip-components=$strip
    else
        busybox tar -xf "$file" -C "$target"
    fi
    return $?
}

# Function to extract using pipe method (decompress | extract)
extract_with_pipe() {
    local file=$1
    local target=$2
    local strip=$3
    
    log "INFO" "Using pipe-based extraction (decompress | extract)"
    
    if [[ "$file" == *.tar.gz ]]; then
        if [ "$strip" -gt 0 ]; then
            gzip -dc "$file" | tar -x -C "$target" --strip-components=$strip --no-same-owner
        else
            gzip -dc "$file" | tar -x -C "$target" --no-same-owner
        fi
    elif [[ "$file" == *.tar.xz ]]; then
        if [ "$strip" -gt 0 ]; then
            xz -dc "$file" | tar -x -C "$target" --strip-components=$strip --no-same-owner
        else
            xz -dc "$file" | tar -x -C "$target" --no-same-owner
        fi
    else
        return 1
    fi
    return $?
}

# Function to try cached version if extraction fails
try_cached_version() {
    local file=$1
    local target=$2
    local component=$3
    
    local base_name=$(basename "$file")
    local cache_dir="/onerecovery/.buildcache/${component,,}"
    
    if [ -d "$cache_dir/${base_name%.tar.*}" ]; then
        log "INFO" "Found cached $component, copying"
        cp -a "$cache_dir/${base_name%.tar.*}/." "$target/"
        return $?
    fi
    
    return 1
}

# Function to extract an archive with container awareness
extract_archive() {
    local file=$1
    local target=$2
    local component=$3
    local strip_components=0
    
    log "INFO" "Extracting $component from $file"
    
    # If target is not specified, use current directory or component directory
    if [[ "$target" == "" ]]; then
        if [[ "$file" == *.tar.xz ]]; then
            target="${file%.tar.xz}"
            strip_components=1
        elif [[ "$file" == *.tar.gz ]]; then
            target="."
        fi
    fi
    
    # Check if target directory already exists and has a completion marker
    if [ -d "$target" ] && [ -f "$target/.extraction_complete" ]; then
        log "SUCCESS" "$component already extracted completely (found marker file)"
        return 0
    fi
    
    # Create target directory if it doesn't exist
    [ ! -d "$target" ] && mkdir -p "$target"
    
    # Determine extraction method based on environment
    if is_container; then
        log "INFO" "Detected container environment, using special extraction modes"
        
        # Check if extraction has been pre-handled by entrypoint script
        if [[ "$file" == *"alpine-minirootfs"* ]] && [ -d "./alpine-minirootfs" ] && [ -f "./alpine-minirootfs/etc/alpine-release" ]; then
            log "INFO" "Alpine minirootfs appears to be pre-extracted, skipping extraction"
            return 0
        fi
        
        # Try calling external handler if available (from entrypoint)
        if type handle_extraction &>/dev/null; then
            log "INFO" "Using entrypoint extraction handler"
            handle_extraction "$file" "$target" && return 0
        fi
        
        # Try extraction methods in sequence until one succeeds
        if command -v busybox &> /dev/null; then
            extract_with_busybox "$file" "$target" "$strip_components" && return 0
        fi
        
        extract_with_pipe "$file" "$target" "$strip_components" && return 0
        
        if [ "${USE_CACHE:-false}" = "true" ]; then
            try_cached_version "$file" "$target" "$component" && return 0
        fi
        
        # Final attempt - try using sudo if available
        if command -v sudo &> /dev/null; then
            log "INFO" "Attempting extraction with sudo"
            if [[ "$file" == *.tar.gz ]]; then
                sudo mkdir -p "$target"
                sudo tar -xzf "$file" -C "$target" && sudo chown -R $(id -u):$(id -g) "$target" && return 0
            elif [[ "$file" == *.tar.xz ]]; then
                sudo mkdir -p "$target"
                sudo tar -xf "$file" -C "$target" --strip-components="$strip_components" && sudo chown -R $(id -u):$(id -g) "$target" && return 0
            fi
        fi
        
        log "ERROR" "All extraction methods failed for $file"
        return 1
    else
        # Standard extraction for non-container environments
        if [[ "$file" == *.tar.gz ]]; then
            tar -C "$target" -xf "$file" || return 1
        elif [[ "$file" == *.tar.xz ]]; then
            if [ "$strip_components" -gt 0 ]; then
                tar -xf "$file" -C "$target" --strip-components=$strip_components --no-same-owner || return 1
            else
                tar -xf "$file" --no-same-owner || return 1
            fi
        else
            log "ERROR" "Unknown archive format: $file"
            return 1
        fi
    fi
    
    # Create a marker file to indicate successful extraction
    touch "$target/.extraction_complete"
    
    log "SUCCESS" "Extracted $component successfully"
    return 0
}

# Main function
main() {
    # Check if we should resume from a checkpoint
    check_resume_point "$1"

    # Step 1: Download and extract Alpine Linux
    log "INFO" "Step 1: Getting Alpine Linux minirootfs"
    if ! download_and_verify "$ALPINE_URL" "Alpine Linux"; then
        log "ERROR" "Failed to download Alpine Linux"
        exit 1
    fi
    
    if ! extract_archive "$alpineminirootfsfile" "./alpine-minirootfs" "Alpine Linux"; then
        log "ERROR" "Failed to extract Alpine Linux"
        exit 1
    fi

    # Step 2: Download and extract Linux kernel
    log "INFO" "Step 2: Getting Linux kernel"
    if ! download_and_verify "$KERNEL_URL" "Linux kernel"; then
        log "ERROR" "Failed to download Linux kernel"
        exit 1
    fi
    
    if ! extract_archive "$linuxver.tar.xz" "" "Linux kernel"; then
        log "ERROR" "Failed to extract Linux kernel"
        exit 1
    fi

    # Create symbolic link to Linux kernel directory
    if [ ! -L "linux" ] || [ ! -d "linux" ]; then
        ln -sf "$linuxver" linux
        log "INFO" "Created symbolic link to Linux kernel directory"
    fi

    # Step 3: Download and extract OpenZFS if enabled
    if [ "${INCLUDE_ZFS:-true}" = "true" ]; then
        log "INFO" "Step 3: Getting OpenZFS source"
        if ! download_and_verify "$ZFS_URL" "OpenZFS"; then
            log "ERROR" "Failed to download OpenZFS"
            exit 1
        fi
        
        # First check if both directories exist - if so, clean up the redundant one
        if [ -d "zfs-${zfsver}" ] && [ -d "zfs" ]; then
            log "INFO" "Found both zfs and zfs-${zfsver} directories, removing zfs-${zfsver}"
            rm -rf "zfs-${zfsver}"
        fi
        
        # If zfs directory exists, extract directly to it
        if [ -d "zfs" ]; then
            if ! extract_archive "zfs-${zfsver}.tar.gz" "zfs" "OpenZFS"; then
                log "ERROR" "Failed to extract OpenZFS"
                exit 1
            fi
            log "INFO" "Extracted OpenZFS to existing zfs directory"
        else
            # Extract to temporary directory and rename
            if ! extract_archive "zfs-${zfsver}.tar.gz" "" "OpenZFS"; then
                log "ERROR" "Failed to extract OpenZFS"
                exit 1
            fi
            
            # Rename ZFS directory
            if [ -d "zfs-${zfsver}" ]; then
                mv "zfs-${zfsver}" zfs
                log "INFO" "Renamed ZFS directory from zfs-${zfsver} to zfs"
            else
                log "ERROR" "Expected zfs-${zfsver} directory not found after extraction"
                exit 1
            fi
        fi
    else
        log "INFO" "Step 3: Skipping OpenZFS (disabled in configuration)"
    fi

    # Print final status
    print_script_end
    return 0
}

# Execute main function
main "$@"

