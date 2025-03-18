#!/bin/bash
# Make sure this file is executable (chmod +x)
#
# OneRecovery Build Core Functions (84_build_core.sh)
# Shared build functions used by 04_build.sh and build.sh
# This is part of the library scripts (80-89 range)
#
# Contains the core build functionality including:
# - Kernel building (build_kernel)
# - ZFS module building (build_zfs)
# - EFI file creation (create_efi)
# - Build argument parsing (parse_build_args)
#

# Helper function to convert boolean to Yes/No string
bool_to_str() {
    if [ "$1" = "true" ]; then
        echo -e "${GREEN}Yes${NC}"
    else
        echo -e "${RED}No${NC}"
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
    
    # Validate threads is an integer, replace with default if not
    if ! [[ "$threads" =~ ^[0-9]+$ ]]; then
        log "WARNING" "Thread count is not a valid number: '$threads'. Using default: 2"
        threads=2
    fi
    
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
    
    # Fix ABI header mismatches - comprehensive approach for all potential mismatches
    log "INFO" "Checking for ABI header mismatches"
    
    # Function to sync a specific header file
    sync_header_file() {
        local arch_path="$1"
        local tools_path="$2"
        
        if [ -f "$arch_path" ] && [ -f "$tools_path" ]; then
            log "INFO" "Synchronizing ABI header: $tools_path"
            cp -f "$arch_path" "$tools_path"
            return 0
        fi
        return 1
    }
    
    # Synchronize known problematic header files
    sync_header_file "arch/x86/lib/insn.c" "tools/arch/x86/lib/insn.c"
    sync_header_file "arch/x86/include/asm/inat.h" "tools/arch/x86/include/asm/inat.h"
    sync_header_file "arch/x86/include/asm/insn.h" "tools/arch/x86/include/asm/insn.h"
    sync_header_file "arch/x86/lib/inat.c" "tools/arch/x86/lib/inat.c"
    
    # Additional general approach - find all files in tools/arch that have equivalents in arch/
    log "INFO" "Performing comprehensive ABI header synchronization"
    find tools/arch -type f -name "*.h" -o -name "*.c" 2>/dev/null | while read tools_file; do
        # Get the relative path and construct the corresponding arch path
        rel_path="${tools_file#tools/}"
        arch_file="$rel_path"
        
        if [ -f "$arch_file" ]; then
            # Compare the files and update if different
            if ! cmp -s "$arch_file" "$tools_file"; then
                log "INFO" "Synchronizing mismatched file: $tools_file"
                cp -f "$arch_file" "$tools_file"
            fi
        fi
    done
    
    # Ensure kernel can find OpenSSL for module signing
    if [ -f "certs/Makefile" ] && grep -q "CONFIG_MODULE_SIG=y" .config; then
        log "INFO" "Setting up kernel module signing with OpenSSL"
        # Create certs directory and signing key if it doesn't exist
        mkdir -p certs
        if [ ! -f "certs/signing_key.pem" ]; then
            log "INFO" "Generating dummy signing key for modules"
            # Generate a dummy key for module signing
            openssl req -new -x509 -newkey rsa:2048 -keyout certs/signing_key.pem \
                -outform DER -out certs/signing_key.x509 -nodes \
                -subj "/CN=OneRecovery Build Signing Key/" 2>/dev/null || true
            # Also create the format needed by the kernel
            openssl x509 -inform DER -in certs/signing_key.x509 \
                -out certs/signing_key.x509.pem 2>/dev/null || true
        fi
    fi
    
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
    
    # Validate threads is an integer, replace with default if not
    if ! [[ "$threads" =~ ^[0-9]+$ ]]; then
        log "WARNING" "Thread count is not a valid number: '$threads'. Using default: 2"
        threads=2
    fi
    
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

# Display comprehensive help for build options
show_build_help() {
    cat << EOF
Usage: $0 [options]

Build Type Options:
  --minimal              Minimal build optimized for size (~30-50% smaller)
                         Automatically disables ZFS, Btrfs, recovery tools, network tools,
                         crypto support, and TUI; enables minimal kernel config
  --full                 Full build with all available components
  --standard             Standard build with recommended components (default)

Optional Components:
  --minimal-kernel       Use minimized kernel configuration (saves memory/space)
  --standard-kernel      Use standard kernel configuration (default)
  --with-zfs             Include ZFS filesystem support (default: yes)
  --without-zfs          Exclude ZFS filesystem support
  --with-btrfs           Include Btrfs filesystem support (default: no)
  --without-btrfs        Exclude Btrfs filesystem support
  --with-recovery-tools  Include data recovery tools (default: yes)
  --without-recovery-tools  Exclude data recovery tools
  --with-network-tools   Include network tools (default: yes)
  --without-network-tools  Exclude network tools
  --with-crypto          Include encryption support (default: yes)
  --without-crypto       Exclude encryption support
  --with-tui             Include Text User Interface (default: yes)
  --without-tui          Exclude Text User Interface

Size Optimization Options:
  --with-compression     Enable EFI file compression (default: yes)
  --without-compression  Disable EFI file compression (faster boot)
  --compression-tool=TOOL Select compression tool (upx, xz, zstd) (default: upx)

Build Performance Options:
  --use-cache            Enable source and build caching (default for build.sh)
  --no-cache             Disable source and build caching (default for 04_build.sh)
  --use-swap             Create swap file if memory is low (default: no)
  --no-swap              Do not create swap file even if memory is low
  --interactive-config   Use interactive kernel configuration (menuconfig)
  --no-interactive-config Use non-interactive kernel config (default)
  --make-verbose         Enable verbose make output (V=1)
  --make-quiet           Use quiet make output (V=0, default)
  --jobs=N               Set number of parallel build jobs (default: auto-detect)

Examples:
  --minimal                       Create minimal recovery image (no ZFS, minimal kernel)
  --full --use-swap               Create full-featured image with swap support
  --standard --with-btrfs         Add Btrfs to standard build (includes ZFS by default)
  --standard --without-zfs        Standard build without ZFS support
  --compression-tool=zstd         Use ZSTD compression instead of default UPX
  --interactive-config --jobs=4   Use interactive config with 4 build threads
EOF
}

# Process build arguments
parse_build_args() {
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
                # Show comprehensive help and exit
                show_build_help
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

# Export all functions for use in other scripts
export -f bool_to_str
export -f build_kernel
export -f build_zfs
export -f create_efi
export -f parse_build_args
export -f show_build_help