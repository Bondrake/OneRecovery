#!/bin/bash
#
# OneRecovery Cross-Environment Build Script (85_cross_env_build.sh)
# Works in GitHub Actions, Docker, and local environments
# Unified build system that standardizes build across all environments
# This is part of the library scripts (80-89 range)
#
set -e

# Define script name for error handling
SCRIPT_NAME=$(basename "$0")

# Source the library scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the core library first (required)
if [ ! -f "$SCRIPT_DIR/80_common.sh" ]; then
    echo "ERROR: Critical library file not found: $SCRIPT_DIR/80_common.sh"
    exit 1
fi
source "$SCRIPT_DIR/80_common.sh"

# Source all library scripts using the source_libraries function
source_libraries "$SCRIPT_DIR"

# Define color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Define paths
BUILD_DIR="$(cd "$SCRIPT_DIR" && pwd)"
ROOTFS_DIR="$BUILD_DIR/alpine-minirootfs"
KERNEL_DIR="$BUILD_DIR/linux"
ZFS_DIR="$BUILD_DIR/zfs"
ZFILES_DIR="$BUILD_DIR/zfiles"
OUTPUT_DIR="$BUILD_DIR/../output"

# Banner is now provided by error_handling.sh

# Log function
log() {
    local level=$1
    local message=$2
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        *)
            echo -e "$message"
            ;;
    esac
}

# Parse command-line arguments
parse_args() {
    BUILD_TYPE="standard"
    INCLUDE_ZFS=true
    INCLUDE_MINIMAL_KERNEL=false
    INCLUDE_COMPRESSION=true
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --minimal)
                BUILD_TYPE="minimal"
                INCLUDE_ZFS=false
                INCLUDE_MINIMAL_KERNEL=true
                shift
                ;;
            --full)
                BUILD_TYPE="full"
                INCLUDE_ZFS=true
                INCLUDE_MINIMAL_KERNEL=false
                shift
                ;;
            --with-zfs)
                INCLUDE_ZFS=true
                shift
                ;;
            --without-zfs)
                INCLUDE_ZFS=false
                shift
                ;;
            --minimal-kernel)
                INCLUDE_MINIMAL_KERNEL=true
                shift
                ;;
            --standard-kernel)
                INCLUDE_MINIMAL_KERNEL=false
                shift
                ;;
            --compression)
                INCLUDE_COMPRESSION=true
                shift
                ;;
            --no-compression)
                INCLUDE_COMPRESSION=false
                shift
                ;;
            *)
                log "WARNING" "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    log "INFO" "Build configuration:"
    log "INFO" "- Build type: $BUILD_TYPE"
    log "INFO" "- Include ZFS: $INCLUDE_ZFS"
    log "INFO" "- Use minimal kernel: $INCLUDE_MINIMAL_KERNEL"
    log "INFO" "- Enable compression: $INCLUDE_COMPRESSION"
}

# Download Alpine Linux
download_alpine() {
    print_section "Downloading Alpine Linux"
    
    local alpine_version="3.21.3"
    local alpine_file="alpine-minirootfs-${alpine_version}-x86_64.tar.gz"
    local alpine_url="http://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/$alpine_file"
    
    if [ ! -f "$BUILD_DIR/$alpine_file" ]; then
        log "INFO" "Downloading Alpine Linux minirootfs"
        wget -q --show-progress "$alpine_url" -O "$BUILD_DIR/$alpine_file" || {
            log "ERROR" "Failed to download Alpine Linux"
            return 1
        }
    else
        log "INFO" "Alpine Linux minirootfs already downloaded"
    fi
    
    if [ ! -d "$ROOTFS_DIR" ]; then
        log "INFO" "Extracting Alpine Linux minirootfs"
        extract_archive "$BUILD_DIR/$alpine_file" "$ROOTFS_DIR"
    else
        log "INFO" "Alpine Linux minirootfs already extracted"
    fi
    
    log "SUCCESS" "Alpine Linux prepared successfully"
}

# Download Linux kernel
download_kernel() {
    print_section "Downloading Linux kernel"
    
    local kernel_version="6.12.19"
    local kernel_file="linux-${kernel_version}.tar.xz"
    local kernel_url="https://cdn.kernel.org/pub/linux/kernel/v6.x/$kernel_file"
    
    if [ ! -f "$BUILD_DIR/$kernel_file" ]; then
        log "INFO" "Downloading Linux kernel"
        wget -q --show-progress "$kernel_url" -O "$BUILD_DIR/$kernel_file" || {
            log "ERROR" "Failed to download Linux kernel"
            return 1
        }
    else
        log "INFO" "Linux kernel already downloaded"
    fi
    
    if [ ! -d "$KERNEL_DIR" ]; then
        log "INFO" "Extracting Linux kernel"
        mkdir -p "$KERNEL_DIR"
        extract_archive "$BUILD_DIR/$kernel_file" "$KERNEL_DIR" 1
        
        # Create a symlink pointing to the kernel directory
        ln -sf "linux" "linux-${kernel_version}" 2>/dev/null || true
    else
        log "INFO" "Linux kernel already extracted"
    fi
    
    log "SUCCESS" "Linux kernel prepared successfully"
}

# Download ZFS
download_zfs() {
    if [ "$INCLUDE_ZFS" != "true" ]; then
        log "INFO" "Skipping ZFS (disabled in configuration)"
        return 0
    fi
    
    print_section "Downloading ZFS"
    
    local zfs_version="2.3.0"
    local zfs_file="zfs-${zfs_version}.tar.gz"
    local zfs_url="https://github.com/openzfs/zfs/releases/download/zfs-${zfs_version}/$zfs_file"
    
    if [ ! -f "$BUILD_DIR/$zfs_file" ]; then
        log "INFO" "Downloading ZFS"
        wget -q --show-progress "$zfs_url" -O "$BUILD_DIR/$zfs_file" || {
            log "ERROR" "Failed to download ZFS"
            return 1
        }
    else
        log "INFO" "ZFS already downloaded"
    fi
    
    if [ ! -d "$ZFS_DIR" ]; then
        log "INFO" "Extracting ZFS"
        mkdir -p "$ZFS_DIR"
        extract_archive "$BUILD_DIR/$zfs_file" "$ZFS_DIR" 1
    else
        log "INFO" "ZFS already extracted"
    fi
    
    log "SUCCESS" "ZFS prepared successfully"
}

# Configure Alpine Linux and system services
configure_system() {
    print_section "Configuring system"
    
    log "INFO" "Setting up system services and configuration"
    configure_alpine "$ROOTFS_DIR" "$ZFILES_DIR"
    
    # Set up kernel configuration
    local config_type="standard"
    if [ "$INCLUDE_MINIMAL_KERNEL" = "true" ]; then
        config_type="minimal"
    fi
    
    setup_kernel_config "$KERNEL_DIR" "$config_type" "$ZFILES_DIR"
    
    if [ "$INCLUDE_ZFS" = "true" ]; then
        setup_zfs "$ZFS_DIR" "$KERNEL_DIR"
    fi
    
    log "SUCCESS" "System configuration completed"
}

# Build the kernel and modules
build_kernel() {
    print_section "Building Linux kernel"
    
    # Get optimal number of threads for building
    local threads=$(get_optimal_threads)
    log "INFO" "Building kernel with $threads threads"
    
    # Check kernel size before building
    local kernel_size=$(du -sh "$KERNEL_DIR" 2>/dev/null | cut -f1 || echo "unknown")
    log "INFO" "Kernel source size: $kernel_size"
    
    # Enter kernel directory
    cd "$KERNEL_DIR"
    
    # Build the kernel
    log "INFO" "Building Linux kernel"
    make -j"$threads" || {
        log "ERROR" "Kernel build failed"
        return 1
    }
    
    # Build modules
    log "INFO" "Building kernel modules"
    make -j"$threads" modules || {
        log "ERROR" "Module build failed"
        return 1
    }
    
    # Install modules
    log "INFO" "Installing kernel modules"
    INSTALL_MOD_PATH="$ROOTFS_DIR" make modules_install
    
    log "SUCCESS" "Kernel and modules built successfully"
    
    # Return to build directory
    cd "$BUILD_DIR"
}

# Build ZFS modules
build_zfs() {
    if [ "$INCLUDE_ZFS" != "true" ]; then
        log "INFO" "Skipping ZFS build (disabled in configuration)"
        return 0
    fi
    
    print_section "Building ZFS"
    
    # Get optimal number of threads for building
    local threads=$(get_optimal_threads)
    log "INFO" "Building ZFS with $threads threads"
    
    # Enter ZFS directory
    cd "$ZFS_DIR"
    
    # Configure ZFS for the kernel
    log "INFO" "Configuring ZFS for the kernel"
    ./configure --with-linux="$KERNEL_DIR" --with-linux-obj="$KERNEL_DIR" --prefix=/fake || {
        log "ERROR" "ZFS configuration failed"
        return 1
    }
    
    # Build ZFS modules
    log "INFO" "Building ZFS modules"
    make -j"$threads" -C module || {
        log "ERROR" "ZFS module build failed"
        return 1
    }
    
    # Install ZFS modules
    log "INFO" "Installing ZFS modules"
    DESTDIR="$(realpath "$ROOTFS_DIR")" make INSTALL_MOD_PATH="$(realpath "$ROOTFS_DIR")" install
    
    # Clean up fake directory
    rm -rf "${ROOTFS_DIR}/fake"
    
    log "SUCCESS" "ZFS built and installed successfully"
    
    # Return to build directory
    cd "$BUILD_DIR"
}

# Create the final EFI file
create_efi() {
    print_section "Creating EFI file"
    
    # Ensure output directory exists
    ensure_directory "$OUTPUT_DIR"
    
    # Get kernel version for modules.dep
    local kernel_version=$(ls "$ROOTFS_DIR/lib/modules/" | head -1)
    log "INFO" "Creating modules.dep for kernel $kernel_version"
    
    # Enter kernel directory
    cd "$KERNEL_DIR"
    
    # Create modules.dep
    log "INFO" "Creating modules.dep"
    depmod -b "$ROOTFS_DIR" -F System.map "$kernel_version"
    
    # Create EFI file
    log "INFO" "Creating OneRecovery.efi"
    cp arch/x86/boot/bzImage "$OUTPUT_DIR/OneRecovery.efi"
    
    # Record original size
    local original_size=$(du -h "$OUTPUT_DIR/OneRecovery.efi" | cut -f1)
    log "INFO" "Original EFI size: $original_size"
    
    # Apply compression if enabled
    if [ "$INCLUDE_COMPRESSION" = "true" ] && command -v upx &>/dev/null; then
        log "INFO" "Applying UPX compression"
        
        # Create a backup
        cp "$OUTPUT_DIR/OneRecovery.efi" "$OUTPUT_DIR/OneRecovery.efi.original"
        
        # Compress the EFI file
        if upx --best --lzma "$OUTPUT_DIR/OneRecovery.efi"; then
            local compressed_size=$(du -h "$OUTPUT_DIR/OneRecovery.efi" | cut -f1)
            log "SUCCESS" "Compression successful"
            log "INFO" "Compressed size: $compressed_size"
        else
            log "WARNING" "Compression failed, restoring original"
            mv "$OUTPUT_DIR/OneRecovery.efi.original" "$OUTPUT_DIR/OneRecovery.efi"
        fi
        
        # Clean up backup
        rm -f "$OUTPUT_DIR/OneRecovery.efi.original"
    elif [ "$INCLUDE_COMPRESSION" = "true" ]; then
        log "WARNING" "UPX not found, skipping compression"
    else
        log "INFO" "Compression disabled"
    fi
    
    local final_size=$(du -h "$OUTPUT_DIR/OneRecovery.efi" | cut -f1)
    log "SUCCESS" "OneRecovery.efi created successfully (size: $final_size)"
    
    # Return to build directory
    cd "$BUILD_DIR"
}

# Main function
main() {
    # Initialize script with standard header (prints banner)
    initialize_script
    
    # Print environment information
    print_environment_info
    
    # Parse command-line arguments
    parse_args "$@"
    
    # Download components
    download_alpine
    download_kernel
    download_zfs
    
    # Configure system
    configure_system
    
    # Build components
    build_kernel
    build_zfs
    
    # Create EFI file
    create_efi
    
    log "SUCCESS" "OneRecovery build completed successfully!"
    log "INFO" "EFI file: $OUTPUT_DIR/OneRecovery.efi"
}

# Run the main function
main "$@"