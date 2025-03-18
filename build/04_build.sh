#!/bin/bash
#
# Build Linux kernel and create EFI file
#
# Core build process that compiles the kernel and produces the EFI file
#
set -e

# Define script name for error handling
SCRIPT_NAME=$(basename "$0")

# Determine the absolute path to the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the core library first (required)
if [ ! -f "${SCRIPT_DIR}/80_common.sh" ]; then
    echo "ERROR: Critical library file not found: ${SCRIPT_DIR}/80_common.sh"
    exit 1
fi
source "${SCRIPT_DIR}/80_common.sh"

# Source all library scripts using the source_libraries function
source_libraries "${SCRIPT_DIR}"

# Initialize script with standard header (prints banner)
initialize_script

# Define paths
BUILD_DIR="$SCRIPT_DIR"
ROOTFS_DIR="$BUILD_DIR/alpine-minirootfs"
KERNEL_DIR="$BUILD_DIR/linux"
ZFS_DIR="$BUILD_DIR/zfs"
ZFILES_DIR="$BUILD_DIR/zfiles"
OUTPUT_DIR="$BUILD_DIR/../output"

# Process command line arguments
parse_args() {
    # Default settings
    BUILD_TYPE="standard"
    
    # Optional components
    INCLUDE_MINIMAL_KERNEL="${INCLUDE_MINIMAL_KERNEL:-false}"
    INCLUDE_ZFS="${INCLUDE_ZFS:-true}"
    INCLUDE_BTRFS="${INCLUDE_BTRFS:-false}"
    INCLUDE_RECOVERY_TOOLS="${INCLUDE_RECOVERY_TOOLS:-true}"
    INCLUDE_NETWORK_TOOLS="${INCLUDE_NETWORK_TOOLS:-true}"
    INCLUDE_CRYPTO="${INCLUDE_CRYPTO:-true}"
    INCLUDE_TUI="${INCLUDE_TUI:-true}"
    INCLUDE_COMPRESSION="${INCLUDE_COMPRESSION:-true}"
    COMPRESSION_TOOL="${COMPRESSION_TOOL:-upx}"
    
    # Build performance options
    USE_CACHE="${USE_CACHE:-false}"
    USE_SWAP="${USE_SWAP:-false}"
    INTERACTIVE_CONFIG="${INTERACTIVE_CONFIG:-false}"
    MAKE_VERBOSE="${MAKE_VERBOSE:-0}"
    
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
            --minimal-kernel)
                INCLUDE_MINIMAL_KERNEL=true
                shift
                ;;
            --standard-kernel)
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
    log "INFO" "- Minimal kernel: $(bool_to_str "$INCLUDE_MINIMAL_KERNEL")"
    log "INFO" "- ZFS support: $(bool_to_str "$INCLUDE_ZFS")"
    log "INFO" "- Btrfs support: $(bool_to_str "$INCLUDE_BTRFS")"
    log "INFO" "- Recovery tools: $(bool_to_str "$INCLUDE_RECOVERY_TOOLS")"
    log "INFO" "- Network tools: $(bool_to_str "$INCLUDE_NETWORK_TOOLS")"
    log "INFO" "- Crypto support: $(bool_to_str "$INCLUDE_CRYPTO")"
    log "INFO" "- Text User Interface: $(bool_to_str "$INCLUDE_TUI")"
    log "INFO" "- Compression: $(bool_to_str "$INCLUDE_COMPRESSION")"
    
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

# Get optimal number of threads for building
get_optimal_threads() {
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
    
    # Detect total cores
    total_cores=$(nproc 2>/dev/null || echo 2)
    
    # Calculate a safe number of threads based on available memory
    # Empirically, each compilation thread needs ~2GB for kernel compilation
    if [ "$available_memory_kb" -gt 0 ]; then
        local safe_threads=$(awk "BEGIN {print int($available_memory_kb/1024/1024/2)}")
        
        # Ensure at least 1 thread and no more than total cores
        safe_threads=$(( safe_threads < 1 ? 1 : safe_threads ))
        safe_threads=$(( safe_threads > total_cores ? total_cores : safe_threads ))
        
        echo "$safe_threads"
    else
        # Default to the number of cores or a reasonable number if memory detection failed
        if [ -n "${BUILD_JOBS:-}" ]; then
            echo "${BUILD_JOBS}"
        else
            echo "$total_cores"
        fi
    fi
}

# Build the kernel and modules
build_kernel() {
    print_section "Building Linux kernel"
    
    # Environment-aware build adjustments
    if is_github_actions; then
        log "INFO" "Running in GitHub Actions environment"
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
    
    # Get optimized compiler flags based on memory conditions
    export KCFLAGS=$(get_memory_optimized_cflags)
    
    # Apply GitHub Actions additional optimizations if needed
    if is_github_actions && [ "$available_memory_kb" -lt 4000000 ]; then
        log "WARNING" "GitHub Actions with low memory - applying additional optimizations"
        # Tell the kernel build system to minimize memory usage at the cost of build time
        export KBUILD_LOW_MEMORY=1
        export CFLAGS="${CFLAGS:-} -Wl,--as-needed"
    fi
    
    # Enter kernel directory
    cd "$KERNEL_DIR"
    
    # Check directory permissions before building
    log "INFO" "Checking kernel source directory permissions"
    local perm_ok=true
    
    # Test if we can write to critical directories
    for test_dir in "." "include" "drivers" "arch/x86" "scripts"; do
        if [ -d "$test_dir" ] && ! touch "$test_dir/.write_test" 2>/dev/null; then
            log "WARNING" "Cannot write to $test_dir directory, fixing permissions"
            if is_restricted_environment; then
                sudo chmod -R u+w "$test_dir" 2>/dev/null || true
            else
                chmod -R u+w "$test_dir" 2>/dev/null || true
            fi
            perm_ok=false
        elif [ -f "$test_dir/.write_test" ]; then
            rm -f "$test_dir/.write_test"
        fi
    done
    
    # If permissions were fixed, check again
    if [ "$perm_ok" = "false" ]; then
        log "INFO" "Fixed permissions, re-checking..."
        if ! touch "./.write_test" 2>/dev/null; then
            log "ERROR" "Still cannot write to kernel source directory after fixing permissions"
            if is_github_actions; then
                log "INFO" "In GitHub Actions environment, using elevated permissions for build"
            fi
        else
            rm -f "./.write_test"
            log "SUCCESS" "Successfully fixed permissions"
        fi
    fi
    
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
        log "INFO" "Make command: make $make_v -j$threads CC=\"ccache gcc\" HOSTCC=\"ccache gcc\""
        
        # Use a wrapper for improved error handling
        nice -n 19 make $make_v -j$threads CC="ccache gcc" HOSTCC="ccache gcc" 2>&1 | tee kernel_build.log || {
            log "ERROR" "Kernel build failed"
            
            # Check build log for common errors
            if grep -q "No space left on device" kernel_build.log; then
                log "ERROR" "Build failed due to insufficient disk space!"
            elif grep -q "Permission denied" kernel_build.log; then
                log "ERROR" "Build failed due to permission issues! Try running in a privileged container."
            elif grep -q "virtual memory exhausted" kernel_build.log || grep -q "Killed" kernel_build.log; then
                log "ERROR" "Build failed due to insufficient memory! Try reducing the number of threads or add more RAM."
            fi
            
            return 1
        }
    else
        log "INFO" "Make command: make $make_v -j$threads"
        nice -n 19 make $make_v -j$threads 2>&1 | tee kernel_build.log || {
            log "ERROR" "Kernel build failed"
            
            # Check build log for common errors
            if grep -q "No space left on device" kernel_build.log; then
                log "ERROR" "Build failed due to insufficient disk space!"
            elif grep -q "Permission denied" kernel_build.log; then
                log "ERROR" "Build failed due to permission issues! Try running in a privileged container."
            elif grep -q "virtual memory exhausted" kernel_build.log || grep -q "Killed" kernel_build.log; then
                log "ERROR" "Build failed due to insufficient memory! Try reducing the number of threads or add more RAM."
            fi
            
            return 1
        }
    fi
    
    # Clean up log file
    rm -f kernel_build.log
    
    # Build modules
    log "INFO" "Building kernel modules"
    if [ "${USE_CACHE:-false}" = "true" ] && command -v ccache &> /dev/null; then
        log "INFO" "Make modules command: make $make_v modules -j$threads"
        
        # Use a wrapper for improved error handling
        nice -n 19 make $make_v modules -j$threads CC="ccache gcc" HOSTCC="ccache gcc" 2>&1 | tee module_build.log || {
            log "ERROR" "Module build failed"
            
            # Check build log for common errors
            if grep -q "No space left on device" module_build.log; then
                log "ERROR" "Module build failed due to insufficient disk space!"
            elif grep -q "Permission denied" module_build.log; then
                log "ERROR" "Module build failed due to permission issues!"
            elif grep -q "virtual memory exhausted" module_build.log || grep -q "Killed" module_build.log; then
                log "ERROR" "Module build failed due to insufficient memory!"
            fi
            
            return 1
        }
    else
        log "INFO" "Make modules command: make $make_v modules -j$threads"
        nice -n 19 make $make_v modules -j$threads 2>&1 | tee module_build.log || {
            log "ERROR" "Module build failed"
            
            # Check build log for common errors
            if grep -q "No space left on device" module_build.log; then
                log "ERROR" "Module build failed due to insufficient disk space!"
            elif grep -q "Permission denied" module_build.log; then
                log "ERROR" "Module build failed due to permission issues!"
            elif grep -q "virtual memory exhausted" module_build.log || grep -q "Killed" module_build.log; then
                log "ERROR" "Module build failed due to insufficient memory!"
            fi
            
            return 1
        }
    fi
    
    # Clean up log file
    rm -f module_build.log
    
    # Install modules
    log "INFO" "Installing kernel modules"
    log "INFO" "Make modules_install command: make $make_v INSTALL_MOD_PATH=\"$ROOTFS_DIR\" modules_install"
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
    
    # Get optimized compiler flags based on memory conditions
    export CFLAGS=$(get_memory_optimized_cflags)
    
    # Enter ZFS directory
    cd "$ZFS_DIR"
    
    # Use ccache for ZFS if enabled
    if [ "${USE_CACHE:-false}" = "true" ] && command -v ccache &> /dev/null; then
        log "INFO" "Using compiler cache for ZFS build"
        export CC="ccache gcc"
        export HOSTCC="ccache gcc"
    fi
    
    # Check for required development packages
    log "INFO" "Checking for RPC development libraries"
    if [ -f "/usr/include/rpc/xdr.h" ]; then
        log "INFO" "Found system RPC headers in /usr/include/rpc/"
    elif [ -f "/usr/include/tirpc/rpc/xdr.h" ]; then
        log "INFO" "Found libtirpc headers in /usr/include/tirpc/"
    else
        # List installed packages for debugging
        if command -v dpkg-query > /dev/null; then
            log "INFO" "Installed packages containing 'rpc' or 'tirpc':"
            dpkg-query -W "*rpc*" "*tirpc*" || true
        fi
        
        # Check paths for RPC headers
        log "INFO" "Searching for RPC headers..."
        find /usr/include -name "xdr.h" || true
    fi
    
    # Verify kernel config has the required ZFS dependencies
    # The proper overlays should have already been applied by 03_conf.sh
    log "INFO" "Verifying kernel config has required ZFS dependencies"
    
    # Check for critical ZFS dependencies
    if [ ! -f "$KERNEL_DIR/.config" ]; then
        log "ERROR" "Kernel config file not found at $KERNEL_DIR/.config"
        log "INFO" "Please run 03_conf.sh before 04_build.sh"
        return 1
    fi
    
    # Check for CONFIG_MODULES which is essential for ZFS
    if ! grep -q "^CONFIG_MODULES=y" "$KERNEL_DIR/.config"; then
        log "ERROR" "CONFIG_MODULES=y not found in kernel config"
        log "INFO" "Please run 03_conf.sh with ZFS support enabled"
        log "INFO" "This should have been applied by the ZFS overlay in 03_conf.sh"
        return 1
    fi
    
    # Check for ZLIB_DEFLATE which is needed for ZFS
    if ! grep -q "^CONFIG_ZLIB_DEFLATE=y" "$KERNEL_DIR/.config"; then
        log "ERROR" "CONFIG_ZLIB_DEFLATE=y not found in kernel config"
        log "INFO" "Please run 03_conf.sh with ZFS support enabled"
        log "INFO" "This should have been applied by the ZFS overlay in 03_conf.sh"
        return 1
    fi
    
    log "SUCCESS" "Kernel has required ZFS dependencies configured"
    
    # Prepare kernel modules build system if needed
    log "INFO" "Preparing kernel modules build system"
    (cd "$KERNEL_DIR" && make modules_prepare) || {
        log "WARNING" "modules_prepare failed, ZFS module build may not work correctly"
    }
    
    # Configure ZFS for the kernel with verbose output
    log "INFO" "Configuring ZFS for the kernel"
    ./configure --with-linux="$KERNEL_DIR" --with-linux-obj="$KERNEL_DIR" --prefix=/fake --enable-debug || {
        log "ERROR" "ZFS configuration failed"
        
        # Print full kernel config for debugging
        log "INFO" "Kernel config dump for debugging:"
        head -n 50 "$KERNEL_DIR/.config"
        
        # Check for critical configs
        log "INFO" "Checking for critical ZFS dependencies in kernel config:"
        grep -E "CONFIG_ZLIB_DEFLATE=|CONFIG_MODULES=|CONFIG_SPL=|CONFIG_ZFS=" "$KERNEL_DIR/.config" || true
        
        # Print the config.log file for debugging
        if [ -f "config.log" ]; then
            log "INFO" "Contents of config.log:"
            cat config.log | grep -E "rpc|tirpc|xdr|error|warning|CONFIG_MODULES|support|ZLIB" || true
            
            # Find the specific error message about modules
            log "INFO" "Searching for module error messages:"
            grep -A 5 "checking whether CONFIG_MODULES is defined" config.log || true
            
            # Search for ZLIB errors
            log "INFO" "Searching for ZLIB error messages:"
            grep -A 5 "checking.*ZLIB" config.log || true
        fi
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
    depmod -b "$ROOTFS_DIR" -F System.map "$kernel_version" || true
    
    # Create EFI file
    log "INFO" "Creating OneRecovery.efi"
    cp arch/x86/boot/bzImage "$OUTPUT_DIR/OneRecovery.efi" || {
        log "ERROR" "Failed to find kernel bzImage"
        return 1
    }
    
    # If building as root, fix permissions on the output directory
    if [ "${BUILD_AS_ROOT:-false}" = "true" ]; then
        log "INFO" "Fixing permissions on output directory after root build"
        if [ -n "$SUDO_UID" ] && [ -n "$SUDO_GID" ]; then
            # We're running with sudo, fix ownership to the original user
            chown -R "$SUDO_UID:$SUDO_GID" "$OUTPUT_DIR" || true
        elif [ -n "$RUNNER_UID" ]; then
            # GitHub Actions specific handling
            chown -R "$RUNNER_UID:$RUNNER_GID" "$OUTPUT_DIR" || true
        else
            # Fallback to making everything world-writable
            chmod -R 777 "$OUTPUT_DIR" || true
        fi
    fi
    
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


# Timing functions are now provided by 80_common.sh

# Main function
main() {
    # Set up the timing log file with absolute path
    TIMING_LOG_FILE="${BUILD_DIR}/build_timing.log"
    export TIMING_LOG_FILE
    
    # Reset timing log for a clean run
    rm -f "$TIMING_LOG_FILE"
    
    # Print environment information if the function exists
    if type print_environment_info &>/dev/null; then
        print_environment_info
    fi
    
    # Parse command line arguments
    start_timing "Argument parsing"
    parse_args "$@"
    end_timing
    
    # Make sure we're in the build directory
    cd "$BUILD_DIR"
    
    # Verify prerequisites - no fallbacks, just fail with clear error messages
    start_timing "Prerequisite verification"
    if [ ! -d "$ROOTFS_DIR" ]; then
        log "ERROR" "Alpine rootfs directory not found: $ROOTFS_DIR"
        log "INFO" "Please run the complete build sequence:"
        log "INFO" "cd build && ./01_get.sh && ./02_chrootandinstall.sh && ./03_conf.sh"
        exit 1
    fi
    
    # Verify the kernel sources exist
    if [ ! -d "$KERNEL_DIR" ]; then
        log "ERROR" "Kernel directory not found: $KERNEL_DIR"
        log "INFO" "Please run 01_get.sh first"
        exit 1
    fi
    
    # Verify ZFS if enabled
    if [ "$INCLUDE_ZFS" = "true" ] && [ ! -d "$ZFS_DIR" ]; then
        log "ERROR" "ZFS directory not found: $ZFS_DIR"
        log "INFO" "Please run 01_get.sh first with ZFS support enabled"
        exit 1
    fi
    
    # Make sure kernel is configured
    if [ ! -f "$KERNEL_DIR/.config" ]; then
        log "ERROR" "Kernel configuration not found: $KERNEL_DIR/.config"
        log "INFO" "Please run 03_conf.sh first"
        exit 1
    fi
    end_timing
    
    # Build kernel
    start_timing "Kernel build"
    build_kernel || {
        log "ERROR" "Kernel build failed"
        exit 1
    }
    end_timing
    
    # Build ZFS if enabled
    if [ "$INCLUDE_ZFS" = "true" ]; then
        start_timing "ZFS build"
        build_zfs || {
            log "ERROR" "ZFS build failed"
            exit 1
        }
        end_timing
    fi
    
    # Create EFI file
    start_timing "EFI file creation"
    create_efi || {
        log "ERROR" "Failed to create EFI file"
        exit 1
    }
    end_timing
    
    # Finalize timing log with summary (only if this is the final script)
    if [ "${FINALIZE_TIMING_LOG:-false}" = "true" ]; then
        finalize_timing_log
    fi
    
    # Print build summary
    print_section "Build Summary"
    log "SUCCESS" "Build completed successfully!"
    log "INFO" "Detailed timing log saved to: ${TIMING_LOG_FILE}"
    
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

# Execute main function with all arguments
main "$@"
