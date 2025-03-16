#!/bin/bash

# Define script name for error handling
SCRIPT_NAME=$(basename "$0")

# Source common error handling if available
if [ -f "./error_handling.sh" ]; then
    source ./error_handling.sh
else
    # Minimal error handling if the file is not available
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
    
    log() {
        local level=$1
        local message=$2
        case "$level" in
            "INFO") echo -e "${BLUE}[INFO]${NC} $message" ;;
            "WARNING") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
            "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
            "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
            *) echo -e "$message" ;;
        esac
    }
    
    trap 'echo -e "${RED}[ERROR]${NC} An error occurred at line $LINENO. Command: $BASH_COMMAND"; exit 1' ERR
    set -e
fi

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

# Build threads equal to CPU cores
THREADS=$(getconf _NPROCESSORS_ONLN)

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
# Bulding kernel
##########################
echo "----------------------------------------------------"
echo -e "Building kernel with initrams using $THREADS threads...\n"
nice -19 make -s -j$THREADS

##########################
# Bulding kernel modules
##########################

#echo "----------------------------------------------------"
echo -e "Building kernel mobules using $THREADS threads...\n"
nice -19 make -s modules -j$THREADS

# Copying kernel modules in root filesystem
echo "----------------------------------------------------"
echo -e "Copying kernel modules in root filesystem\n"
nice -19 make -s modules_install

# Building and installing ZFS modules if enabled
if [ "${INCLUDE_ZFS:-true}" = "true" ]; then
    echo "----------------------------------------------------"
    echo "Building and installing ZFS modules"
    cd ../zfs
    ./autogen.sh
    ./configure --with-linux=$(pwd)/../$KERNELPATH --with-linux-obj=$(pwd)/../$KERNELPATH --prefix=/fake
    nice -19 make -s -j$THREADS -C module
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
# Bulding kernel
##########################
echo "----------------------------------------------------"
echo -e "Building kernel with initrams using $THREADS threads...\n"
nice -19 make -s -j$THREADS


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
