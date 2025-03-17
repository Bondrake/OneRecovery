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
    # Default settings
    BUILD_TYPE="standard"
    
    # Optional components
    INCLUDE_ZFS=true
    INCLUDE_BTRFS=false
    INCLUDE_RECOVERY_TOOLS=true
    INCLUDE_NETWORK_TOOLS=true
    INCLUDE_CRYPTO=true
    INCLUDE_TUI=true
    INCLUDE_MINIMAL_KERNEL=false
    INCLUDE_COMPRESSION=true
    COMPRESSION_TOOL="upx"  # Options: upx, xz, zstd
    
    # Build performance options
    USE_CACHE=true
    USE_SWAP=false
    INTERACTIVE_CONFIG=false
    MAKE_VERBOSE=0
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --minimal)
                BUILD_TYPE="minimal"
                INCLUDE_ZFS=false
                INCLUDE_BTRFS=false
                INCLUDE_RECOVERY_TOOLS=false
                INCLUDE_NETWORK_TOOLS=false
                INCLUDE_CRYPTO=false
                INCLUDE_TUI=false
                INCLUDE_MINIMAL_KERNEL=true
                shift
                ;;
            --full)
                BUILD_TYPE="full"
                INCLUDE_ZFS=true
                INCLUDE_BTRFS=true
                INCLUDE_RECOVERY_TOOLS=true
                INCLUDE_NETWORK_TOOLS=true
                INCLUDE_CRYPTO=true
                INCLUDE_TUI=true
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
            --with-btrfs)
                INCLUDE_BTRFS=true
                shift
                ;;
            --without-btrfs)
                INCLUDE_BTRFS=false
                shift
                ;;
            --with-recovery-tools)
                INCLUDE_RECOVERY_TOOLS=true
                shift
                ;;
            --without-recovery-tools)
                INCLUDE_RECOVERY_TOOLS=false
                shift
                ;;
            --with-network-tools)
                INCLUDE_NETWORK_TOOLS=true
                shift
                ;;
            --without-network-tools)
                INCLUDE_NETWORK_TOOLS=false
                shift
                ;;
            --with-crypto)
                INCLUDE_CRYPTO=true
                shift
                ;;
            --without-crypto)
                INCLUDE_CRYPTO=false
                shift
                ;;
            --with-tui)
                INCLUDE_TUI=true
                shift
                ;;
            --without-tui)
                INCLUDE_TUI=false
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
            --with-compression|--compression)
                INCLUDE_COMPRESSION=true
                shift
                ;;
            --without-compression|--no-compression)
                INCLUDE_COMPRESSION=false
                shift
                ;;
            --compression-tool=*)
                COMPRESSION_TOOL="${1#*=}"
                # Validate that the tool is one of the allowed options
                if [[ "$COMPRESSION_TOOL" != "upx" && "$COMPRESSION_TOOL" != "xz" && "$COMPRESSION_TOOL" != "zstd" ]]; then
                    log "ERROR" "Invalid compression tool: $COMPRESSION_TOOL. Allowed values: upx, xz, zstd"
                    exit 1
                fi
                shift
                ;;
            --use-cache)
                USE_CACHE=true
                shift
                ;;
            --no-cache)
                USE_CACHE=false
                shift
                ;;
            --use-swap)
                USE_SWAP=true
                shift
                ;;
            --no-swap)
                USE_SWAP=false
                shift
                ;;
            --interactive-config)
                INTERACTIVE_CONFIG=true
                shift
                ;;
            --no-interactive-config)
                INTERACTIVE_CONFIG=false
                shift
                ;;
            --make-verbose)
                MAKE_VERBOSE=1
                shift
                ;;
            --make-quiet)
                MAKE_VERBOSE=0
                shift
                ;;
            --jobs=*)
                BUILD_JOBS="${1#*=}"
                # Validate that the job count is a positive integer
                if ! [[ "$BUILD_JOBS" =~ ^[0-9]+$ ]] || [ "$BUILD_JOBS" -lt 1 ]; then
                    log "ERROR" "Invalid job count: $BUILD_JOBS. Must be a positive integer."
                    exit 1
                fi
                shift
                ;;
            --help|-h)
                # Print usage information
                echo "Usage: $0 [options]"
                echo ""
                echo "Options:"
                echo "  --minimal              Minimal build optimized for size (~30-50% smaller)"
                echo "  --full                 Full build with all available components"
                echo ""
                echo "Optional Components:"
                echo "  --with-zfs             Include ZFS filesystem support (default: yes)"
                echo "  --without-zfs          Exclude ZFS filesystem support"
                echo "  --with-btrfs           Include Btrfs filesystem support (default: no)"
                echo "  --without-btrfs        Exclude Btrfs filesystem support"
                echo "  --with-recovery-tools  Include data recovery tools (default: yes)"
                echo "  --without-recovery-tools  Exclude data recovery tools"
                echo "  --with-network-tools   Include network tools (default: yes)"
                echo "  --without-network-tools  Exclude network tools"
                echo "  --with-crypto          Include encryption support (default: yes)"
                echo "  --without-crypto       Exclude encryption support"
                echo "  --with-tui             Include Text User Interface (default: yes)"
                echo "  --without-tui          Exclude Text User Interface"
                echo ""
                echo "Size Optimization Options:"
                echo "  --with-compression     Enable EFI file compression (default: yes)"
                echo "  --without-compression  Disable EFI file compression (faster boot)"
                echo "  --compression-tool=TOOL Select compression tool (upx, xz, zstd) (default: upx)"
                echo ""
                echo "Build Performance Options:"
                echo "  --use-cache            Enable source and build caching (default: yes)"
                echo "  --no-cache             Disable source and build caching"
                echo "  --jobs=N               Set number of parallel build jobs (default: CPU cores)"
                echo "  --use-swap             Create swap file if memory is low (default: no)"
                echo "  --no-swap              Do not create swap file even if memory is low"
                echo "  --interactive-config   Use interactive kernel configuration (menuconfig)"
                echo "  --no-interactive-config Use non-interactive kernel config (default)"
                echo "  --make-verbose         Enable verbose make output (V=1)"
                echo "  --make-quiet           Use quiet make output (V=0, default)"
                exit 0
                ;;
            *)
                log "WARNING" "Unknown option: $1"
                shift
                ;;
        esac
    done
    
    # Print configuration summary
    log "INFO" "Build configuration:"
    log "INFO" "- Build type: $BUILD_TYPE"
    log "INFO" "- ZFS support: $(bool_to_str "$INCLUDE_ZFS")"
    log "INFO" "- Btrfs support: $(bool_to_str "$INCLUDE_BTRFS")"
    log "INFO" "- Recovery tools: $(bool_to_str "$INCLUDE_RECOVERY_TOOLS")"
    log "INFO" "- Network tools: $(bool_to_str "$INCLUDE_NETWORK_TOOLS")"
    log "INFO" "- Crypto support: $(bool_to_str "$INCLUDE_CRYPTO")"
    log "INFO" "- Text User Interface: $(bool_to_str "$INCLUDE_TUI")"
    log "INFO" "- Use minimal kernel: $(bool_to_str "$INCLUDE_MINIMAL_KERNEL")"
    log "INFO" "- Enable compression: $(bool_to_str "$INCLUDE_COMPRESSION")"
    
    if [ "$INCLUDE_COMPRESSION" = "true" ]; then
        log "INFO" "- Compression tool: $COMPRESSION_TOOL"
    fi
    
    log "INFO" "- Use caching: $(bool_to_str "$USE_CACHE")"
    log "INFO" "- Use swap if needed: $(bool_to_str "$USE_SWAP")"
    log "INFO" "- Interactive config: $(bool_to_str "$INTERACTIVE_CONFIG")"
    log "INFO" "- Verbose make output: $(bool_to_str "$MAKE_VERBOSE")"
}

# Helper function to convert boolean to Yes/No string
bool_to_str() {
    if [ "$1" = "true" ]; then
        echo -e "${GREEN}Yes${NC}"
    else
        echo -e "${RED}No${NC}"
    fi
}

# Download Alpine Linux
download_alpine() {
    print_section "Downloading Alpine Linux"
    
    # Define architecture for fallback URLs
    local arch="x86_64"
    
    # Get the latest Alpine version using our helper function
    # Use the quiet parameter to avoid log output when capturing the result
    local alpine_version=$(get_latest_alpine_version "$ALPINE_VERSION" "3" "5" "true")
    
    # Get the Alpine URL - use quiet mode to avoid log messages in output
    local alpine_url=$(get_alpine_minirootfs_url "$alpine_version" "$arch" "true")
    local alpine_file=$(basename "$alpine_url")
    
    # Now log the information after we have clean values
    log "INFO" "Using Alpine version: $alpine_version"
    log "INFO" "Alpine URL: $alpine_url"
    
    if [ ! -f "$BUILD_DIR/$alpine_file" ]; then
        log "INFO" "Downloading Alpine Linux minirootfs"
        
        # Try downloading from the generated URL
        wget -q --show-progress --tries=3 --timeout=30 "$alpine_url" -O "$BUILD_DIR/$alpine_file"
        
        # If that fails, try alternative URLs
        if [ $? -ne 0 ]; then
            log "WARNING" "Primary download failed, trying alternative URLs"
            
            # Try with HTTP if HTTPS fails
            if [[ "$alpine_url" == https://* ]]; then
                local http_url="${alpine_url/https:/http:}"
                log "INFO" "Trying HTTP URL: $http_url"
                wget -q --show-progress --tries=3 --timeout=30 "$http_url" -O "$BUILD_DIR/$alpine_file"
            fi
            
            # If still fails, try CDN mirror
            if [ $? -ne 0 ]; then
                local mirror_url="https://dl-5.alpinelinux.org/alpine/v${alpine_version%.*}/releases/${arch:-x86_64}/alpine-minirootfs-${alpine_version}-${arch:-x86_64}.tar.gz"
                log "INFO" "Trying mirror URL: $mirror_url"
                wget -q --show-progress --tries=3 --timeout=30 "$mirror_url" -O "$BUILD_DIR/$alpine_file"
            fi
            
            # Check if any of the alternative downloads worked
            if [ $? -ne 0 ]; then
                log "ERROR" "Failed to download Alpine Linux from all sources"
                return 1
            fi
        fi
        
        log "SUCCESS" "Successfully downloaded Alpine Linux minirootfs"
    else
        log "INFO" "Alpine Linux minirootfs already downloaded"
    fi
    
    if [ ! -d "$ROOTFS_DIR" ]; then
        log "INFO" "Extracting Alpine Linux minirootfs"
        # Normal extraction for Alpine (small archive)
        extract_archive "$BUILD_DIR/$alpine_file" "$ROOTFS_DIR"
    else
        log "INFO" "Alpine Linux minirootfs already extracted"
    fi
    
    log "SUCCESS" "Alpine Linux prepared successfully"
}

# Download Linux kernel
download_kernel() {
    print_section "Downloading Linux kernel"
    
    # Use the version from 80_common.sh
    local kernel_version="$KERNEL_VERSION"
    local kernel_major=$(echo "$kernel_version" | cut -d. -f1)
    local kernel_file="linux-${kernel_version}.tar.xz"
    local kernel_url="https://cdn.kernel.org/pub/linux/kernel/v${kernel_major}.x/$kernel_file"
    
    log "INFO" "Using Linux kernel version: $kernel_version"
    
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
        log "INFO" "Extracting Linux kernel from $kernel_file"
        mkdir -p "$KERNEL_DIR"
        
        # Use optimized extraction for kernel (large archive)
        # Add true for skip_ownership to avoid the slow ownership changes for large kernel source
        log "INFO" "Using optimized extraction for kernel source (large archive)"
        extract_archive "$BUILD_DIR/$kernel_file" "$KERNEL_DIR" 1 true
        
        # Create a symlink pointing to the kernel directory
        ln -sf "linux" "linux-${kernel_version}" 2>/dev/null || true
        
        # Set up kernel permissions in a CI-friendly way
        log "INFO" "Setting up kernel build environment"
        # Use CI-friendly kernel permission handling
        if type handle_kernel_permissions &>/dev/null; then
            handle_kernel_permissions "$KERNEL_DIR"
        else
            # Fallback to direct method if the function isn't available
            if [ -f "$KERNEL_DIR/Makefile" ]; then
                chmod +x "$KERNEL_DIR/Makefile" 2>/dev/null || log "WARNING" "Could not change Makefile permissions, continuing anyway"
            fi
            # Process only the important files rather than recursively processing everything
            find "$KERNEL_DIR/scripts" -type f -name "*.sh" -exec chmod +x {} \; 2>/dev/null || log "WARNING" "Could not change script permissions, continuing anyway"
        fi
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
    
    # Use the version from 80_common.sh
    local zfs_version="$ZFS_VERSION"
    local zfs_file="zfs-${zfs_version}.tar.gz"
    local zfs_url="https://github.com/openzfs/zfs/releases/download/zfs-${zfs_version}/$zfs_file"
    
    log "INFO" "Using ZFS version: $zfs_version"
    
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
        log "INFO" "Extracting ZFS from $zfs_file"
        mkdir -p "$ZFS_DIR"
        
        # Use optimized extraction for ZFS (medium-sized archive)
        # We can keep ownership changes for ZFS since it's not as large as the kernel
        log "INFO" "Using optimized extraction for ZFS"
        extract_archive "$BUILD_DIR/$zfs_file" "$ZFS_DIR" 1
        
        # Make scripts executable
        if [ -f "$ZFS_DIR/autogen.sh" ]; then
            chmod +x "$ZFS_DIR/autogen.sh"
        fi
        if [ -f "$ZFS_DIR/configure" ]; then
            chmod +x "$ZFS_DIR/configure"
        fi
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
    
    # Set directory permissions for CI environments
    if is_github_actions; then
        log "INFO" "Setting GitHub Actions-specific permissions on kernel directory"
        chmod -R 777 "$KERNEL_DIR" 2>/dev/null || true
        sudo mkdir -p "$KERNEL_DIR/scripts/basic" "$KERNEL_DIR/include/config" 2>/dev/null || true
        sudo chmod -R 777 "$KERNEL_DIR/scripts" "$KERNEL_DIR/include" 2>/dev/null || true
        
        # Make sure .config is clean and writable
        if [ -f "$KERNEL_DIR/.config" ]; then
            sudo chmod 777 "$KERNEL_DIR/.config" 2>/dev/null || true
        else
            sudo touch "$KERNEL_DIR/.config" 2>/dev/null || true
            sudo chmod 777 "$KERNEL_DIR/.config" 2>/dev/null || true
        fi
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
    
    # Fix kernel permissions before building
    if type -t fix_kernel_permissions >/dev/null; then
        log "INFO" "Fixing kernel permissions before build"
        fix_kernel_permissions "$KERNEL_DIR"
    fi
    
    # In GitHub Actions, we need to ensure all required directories have the right permissions
    if is_github_actions; then
        log "INFO" "Setting GitHub Actions-specific permissions for build"
        sudo chmod -R 777 "$KERNEL_DIR/scripts" 2>/dev/null || true
        sudo mkdir -p "$KERNEL_DIR/scripts/basic" "$KERNEL_DIR/include/config" "$KERNEL_DIR/include/generated" 2>/dev/null || true
        sudo chmod -R 777 "$KERNEL_DIR/scripts/basic" "$KERNEL_DIR/include" 2>/dev/null || true
        
        # Fix configuration directories that are needed for syncconfig
        if [ -f "$KERNEL_DIR/.config" ]; then
            log "INFO" "Creating minimal configuration scaffold in GitHub Actions"
            
            # Create basic config files to help syncconfig
            sudo mkdir -p "$KERNEL_DIR/.tmp_versions" 2>/dev/null || true
            sudo touch "$KERNEL_DIR/include/config/auto.conf" 2>/dev/null || true
            sudo chmod -R 777 "$KERNEL_DIR/.tmp_versions" "$KERNEL_DIR/include/config" 2>/dev/null || true
            
            # Use the proper configuration file for GitHub Actions
            log "INFO" "Using standard kernel configuration for GitHub Actions"
            sudo chmod 777 "$KERNEL_DIR/.config" 2>/dev/null || true
        fi
    fi
    
    # Detect available system memory
    local available_memory_kb=0
    local total_cores=0
    
    # Detect available memory
    if [ -f "/proc/meminfo" ]; then
        available_memory_kb=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
    fi
    
    # If memory detection failed, try total memory with a reduction factor
    if [ "$available_memory_kb" -eq 0 ] && [ -f "/proc/meminfo" ]; then
        local total_memory_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
        available_memory_kb=$((total_memory_kb * 7 / 10)) # Use 70% of total memory
    fi
    
    # Convert to GB for display
    local available_memory_gb=$(awk "BEGIN {printf \"%.1f\", $available_memory_kb/1024/1024}")
    
    # Get optimal number of threads for building
    local threads=$(get_optimal_threads)
    log "INFO" "Building kernel with $threads threads"
    
    # Check kernel size before building
    local kernel_size=$(du -sh "$KERNEL_DIR" 2>/dev/null | cut -f1 || echo "unknown")
    log "INFO" "Kernel source size: $kernel_size"
    
    # Create swap file if memory is very low and USE_SWAP is enabled
    if [ "${USE_SWAP:-false}" = "true" ] && [ "$available_memory_kb" -gt 0 ] && [ "$available_memory_kb" -lt 4000000 ]; then  # < 4GB
        log "INFO" "Low memory detected (${available_memory_gb}GB). Creating temporary swap file..."
        
        local swap_size_mb=4096  # 4GB swap
        local swap_file="/tmp/onerecovery_swap"
        
        # Remove existing swap if present
        if [ -f "$swap_file" ]; then
            sudo swapoff "$swap_file" 2>/dev/null || true
            sudo rm -f "$swap_file"
        fi
        
        # Create new swap file
        log "INFO" "Allocating ${swap_size_mb}MB swap file at $swap_file"
        sudo dd if=/dev/zero of="$swap_file" bs=1M count="$swap_size_mb" status=progress 2>/dev/null || {
            log "WARNING" "Failed to create swap file. Continuing without swap."
        }
        
        if [ -f "$swap_file" ]; then
            sudo chmod 600 "$swap_file"
            sudo mkswap "$swap_file" >/dev/null 2>&1 || {
                log "WARNING" "Failed to format swap file. Continuing without swap."
                sudo rm -f "$swap_file"
            }
            
            sudo swapon "$swap_file" >/dev/null 2>&1 || {
                log "WARNING" "Failed to enable swap file. Continuing without swap."
                sudo rm -f "$swap_file"
            }
            
            # Re-read available memory with swap included
            sleep 1
            available_memory_kb=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
            available_memory_gb=$(awk "BEGIN {printf \"%.1f\", $available_memory_kb/1024/1024}")
            log "SUCCESS" "Swap file enabled. Available memory now: ${available_memory_gb}GB"
        fi
    fi
    
    # Calculate a safe number of threads based on available memory
    # Empirically, each compilation thread needs ~2GB for kernel compilation
    if [ "$available_memory_kb" -gt 0 ]; then
        local safe_threads=$(awk "BEGIN {print int($available_memory_kb/1024/1024/2)}")
        # Ensure at least 1 thread and no more than original THREADS
        safe_threads=$(( safe_threads < 1 ? 1 : safe_threads ))
        safe_threads=$(( safe_threads > threads ? threads : safe_threads ))
        
        if [ "$safe_threads" -lt "$threads" ]; then
            log "WARNING" "Limited available memory: ${available_memory_gb}GB. Reducing build threads from $threads to $safe_threads"
            threads=$safe_threads
        else
            log "INFO" "Available memory: ${available_memory_gb}GB. Using $threads threads"
        fi
    else
        log "WARNING" "Could not detect available memory. Using $threads threads, but may be risky"
    fi
    
    # Additional optimizations to reduce memory usage
    export KBUILD_BUILD_TIMESTAMP=$(date)
    # Reduce memory usage by disabling debugging symbols if memory is tight
    if [ "$available_memory_kb" -gt 0 ] && [ "$available_memory_kb" -lt 8000000 ]; then  # < 8GB
        log "INFO" "Low memory environment detected, using memory-saving options"
        export KCFLAGS="-g0 -Os"  # Optimize for size, omit debug info
    else
        export KCFLAGS="-O2"      # Default optimization
    fi
    
    # Enter kernel directory
    cd "$KERNEL_DIR"
    
    # Set kernel config interactively if requested
    if [ "${INTERACTIVE_CONFIG:-false}" = "true" ]; then
        log "INFO" "Using interactive kernel configuration"
        make menuconfig
    else
        log "INFO" "Using non-interactive kernel configuration"
        make olddefconfig
    fi
    
    # Determine verbosity level
    if [ "${MAKE_VERBOSE:-0}" = "1" ] || [ "${VERBOSE:-false}" = "true" ]; then
        local make_v="V=1"
        log "INFO" "Using verbose build output"
    else
        local make_v="V=0"
    fi
    
    # Build with compiler cache if available
    if [ "${USE_CACHE:-false}" = "true" ] && command -v ccache &> /dev/null; then
        log "INFO" "Using compiler cache for faster builds"
        nice -n 19 make $make_v -j$threads CC="ccache gcc" HOSTCC="ccache gcc" || {
            log "ERROR" "Kernel build failed"
            return 1
        }
    else
        nice -n 19 make $make_v -j$threads || {
            log "ERROR" "Kernel build failed"
            return 1
        }
    fi
    
    # Build modules
    log "INFO" "Building kernel modules"
    if [ "${USE_CACHE:-false}" = "true" ] && command -v ccache &> /dev/null; then
        nice -n 19 make $make_v modules -j$threads CC="ccache gcc" HOSTCC="ccache gcc" || {
            log "ERROR" "Module build failed"
            return 1
        }
    else
        nice -n 19 make $make_v modules -j$threads || {
            log "ERROR" "Module build failed"
            return 1
        }
    fi
    
    # Install modules
    log "INFO" "Installing kernel modules"
    INSTALL_MOD_PATH="$ROOTFS_DIR" make modules_install
    
    log "SUCCESS" "Kernel and modules built successfully"
    
    # Return to build directory
    cd "$BUILD_DIR"
    
    # Clean up swap file if we created one
    if [ "${USE_SWAP:-false}" = "true" ] && [ -f "/tmp/onerecovery_swap" ]; then
        log "INFO" "Removing temporary swap file"
        sudo swapoff "/tmp/onerecovery_swap" 2>/dev/null || true
        sudo rm -f "/tmp/onerecovery_swap"
        log "SUCCESS" "Swap file removed"
    fi
}

# Build ZFS modules
build_zfs() {
    if [ "$INCLUDE_ZFS" != "true" ]; then
        log "INFO" "Skipping ZFS build (disabled in configuration)"
        return 0
    fi
    
    print_section "Building ZFS"
    
    # Detect available system memory
    local available_memory_kb=0
    
    # Detect available memory
    if [ -f "/proc/meminfo" ]; then
        available_memory_kb=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
    fi
    
    # Convert to GB for display
    local available_memory_gb=$(awk "BEGIN {printf \"%.1f\", $available_memory_kb/1024/1024}")
    
    # Get optimal number of threads for building
    local threads=$(get_optimal_threads)
    log "INFO" "Building ZFS with $threads threads"
    
    # Apply memory-based optimizations for ZFS build
    if [ "$available_memory_kb" -gt 0 ] && [ "$available_memory_kb" -lt 8000000 ]; then  # < 8GB
        log "INFO" "Low memory environment detected, using memory-saving options for ZFS build"
        export CFLAGS="-g0 -Os"  # Optimize for size, omit debug info
    else
        export CFLAGS="-O2"      # Default optimization
    fi
    
    # Enter ZFS directory
    cd "$ZFS_DIR"
    
    # Use ccache for ZFS if enabled
    if [ "${USE_CACHE:-false}" = "true" ] && command -v ccache &> /dev/null; then
        log "INFO" "Using compiler cache for ZFS build"
        export CC="ccache gcc"
        export HOSTCC="ccache gcc"
    fi
    
    # Configure ZFS for the kernel
    log "INFO" "Configuring ZFS for the kernel"
    ./configure --with-linux="$KERNEL_DIR" --with-linux-obj="$KERNEL_DIR" --prefix=/fake || {
        log "ERROR" "ZFS configuration failed"
        return 1
    }
    
    # Determine verbosity level
    if [ "${MAKE_VERBOSE:-0}" = "1" ] || [ "${VERBOSE:-false}" = "true" ]; then
        local make_v="V=1"
        log "INFO" "Using verbose build output"
    else
        local make_v="V=0"
    fi
    
    # Build ZFS modules
    log "INFO" "Building ZFS modules"
    nice -n 19 make $make_v -j"$threads" -C module || {
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
    if [ "$INCLUDE_COMPRESSION" = "true" ]; then
        # Determine which compression tool to use
        COMPRESSION_TOOL="${COMPRESSION_TOOL:-upx}"
        log "INFO" "Selected compression tool: $COMPRESSION_TOOL"
        
        # Create a backup of the original file
        cp "$OUTPUT_DIR/OneRecovery.efi" "$OUTPUT_DIR/OneRecovery.efi.original"
        
        case "$COMPRESSION_TOOL" in
            "upx")
                if command -v upx &> /dev/null; then
                    # Apply UPX compression
                    log "INFO" "Compressing with UPX (faster decompression, good size reduction)..."
                    if upx --best --lzma "$OUTPUT_DIR/OneRecovery.efi"; then
                        COMPRESSED_SIZE=$(du -h "$OUTPUT_DIR/OneRecovery.efi" | cut -f1)
                        log "SUCCESS" "UPX compression successful"
                        log "INFO" "Original size: $original_size, Compressed size: $COMPRESSED_SIZE"
                    else
                        log "WARNING" "UPX compression failed, restoring original file"
                        mv "$OUTPUT_DIR/OneRecovery.efi.original" "$OUTPUT_DIR/OneRecovery.efi"
                    fi
                else
                    log "ERROR" "UPX not found. Please install UPX: apt-get install upx-ucl"
                    log "INFO" "Restoring original uncompressed file"
                    mv "$OUTPUT_DIR/OneRecovery.efi.original" "$OUTPUT_DIR/OneRecovery.efi"
                fi
                ;;
                
            "xz")
                if command -v xz &> /dev/null; then
                    # Apply XZ compression
                    log "INFO" "Compressing with XZ (higher compression ratio, slower decompression)..."
                    # Note: XZ compression would require a decompression stub in a real implementation
                    # This is a simplified version for demonstration
                    if xz -z -9 -e -f --keep "$OUTPUT_DIR/OneRecovery.efi"; then
                        # In a real implementation, we would need to prepend a decompression stub
                        # For now, we'll just rename the file
                        mv "$OUTPUT_DIR/OneRecovery.efi.xz" "$OUTPUT_DIR/OneRecovery.efi.compressed"
                        COMPRESSED_SIZE=$(du -h "$OUTPUT_DIR/OneRecovery.efi.compressed" | cut -f1)
                        log "WARNING" "XZ compression completed but requires a custom decompression stub"
                        log "INFO" "Original size: $original_size, Compressed size: $COMPRESSED_SIZE"
                        log "INFO" "Using original uncompressed file for compatibility"
                        mv "$OUTPUT_DIR/OneRecovery.efi.original" "$OUTPUT_DIR/OneRecovery.efi"
                    else
                        log "WARNING" "XZ compression failed, restoring original file"
                        mv "$OUTPUT_DIR/OneRecovery.efi.original" "$OUTPUT_DIR/OneRecovery.efi"
                    fi
                else
                    log "ERROR" "XZ not found. Please install XZ"
                    log "INFO" "Restoring original uncompressed file"
                    mv "$OUTPUT_DIR/OneRecovery.efi.original" "$OUTPUT_DIR/OneRecovery.efi"
                fi
                ;;
                
            "zstd")
                if command -v zstd &> /dev/null; then
                    # Apply ZSTD compression
                    log "INFO" "Compressing with ZSTD (balanced compression ratio and speed)..."
                    # Note: ZSTD compression would require a decompression stub in a real implementation
                    # This is a simplified version for demonstration
                    if zstd -19 -f "$OUTPUT_DIR/OneRecovery.efi" -o "$OUTPUT_DIR/OneRecovery.efi.zst"; then
                        # In a real implementation, we would need to prepend a decompression stub
                        # For now, we'll just rename the file
                        mv "$OUTPUT_DIR/OneRecovery.efi.zst" "$OUTPUT_DIR/OneRecovery.efi.compressed"
                        COMPRESSED_SIZE=$(du -h "$OUTPUT_DIR/OneRecovery.efi.compressed" | cut -f1)
                        log "WARNING" "ZSTD compression completed but requires a custom decompression stub"
                        log "INFO" "Original size: $original_size, Compressed size: $COMPRESSED_SIZE"
                        log "INFO" "Using original uncompressed file for compatibility"
                        mv "$OUTPUT_DIR/OneRecovery.efi.original" "$OUTPUT_DIR/OneRecovery.efi"
                    else
                        log "WARNING" "ZSTD compression failed, restoring original file"
                        mv "$OUTPUT_DIR/OneRecovery.efi.original" "$OUTPUT_DIR/OneRecovery.efi"
                    fi
                else
                    log "ERROR" "ZSTD not found. Please install ZSTD"
                    log "INFO" "Restoring original uncompressed file"
                    mv "$OUTPUT_DIR/OneRecovery.efi.original" "$OUTPUT_DIR/OneRecovery.efi"
                fi
                ;;
                
            *)
                log "ERROR" "Unknown compression tool: $COMPRESSION_TOOL"
                log "INFO" "Restoring original uncompressed file"
                mv "$OUTPUT_DIR/OneRecovery.efi.original" "$OUTPUT_DIR/OneRecovery.efi"
                ;;
        esac
        
        # Clean up backup if it exists
        rm -f "$OUTPUT_DIR/OneRecovery.efi.original"
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
    
    # Print a summary of the build
    print_section "Build Summary"
    log "SUCCESS" "OneRecovery build completed successfully!"
    
    if [ -f "$OUTPUT_DIR/OneRecovery.efi" ]; then
        local file_size=$(du -h "$OUTPUT_DIR/OneRecovery.efi" | cut -f1)
        log "SUCCESS" "Created OneRecovery.efi (Size: $file_size)"
        log "INFO" "EFI file: $OUTPUT_DIR/OneRecovery.efi"
        
        # Show included features
        log "INFO" "Included features:"
        [ "$INCLUDE_ZFS" = "true" ] && log "INFO" "  - ZFS filesystem support"
        [ "$INCLUDE_BTRFS" = "true" ] && log "INFO" "  - Btrfs filesystem support"
        [ "$INCLUDE_RECOVERY_TOOLS" = "true" ] && log "INFO" "  - Data recovery tools"
        [ "$INCLUDE_NETWORK_TOOLS" = "true" ] && log "INFO" "  - Network tools"
        [ "$INCLUDE_CRYPTO" = "true" ] && log "INFO" "  - Encryption support"
        [ "$INCLUDE_TUI" = "true" ] && log "INFO" "  - Text User Interface"
        
        # Show build configuration
        log "INFO" ""
        log "INFO" "Build configuration:"
        if [ "$INCLUDE_MINIMAL_KERNEL" = "true" ]; then
            log "INFO" "  - Kernel: Minimal (optimized for size)"
        else
            log "INFO" "  - Kernel: Standard"
        fi
        
        if [ "$INCLUDE_COMPRESSION" = "true" ]; then
            log "INFO" "  - Compression: Enabled (using ${COMPRESSION_TOOL:-upx})"
        else
            log "INFO" "  - Compression: Disabled"
        fi
        
        # Show cache information if used
        if [ "${USE_CACHE:-false}" = "true" ] && command -v ccache &> /dev/null; then
            log "INFO" ""
            log "INFO" "Compiler cache statistics:"
            ccache -s | grep -E 'cache hit|cache miss|cache size' | while read line; do
                log "INFO" "  $line"
            done
        fi
    else
        log "ERROR" "Output file not found. Build may have failed silently."
        exit 1
    fi
}

# Run the main function
main "$@"