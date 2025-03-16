#!/bin/bash
#
# Download Alpine Linux, Linux kernel, and ZFS sources
#

# Define script name for error handling
SCRIPT_NAME=$(basename "$0")

# Source common error handling
source ./error_handling.sh

# Initialize error handling
init_error_handling

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
    
    log "SUCCESS" "Downloaded $component successfully"
    return 0
}

# Function to extract an archive
extract_archive() {
    local file=$1
    local target=$2
    local component=$3
    
    log "INFO" "Extracting $component from $file"
    
    if [[ "$file" == *.tar.gz ]]; then
        if [[ "$target" == "" ]]; then
            tar -xf "$file" || return 1
        else
            # Create target directory if it doesn't exist
            [ ! -d "$target" ] && mkdir -p "$target"
            tar -C "$target" -xf "$file" || return 1
        fi
    elif [[ "$file" == *.tar.xz ]]; then
        tar -xf "$file" || return 1
    else
        log "ERROR" "Unknown archive format: $file"
        return 1
    fi
    
    log "SUCCESS" "Extracted $component successfully"
    return 0
}

# Check if we should resume from a checkpoint
check_resume_point "$1"

# Download and extract Alpine Linux
log "INFO" "Step 1: Getting Alpine Linux minirootfs"
download_and_verify "$ALPINE_URL" "Alpine Linux" && 
    extract_archive "$alpineminirootfsfile" "./alpine-minirootfs" "Alpine Linux" || 
    exit 1

# Download and extract Linux kernel
log "INFO" "Step 2: Getting Linux kernel"
download_and_verify "$KERNEL_URL" "Linux kernel" && 
    extract_archive "$linuxver.tar.xz" "" "Linux kernel" || 
    exit 1

# Create symbolic link to Linux kernel directory
if [ ! -L "linux" ] || [ ! -d "linux" ]; then
    ln -sf "$linuxver" linux
    log "INFO" "Created symbolic link to Linux kernel directory"
fi

# Download and extract OpenZFS if enabled
if [ "${INCLUDE_ZFS:-true}" = "true" ]; then
    log "INFO" "Step 3: Getting OpenZFS source"
    download_and_verify "$ZFS_URL" "OpenZFS" && 
        extract_archive "zfs-${zfsver}.tar.gz" "" "OpenZFS" || 
        exit 1

    # Rename ZFS directory
    if [ -d "zfs-${zfsver}" ] && [ ! -d "zfs" ]; then
        mv "zfs-${zfsver}" zfs
        log "INFO" "Renamed ZFS directory"
    elif [ -d "zfs" ]; then
        log "INFO" "ZFS directory already exists"
    fi
else
    log "INFO" "Step 3: Skipping OpenZFS (disabled in configuration)"
fi

# Print final status
print_script_end

