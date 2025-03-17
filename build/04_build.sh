#!/bin/bash
#
# Build Linux kernel and create EFI file
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

# RootFS variables
ROOTFS="alpine-minirootfs"
CACHEPATH="$ROOTFS/var/cache/apk/"
SHELLHISTORY="$ROOTFS/root/.ash_history"
DEVCONSOLE="$ROOTFS/dev/console"
MODULESPATH="$ROOTFS/lib/modules/"
DEVURANDOM="$ROOTFS/dev/urandom"

# Kernel variables
KERNELVERSION="$(ls -d linux-* | awk '{print $1}' | head -1 | cut -d- -f2)"
KERNELPATH="linux"
export INSTALL_MOD_PATH="../$ROOTFS/"

# Set optimal number of build threads
# Use the specified number of jobs, or autodetect from CPU count
if [ -n "${BUILD_JOBS:-}" ] && [ "${BUILD_JOBS:-0}" -gt 0 ]; then
    THREADS=$BUILD_JOBS
    log "INFO" "Using specified number of build jobs: $THREADS"
else
    # Default: Use number of cores for optimal performance 
    THREADS=$(getconf _NPROCESSORS_ONLN)
    log "INFO" "Auto-detected number of build jobs: $THREADS"
fi

# Print banner
echo "      ____________  "
echo "    /|------------| "
echo "   /_|  .---.     | "
echo "  |    /     \    | "
echo "  |    \.6-6./    | "
echo "  |    /\`\_/\`\    | "
echo "  |   //  _  \\\   | "
echo "  |  | \     / |  | "
echo "  | /\`\_\`>  <_/\`\ | "
echo "  | \__/'---'\__/ | "
echo "  |_______________| "
echo "                    "
echo "   OneRecovery.efi  "

# Initialize build type message based on configuration
if [ "${INCLUDE_MINIMAL_KERNEL:-false}" = "true" ]; then
    log "INFO" "Building minimal kernel version (optimized for size)"
else
    log "INFO" "Building standard kernel version"
fi

##########################
# Checking root filesystem
##########################

echo "----------------------------------------------------"
echo -e "Checking root filesystem\n"

# Clearing apk cache 
if [ "$(ls -A $CACHEPATH)" ]; then 
    echo -e "Apk cache folder is not empty: $CACHEPATH \nRemoving cache...\n"
    rm $CACHEPATH*
fi

# Remove shell history
if [ -f $SHELLHISTORY ]; then
    echo -e "Shell history found: $SHELLHISTORY \nRemoving history file...\n"
    rm $SHELLHISTORY
fi

# Clearing kernel modules folder
if [ -d "$MODULESPATH" ]; then
    if [ "$(ls -A $MODULESPATH 2>/dev/null)" ]; then 
        echo -e "Kernel modules folder is not empty: $MODULESPATH \nRemoving modules...\n"
        rm -r $MODULESPATH*
    fi
else
    echo -e "Kernel modules folder doesn't exist yet: $MODULESPATH \nWill be created during installation.\n"
    # Create the directory structure in advance
    mkdir -p $MODULESPATH
fi

# Removing dev bindings
if [ -e $DEVURANDOM ]; then
    echo -e "/dev/ bindings found: $DEVURANDOM. Unmounting...\n"
    umount $DEVURANDOM || echo -e "Not mounted. \n"
    rm $DEVURANDOM
fi


## Check if console character file exist
#if [ ! -e $DEVCONSOLE ]; then
#    echo -e "ERROR: Console device does not exist: $DEVCONSOLE \nPlease create device file:  mknod -m 600 $DEVCONSOLE c 5 1"
#    exit 1
#else
#    if [ -d $DEVCONSOLE ]; then # Check that console device is not a folder 
#        echo -e  "ERROR: Console device is a folder: $DEVCONSOLE \nPlease create device file:  mknod -m 600 $DEVCONSOLE c 5 1"
#        exit 1
#    fi
#
#    if [ -f $DEVCONSOLE ]; then # Check that console device is not a regular file
#        echo -e "ERROR: Console device is a regular: $DEVCONSOLE \nPlease create device file:  mknod -m 600 $DEVCONSOLE c 5 1"
#    fi
#fi

# Print rootfs uncompressed size
echo -e "Uncompressed root filesystem size WITHOUT kernel modules: $(du -sh $ROOTFS | cut -f1)\n"


cd $KERNELPATH 

##########################
# Building kernel
##########################
echo "----------------------------------------------------"
log "INFO" "Building kernel with initramfs using $THREADS threads"

# Detect available system memory and adjust threads if needed
AVAILABLE_MEM_KB=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
AVAILABLE_MEM_GB=$(awk "BEGIN {printf \"%.1f\", $AVAILABLE_MEM_KB/1024/1024}")

# Create swap file if memory is very low and USE_SWAP is enabled
if [ "${USE_SWAP:-false}" = "true" ] && [ "$AVAILABLE_MEM_KB" -gt 0 ] && [ "$AVAILABLE_MEM_KB" -lt 4000000 ]; then  # < 4GB
    log "INFO" "Low memory detected (${AVAILABLE_MEM_GB}GB). Creating temporary swap file..."
    
    SWAP_SIZE_MB=4096  # 4GB swap
    SWAP_FILE="/tmp/onerecovery_swap"
    
    # Remove existing swap if present
    if [ -f "$SWAP_FILE" ]; then
        sudo swapoff "$SWAP_FILE" 2>/dev/null || true
        sudo rm -f "$SWAP_FILE"
    fi
    
    # Create new swap file
    log "INFO" "Allocating ${SWAP_SIZE_MB}MB swap file at $SWAP_FILE"
    sudo dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE_MB" status=progress 2>/dev/null || {
        log "WARNING" "Failed to create swap file. Continuing without swap."
    }
    
    if [ -f "$SWAP_FILE" ]; then
        sudo chmod 600 "$SWAP_FILE"
        sudo mkswap "$SWAP_FILE" >/dev/null 2>&1 || {
            log "WARNING" "Failed to format swap file. Continuing without swap."
            sudo rm -f "$SWAP_FILE"
        }
        
        sudo swapon "$SWAP_FILE" >/dev/null 2>&1 || {
            log "WARNING" "Failed to enable swap file. Continuing without swap."
            sudo rm -f "$SWAP_FILE"
        }
        
        # Re-read available memory with swap included
        sleep 1
        AVAILABLE_MEM_KB=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
        AVAILABLE_MEM_GB=$(awk "BEGIN {printf \"%.1f\", $AVAILABLE_MEM_KB/1024/1024}")
        log "SUCCESS" "Swap file enabled. Available memory now: ${AVAILABLE_MEM_GB}GB"
    fi
fi

# Calculate a safe number of threads based on available memory
# Empirically, each compilation thread needs ~2GB for kernel compilation
if [ "$AVAILABLE_MEM_KB" -gt 0 ]; then
    SAFE_THREADS=$(awk "BEGIN {print int($AVAILABLE_MEM_KB/1024/1024/2)}")
    # Ensure at least 1 thread and no more than original THREADS
    SAFE_THREADS=$(( SAFE_THREADS < 1 ? 1 : SAFE_THREADS ))
    SAFE_THREADS=$(( SAFE_THREADS > THREADS ? THREADS : SAFE_THREADS ))
    
    if [ "$SAFE_THREADS" -lt "$THREADS" ]; then
        log "WARNING" "Limited available memory: ${AVAILABLE_MEM_GB}GB. Reducing build threads from $THREADS to $SAFE_THREADS"
        THREADS=$SAFE_THREADS
    else
        log "INFO" "Available memory: ${AVAILABLE_MEM_GB}GB. Using $THREADS threads"
    fi
else
    log "WARNING" "Could not detect available memory. Using $THREADS threads, but may be risky"
fi

# Additional optimizations to reduce memory usage
export KBUILD_BUILD_TIMESTAMP=$(date)
# Reduce memory usage by disabling debugging symbols if memory is tight
if [ "$AVAILABLE_MEM_KB" -gt 0 ] && [ "$AVAILABLE_MEM_KB" -lt 8000000 ]; then  # < 8GB
    log "INFO" "Low memory environment detected, using memory-saving options"
    export KCFLAGS="-g0 -Os"  # Optimize for size, omit debug info
else
    export KCFLAGS="-O2"      # Default optimization
fi

if [ "${INTERACTIVE_CONFIG:-false}" = "true" ]; then
    log "INFO" "Using interactive kernel configuration"
    make menuconfig
else
    log "INFO" "Using non-interactive kernel configuration (auto-accepting defaults for new options)"
    make olddefconfig
fi

# Determine verbosity level
if [ "${MAKE_VERBOSE:-0}" = "1" ] || [ "${VERBOSE:-false}" = "true" ]; then
    MAKE_V="V=1"
    log "INFO" "Using verbose build output"
else
    MAKE_V="V=0"
fi

if [ "${USE_CACHE:-false}" = "true" ] && command -v ccache &> /dev/null; then
    log "INFO" "Using compiler cache for faster builds"
    nice -n 19 make $MAKE_V -j$THREADS CC="ccache gcc" HOSTCC="ccache gcc"
else
    nice -n 19 make $MAKE_V -j$THREADS
fi

##########################
# Building kernel modules
##########################

echo "----------------------------------------------------"
log "INFO" "Building kernel modules using $THREADS threads"

if [ "${USE_CACHE:-false}" = "true" ] && command -v ccache &> /dev/null; then
    nice -n 19 make $MAKE_V modules -j$THREADS CC="ccache gcc" HOSTCC="ccache gcc"
else
    nice -n 19 make $MAKE_V modules -j$THREADS
fi

# Copying kernel modules in root filesystem
echo "----------------------------------------------------"
echo -e "Copying kernel modules in root filesystem\n"
nice -19 make -s modules_install

# Building and installing ZFS modules if enabled
if [ "${INCLUDE_ZFS:-true}" = "true" ]; then
    echo "----------------------------------------------------"
    log "INFO" "Building and installing ZFS modules"
    cd ../zfs
    
    # Memory-saving options for ZFS build too
    if [ "$AVAILABLE_MEM_KB" -gt 0 ] && [ "$AVAILABLE_MEM_KB" -lt 8000000 ]; then  # < 8GB
        log "INFO" "Low memory environment detected, using memory-saving options for ZFS build"
        export CFLAGS="-g0 -Os"  # Optimize for size, omit debug info
    else
        export CFLAGS="-O2"      # Default optimization
    fi
    
    # Use ccache for ZFS if enabled
    if [ "${USE_CACHE:-false}" = "true" ] && command -v ccache &> /dev/null; then
        log "INFO" "Using compiler cache for ZFS build"
        export CC="ccache gcc"
        export HOSTCC="ccache gcc"
    fi
    
    # Check for required dependencies
    log "INFO" "Verifying ZFS build dependencies"
    if [ ! -e "../$ROOTFS/usr/include/uuid/uuid.h" ]; then
        log "WARNING" "UUID development headers missing - installing util-linux-dev in chroot"
        chroot "../$ROOTFS" /bin/ash -c "apk add util-linux-dev"
    fi
    
    ./autogen.sh
    ./configure --with-linux=$(pwd)/../$KERNELPATH --with-linux-obj=$(pwd)/../$KERNELPATH --prefix=/fake
    log "INFO" "Building ZFS modules with $THREADS threads"
    nice -n 19 make -s -j$THREADS -C module
    DESTDIR=$(realpath $(pwd)/../$ROOTFS)
    mkdir -p ${DESTDIR}/fake
    make DESTDIR=${DESTDIR} INSTALL_MOD_PATH=${DESTDIR} install
    rm -rf ${DESTDIR}/fake
    echo -e "Uncompressed root filesystem size WITH kernel modules: $(du -sh $DESTDIR | cut -f1)\n"
    cd $(pwd)/../$KERNELPATH
else
    echo "----------------------------------------------------"
    echo "Skipping ZFS module build (disabled in configuration)"
fi


# Creating modules.dep
echo "----------------------------------------------------"
echo -e "Copying modules.dep\n"
nice -19 depmod -b ../$ROOTFS -F System.map $KERNELVERSION

##########################
# Rebuilding kernel
##########################
echo "----------------------------------------------------"
log "INFO" "Rebuilding kernel with all modules using $THREADS threads"

# Apply memory-saving optimizations for final build too
# No need to reconfigure here, as we're just rebuilding with modules
if [ "${USE_CACHE:-false}" = "true" ] && command -v ccache &> /dev/null; then
    nice -n 19 make $MAKE_V -j$THREADS CC="ccache gcc" HOSTCC="ccache gcc"
else
    nice -n 19 make $MAKE_V -j$THREADS
fi


##########################
# Get builded file
##########################

#rm /boot/efi/EFI/OneFileLinux.efi
#cp arch/x86/boot/bzImage /boot/efi/EFI/OneFileLinux.efi
sync

# Copy the kernel image as OneRecovery.efi
cp arch/x86/boot/bzImage ../OneRecovery.efi
sync

# Record the original file size
ORIGINAL_SIZE=$(du -h ../OneRecovery.efi | cut -f1)

# Apply compression if enabled
if [ "${INCLUDE_COMPRESSION:-true}" = "true" ]; then
    log "INFO" "Applying compression to reduce file size"
    
    # Determine which compression tool to use
    COMPRESSION_TOOL="${COMPRESSION_TOOL:-upx}"
    log "INFO" "Selected compression tool: $COMPRESSION_TOOL"
    
    # Create a backup of the original file
    cp ../OneRecovery.efi ../OneRecovery.efi.original
    
    case "$COMPRESSION_TOOL" in
        "upx")
            if command -v upx &> /dev/null; then
                # Apply UPX compression
                log "INFO" "Compressing with UPX (faster decompression, good size reduction)..."
                if upx --best --lzma ../OneRecovery.efi; then
                    COMPRESSED_SIZE=$(du -h ../OneRecovery.efi | cut -f1)
                    log "SUCCESS" "UPX compression successful"
                    log "INFO" "Original size: $ORIGINAL_SIZE, Compressed size: $COMPRESSED_SIZE"
                else
                    log "WARNING" "UPX compression failed, restoring original file"
                    mv ../OneRecovery.efi.original ../OneRecovery.efi
                fi
            else
                log "ERROR" "UPX not found. Please install UPX: apt-get install upx-ucl"
                log "INFO" "Restoring original uncompressed file"
                mv ../OneRecovery.efi.original ../OneRecovery.efi
            fi
            ;;
            
        "xz")
            if command -v xz &> /dev/null; then
                # Apply XZ compression
                log "INFO" "Compressing with XZ (higher compression ratio, slower decompression)..."
                # Note: XZ compression would require a decompression stub in a real implementation
                # This is a simplified version for demonstration
                if xz -z -9 -e -f --keep ../OneRecovery.efi; then
                    # In a real implementation, we would need to prepend a decompression stub
                    # For now, we'll just rename the file
                    mv ../OneRecovery.efi.xz ../OneRecovery.efi.compressed
                    COMPRESSED_SIZE=$(du -h ../OneRecovery.efi.compressed | cut -f1)
                    log "WARNING" "XZ compression completed but requires a custom decompression stub"
                    log "INFO" "Original size: $ORIGINAL_SIZE, Compressed size: $COMPRESSED_SIZE"
                    log "INFO" "Using original uncompressed file for compatibility"
                    mv ../OneRecovery.efi.original ../OneRecovery.efi
                else
                    log "WARNING" "XZ compression failed, restoring original file"
                    mv ../OneRecovery.efi.original ../OneRecovery.efi
                fi
            else
                log "ERROR" "XZ not found. Please install XZ: apt-get install xz-utils"
                log "INFO" "Restoring original uncompressed file"
                mv ../OneRecovery.efi.original ../OneRecovery.efi
            fi
            ;;
            
        "zstd")
            if command -v zstd &> /dev/null; then
                # Apply ZSTD compression
                log "INFO" "Compressing with ZSTD (balanced compression ratio and speed)..."
                # Note: ZSTD compression would require a decompression stub in a real implementation
                # This is a simplified version for demonstration
                if zstd -19 -f ../OneRecovery.efi -o ../OneRecovery.efi.zst; then
                    # In a real implementation, we would need to prepend a decompression stub
                    # For now, we'll just rename the file
                    mv ../OneRecovery.efi.zst ../OneRecovery.efi.compressed
                    COMPRESSED_SIZE=$(du -h ../OneRecovery.efi.compressed | cut -f1)
                    log "WARNING" "ZSTD compression completed but requires a custom decompression stub"
                    log "INFO" "Original size: $ORIGINAL_SIZE, Compressed size: $COMPRESSED_SIZE"
                    log "INFO" "Using original uncompressed file for compatibility"
                    mv ../OneRecovery.efi.original ../OneRecovery.efi
                else
                    log "WARNING" "ZSTD compression failed, restoring original file"
                    mv ../OneRecovery.efi.original ../OneRecovery.efi
                fi
            else
                log "ERROR" "ZSTD not found. Please install ZSTD: apt-get install zstd"
                log "INFO" "Restoring original uncompressed file"
                mv ../OneRecovery.efi.original ../OneRecovery.efi
            fi
            ;;
            
        *)
            log "ERROR" "Unknown compression tool: $COMPRESSION_TOOL"
            log "INFO" "Restoring original uncompressed file"
            mv ../OneRecovery.efi.original ../OneRecovery.efi
            ;;
    esac
    
    # Clean up backup if it exists
    rm -f ../OneRecovery.efi.original
else
    log "INFO" "Compression disabled by configuration"
fi

echo "----------------------------------------------------"
log "SUCCESS" "Build completed successfully: $(pwd)/../OneRecovery.efi"

# Wait for filesystem sync to complete
sleep 2
FINAL_SIZE=$(du -sh $(pwd)/../OneRecovery.efi | cut -f1)
log "INFO" "Final file size: $FINAL_SIZE"

# Clean up swap file if we created one
if [ "${USE_SWAP:-false}" = "true" ] && [ -f "/tmp/onerecovery_swap" ]; then
    log "INFO" "Removing temporary swap file"
    sudo swapoff "/tmp/onerecovery_swap" 2>/dev/null || true
    sudo rm -f "/tmp/onerecovery_swap"
    log "SUCCESS" "Swap file removed"
fi

# Print summary of build configuration
echo "----------------------------------------------------"
log "INFO" "Build Summary:"
if [ "${INCLUDE_MINIMAL_KERNEL:-false}" = "true" ]; then
    log "INFO" "- Kernel: Minimal (optimized for size)"
else
    log "INFO" "- Kernel: Standard"
fi

if [ "${INCLUDE_COMPRESSION:-true}" = "true" ]; then
    log "INFO" "- Compression: Enabled (using ${COMPRESSION_TOOL:-upx})"
else
    log "INFO" "- Compression: Disabled"
fi

log "INFO" "- ZFS Support: $([ "${INCLUDE_ZFS:-true}" = "true" ] && echo "Included" || echo "Excluded")"
log "INFO" "- File Size: $FINAL_SIZE"
