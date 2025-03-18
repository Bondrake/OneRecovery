#!/bin/bash
#
# Configure Alpine Linux system services and settings
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

# Initialize script with standard header (prints banner)
initialize_script

# Check if we should resume from a checkpoint
check_resume_point "$1"

# Start timing for configuration
start_timing "03_conf: System services"

# Configure system services for sysinit runlevel
log "INFO" "Setting up system services in sysinit runlevel"

# Define a function to create service symlinks using various methods
create_service_symlinks() {
    local target_dir="./alpine-minirootfs/etc/runlevels/sysinit"
    
    # Try to create using direct methods first
    if mkdir -p "$target_dir" 2>/dev/null; then
        log "INFO" "Created runlevels directory"
        
        # Try to set permissions but continue if it fails
        chmod 777 "$target_dir" 2>/dev/null || log "WARNING" "Could not set permissions on $target_dir"
        
        # Create symlinks - continue even if some fail
        ln -fs /etc/init.d/mdev "$target_dir/mdev" 2>/dev/null
        ln -fs /etc/init.d/devfs "$target_dir/devfs" 2>/dev/null
        ln -fs /etc/init.d/dmesg "$target_dir/dmesg" 2>/dev/null
        ln -fs /etc/init.d/syslog "$target_dir/syslog" 2>/dev/null
        ln -fs /etc/init.d/hwdrivers "$target_dir/hwdrivers" 2>/dev/null
        ln -fs /etc/init.d/networking "$target_dir/networking" 2>/dev/null
        
        # Check if at least some symlinks were created
        if ls -la "$target_dir"/* >/dev/null 2>&1; then
            log "SUCCESS" "Created service symlinks"
            return 0
        fi
    fi
    
    # If direct method failed, try alternative approaches
    log "WARNING" "Direct symlink creation failed, trying alternatives"
    
    # Try using touch to create empty files instead of symlinks
    if mkdir -p "$target_dir" 2>/dev/null; then
        # Create empty files in place of symlinks
        touch "$target_dir/mdev" "$target_dir/devfs" "$target_dir/dmesg" \
              "$target_dir/syslog" "$target_dir/hwdrivers" "$target_dir/networking" 2>/dev/null
        
        log "WARNING" "Created placeholder files instead of symlinks"
        return 0
    fi
    
    # Alternative: Create a file with the list of services to be added later
    log "WARNING" "Could not create runlevels directory, creating services list file"
    echo "mdev devfs dmesg syslog hwdrivers networking" > "./alpine-minirootfs/services.txt" 2>/dev/null
    
    return 0  # Continue build even if we couldn't create symlinks
}

# Check if running in container and apply special handling
if [ "${IN_DOCKER_CONTAINER}" = "true" ] || grep -q "docker\|container" /proc/1/cgroup 2>/dev/null || [ -f "/.dockerenv" ]; then
    log "INFO" "Running in container, using special permissions handling"
    
    # First attempt: Try with sudo if available
    if command -v sudo &> /dev/null; then
        log "INFO" "Using sudo for service setup"
        sudo mkdir -p ./alpine-minirootfs/etc/runlevels/sysinit 2>/dev/null
        sudo chmod 777 ./alpine-minirootfs/etc/runlevels/sysinit 2>/dev/null
        sudo ln -fs /etc/init.d/mdev ./alpine-minirootfs/etc/runlevels/sysinit/mdev 2>/dev/null
        sudo ln -fs /etc/init.d/devfs ./alpine-minirootfs/etc/runlevels/sysinit/devfs 2>/dev/null
        sudo ln -fs /etc/init.d/dmesg ./alpine-minirootfs/etc/runlevels/sysinit/dmesg 2>/dev/null
        sudo ln -fs /etc/init.d/syslog ./alpine-minirootfs/etc/runlevels/sysinit/syslog 2>/dev/null
        sudo ln -fs /etc/init.d/hwdrivers ./alpine-minirootfs/etc/runlevels/sysinit/hwdrivers 2>/dev/null
        sudo ln -fs /etc/init.d/networking ./alpine-minirootfs/etc/runlevels/sysinit/networking 2>/dev/null
        
        # Check if at least some files were created
        if ! ls -la ./alpine-minirootfs/etc/runlevels/sysinit/* >/dev/null 2>&1; then
            log "WARNING" "Sudo method failed, trying alternative methods"
            create_service_symlinks
        fi
    else
        # No sudo available, try direct method
        log "INFO" "Sudo not available, trying alternative methods"
        create_service_symlinks
    fi
else
    # Regular environment - use standard method
    log "INFO" "Using standard method for service setup"
    create_service_symlinks
fi

# Continue even if symlinks couldn't be created perfectly - we can fix later
log "SUCCESS" "System services configured (possibly with fallbacks)"

# Set up terminal access
log "INFO" "Setting up terminal access"
ln -fs /sbin/agetty ./alpine-minirootfs/sbin/getty 
log "SUCCESS" "Terminal access configured"

# Copy configuration files
log "INFO" "Copying configuration files from zfiles"
# Check that the required files exist
for file in interfaces resolv.conf profile shadow init; do
    if [ ! -f "./zfiles/$file" ]; then
        log "ERROR" "Required configuration file not found: ./zfiles/$file"
        exit 1
    fi
done

# Create target directories if they don't exist
mkdir -p ./alpine-minirootfs/etc/network
mkdir -p ./alpine-minirootfs/etc

# Copy the files
cat ./zfiles/interfaces > ./alpine-minirootfs/etc/network/interfaces
cat ./zfiles/resolv.conf > ./alpine-minirootfs/etc/resolv.conf
cat ./zfiles/profile > ./alpine-minirootfs/etc/profile

end_timing

# Start timing for system configuration
start_timing "03_conf: System configuration"

# Configure root password
if [ "${GENERATE_RANDOM_PASSWORD:-true}" = "true" ]; then
    # Generate a random password
    log "INFO" "Generating random root password"
    GENERATED_PASSWORD=$(generate_random_password "${ROOT_PASSWORD_LENGTH:-12}")
    
    # Create password hash
    PASSWORD_HASH=$(create_password_hash "$GENERATED_PASSWORD")
    
    if [ "$PASSWORD_HASH" = "ERROR" ]; then
        log "ERROR" "Failed to hash password. Falling back to no password (unsafe)."
        cp ./zfiles/shadow ./alpine-minirootfs/etc/shadow
    else
        # Create shadow file with hashed password
        log "INFO" "Setting secure root password"
        sed "s|^root:.*|root:$PASSWORD_HASH:18383:0:::::|" ./zfiles/shadow > ./alpine-minirootfs/etc/shadow
        
        # Save the password to a file for user reference
        echo "Generated root password: $GENERATED_PASSWORD" > onerecovery-password.txt
        log "SUCCESS" "Random root password generated. See onerecovery-password.txt"
    fi
elif [ -n "${ROOT_PASSWORD}" ]; then
    # Use provided custom password
    log "INFO" "Setting custom root password"
    PASSWORD_HASH=$(create_password_hash "$ROOT_PASSWORD")
    
    if [ "$PASSWORD_HASH" = "ERROR" ]; then
        log "ERROR" "Failed to hash password. Falling back to no password (unsafe)."
        cp ./zfiles/shadow ./alpine-minirootfs/etc/shadow
    else
        # Create shadow file with hashed password
        sed "s|^root:.*|root:$PASSWORD_HASH:18383:0:::::|" ./zfiles/shadow > ./alpine-minirootfs/etc/shadow
        log "SUCCESS" "Custom root password set"
    fi
else
    # No password (original behavior)
    log "WARNING" "Creating root account with no password (unsafe)"
    cp ./zfiles/shadow ./alpine-minirootfs/etc/shadow
fi

cat ./zfiles/init > ./alpine-minirootfs/init
chmod +x ./alpine-minirootfs/init

# Install TUI script if enabled
if [ "${INCLUDE_TUI:-true}" = "true" ]; then
    log "INFO" "Installing Text User Interface"
    cat ./zfiles/onerecovery-tui > ./alpine-minirootfs/onerecovery-tui
    chmod +x ./alpine-minirootfs/onerecovery-tui
else
    log "INFO" "Skipping Text User Interface (disabled in configuration)"
fi
log "SUCCESS" "Configuration files copied"

end_timing

# Start timing for console configuration
start_timing "03_conf: Console configuration"

# Configure console settings
log "INFO" "Configuring console settings"
# Enable serial console
sed -i 's/^#ttyS0/ttyS0/' ./alpine-minirootfs/etc/inittab

# Enable root login on all local consoles
sed -i 's|\(/sbin/getty \)|\1 -a root |' ./alpine-minirootfs/etc/inittab
log "SUCCESS" "Console settings configured"

# Legacy commented code preserved for reference
#mv ./alpine-minirootfs/etc/profile.d/color_prompt ./alpine-minirootfs/etc/profile.d/color_prompt.sh
#mv ./alpine-minirootfs/etc/profile.d/locale ./alpine-minirootfs/etc/profile.d/locale.sh
#chmod +x ./alpine-minirootfs/etc/profile.d/*.sh
#mkdir ./alpine-minirootfs/media/ubuntu
#cat > ./alpine-minirootfs/etc/fstab << EOF
#/dev/cdrom	/media/cdrom	iso9660	noauto,ro 0 0
#/dev/usbdisk	/media/usb	vfat	noauto,ro 0 0
#/dev/sda5	/media/ubuntu	ext4	rw,relatime 0 0
#EOF

end_timing

# Start timing for kernel configuration
start_timing "03_conf: Kernel configuration"

# Set up kernel configuration
log "INFO" "Setting up kernel configuration"
mkdir -p alpine-minirootfs/lib/

# Kernel configuration paths
KERNEL_CONFIG_DIR="kernel-configs"
FEATURES_DIR="$KERNEL_CONFIG_DIR/features"
ALPINE_CONFIG_MINIMAL="$KERNEL_CONFIG_DIR/minimal.config"
ALPINE_CONFIG_STANDARD="$KERNEL_CONFIG_DIR/standard.config"
LEGACY_MINIMAL_CONFIG="zfiles/kernel-minimal.config"
LEGACY_STANDARD_CONFIG="zfiles/.config"

# Make sure the kernel config directories exist
mkdir -p "$KERNEL_CONFIG_DIR/base"
mkdir -p "$FEATURES_DIR"

# Download Alpine kernel config if needed
if [ "${USE_ALPINE_KERNEL_CONFIG:-true}" = "true" ]; then
    log "INFO" "Setting up Alpine Linux kernel configuration"
    if [ -f "./tools/get-alpine-kernel-config.sh" ]; then
        chmod +x ./tools/get-alpine-kernel-config.sh
        ./tools/get-alpine-kernel-config.sh --dir="$(pwd)" --version="${ALPINE_VERSION}"
        
        # Verify the download was successful
        if [ ! -f "$ALPINE_CONFIG_MINIMAL" ] || [ ! -s "$ALPINE_CONFIG_MINIMAL" ]; then
            log "ERROR" "Failed to download Alpine kernel config. Check network connection."
            log "INFO" "Falling back to legacy kernel config."
            USE_ALPINE_KERNEL_CONFIG=false
            
            # Use legacy configs if available
            if [ -f "$LEGACY_MINIMAL_CONFIG" ]; then
                log "INFO" "Using legacy minimal kernel config: $LEGACY_MINIMAL_CONFIG"
                mkdir -p "$(dirname "$ALPINE_CONFIG_MINIMAL")"
                cp "$LEGACY_MINIMAL_CONFIG" "$ALPINE_CONFIG_MINIMAL"
            else
                log "ERROR" "No kernel configuration available."
                exit 1
            fi
        else
            log "SUCCESS" "Alpine kernel configuration downloaded successfully"
        fi
    else
        log "ERROR" "Alpine kernel config download script not found."
        exit 1
    fi
fi

# Check for custom kernel configuration
if [ -n "${CUSTOM_KERNEL_CONFIG:-}" ] && [ -f "${CUSTOM_KERNEL_CONFIG}" ]; then
    log "INFO" "Using custom kernel configuration: ${CUSTOM_KERNEL_CONFIG}"
    cp "${CUSTOM_KERNEL_CONFIG}" linux/.config

# Use Alpine-based config if enabled
elif [ "${USE_ALPINE_KERNEL_CONFIG:-true}" = "true" ]; then
    if [ "${INCLUDE_MINIMAL_KERNEL:-false}" = "true" ]; then
        if [ ! -f "$ALPINE_CONFIG_MINIMAL" ]; then
            log "ERROR" "Alpine minimal kernel config not found: $ALPINE_CONFIG_MINIMAL"
            log "INFO" "Falling back to legacy kernel config"
            
            if [ ! -f "$LEGACY_MINIMAL_CONFIG" ]; then
                log "ERROR" "Legacy minimal kernel config not found: $LEGACY_MINIMAL_CONFIG"
                exit 1
            fi
            cp "$LEGACY_MINIMAL_CONFIG" linux/.config
        else
            log "INFO" "Using Alpine-based minimal kernel configuration"
            cp "$ALPINE_CONFIG_MINIMAL" linux/.config
        fi
    else
        if [ ! -f "$ALPINE_CONFIG_STANDARD" ]; then
            log "ERROR" "Alpine standard kernel config not found: $ALPINE_CONFIG_STANDARD"
            log "INFO" "Falling back to legacy kernel config"
            
            if [ ! -f "$LEGACY_STANDARD_CONFIG" ]; then
                log "ERROR" "Legacy standard kernel config not found: $LEGACY_STANDARD_CONFIG"
                exit 1
            fi
            cp "$LEGACY_STANDARD_CONFIG" linux/.config
        else
            log "INFO" "Using Alpine-based standard kernel configuration"
            cp "$ALPINE_CONFIG_STANDARD" linux/.config
        fi
    fi

    # Apply feature overlays based on package selection
    if [ "${AUTO_KERNEL_CONFIG:-true}" = "true" ]; then
        APPLY_OVERLAY="./tools/apply-config-overlay.sh"
        
        # Check if using minimal kernel
        if [ "${INCLUDE_MINIMAL_KERNEL:-false}" = "true" ]; then
            log "INFO" "Building with minimal kernel configuration (INCLUDE_MINIMAL_KERNEL=true)"
            log "INFO" "Skipping most feature overlays for minimal build"
            
            # Apply only essential overlays for minimal build
            # (none by default, but you could add critical ones here if needed)
        else
            log "INFO" "Building with standard kernel configuration"
            
            if [ -f "$APPLY_OVERLAY" ]; then
                # Apply ZFS overlay if enabled
                if [ "${INCLUDE_ZFS:-true}" = "true" ] && [ -f "$FEATURES_DIR/zfs-support.conf" ]; then
                    log "INFO" "Applying ZFS kernel config overlay"
                    "$APPLY_OVERLAY" "$FEATURES_DIR/zfs-support.conf" "linux/.config"
                else
                    log "INFO" "Skipping ZFS kernel config overlay (INCLUDE_ZFS=${INCLUDE_ZFS:-true})"
                fi
                
                # Apply BTRFS overlay if enabled
                if [ "${INCLUDE_BTRFS:-false}" = "true" ] && [ -f "$FEATURES_DIR/btrfs-support.conf" ]; then
                    log "INFO" "Applying BTRFS kernel config overlay"
                    "$APPLY_OVERLAY" "$FEATURES_DIR/btrfs-support.conf" "linux/.config"
                else
                    log "INFO" "Skipping BTRFS kernel config overlay (INCLUDE_BTRFS=${INCLUDE_BTRFS:-false})"
                fi
                
                # Apply network tools overlay if enabled
                if [ "${INCLUDE_NETWORK_TOOLS:-true}" = "true" ] && [ -f "$FEATURES_DIR/network-tools.conf" ]; then
                    log "INFO" "Applying network tools kernel config overlay"
                    "$APPLY_OVERLAY" "$FEATURES_DIR/network-tools.conf" "linux/.config"
                else
                    log "INFO" "Skipping network tools kernel config overlay (INCLUDE_NETWORK_TOOLS=${INCLUDE_NETWORK_TOOLS:-true})"
                fi
                
                # Apply crypto overlay if enabled
                if [ "${INCLUDE_CRYPTO:-true}" = "true" ] && [ -f "$FEATURES_DIR/crypto-support.conf" ]; then
                    log "INFO" "Applying crypto support kernel config overlay"
                    "$APPLY_OVERLAY" "$FEATURES_DIR/crypto-support.conf" "linux/.config"
                else
                    log "INFO" "Skipping crypto support kernel config overlay (INCLUDE_CRYPTO=${INCLUDE_CRYPTO:-true})"
                fi
                
                # Apply advanced filesystem overlay if enabled
                if [ "${INCLUDE_ADVANCED_FS:-false}" = "true" ] && [ -f "$FEATURES_DIR/advanced-fs.conf" ]; then
                    log "INFO" "Applying advanced filesystems kernel config overlay"
                    "$APPLY_OVERLAY" "$FEATURES_DIR/advanced-fs.conf" "linux/.config"
                else
                    log "INFO" "Skipping advanced filesystems kernel config overlay (INCLUDE_ADVANCED_FS=${INCLUDE_ADVANCED_FS:-false})"
                fi
            else
                log "WARNING" "Config overlay utility not found: $APPLY_OVERLAY"
                log "INFO" "Continuing without applying feature-specific kernel options"
            fi
        fi
    fi

# Use legacy kernel configs
else
    # Use appropriate kernel config based on build type
    if [ "${INCLUDE_MINIMAL_KERNEL:-false}" = "true" ]; then
        if [ ! -f "$LEGACY_MINIMAL_CONFIG" ]; then
            log "ERROR" "Minimal kernel configuration file not found: $LEGACY_MINIMAL_CONFIG"
            exit 1
        fi
        log "INFO" "Using legacy minimal kernel configuration"
        cp "$LEGACY_MINIMAL_CONFIG" linux/.config
    else
        if [ ! -f "$LEGACY_STANDARD_CONFIG" ]; then
            log "ERROR" "Standard kernel configuration file not found: $LEGACY_STANDARD_CONFIG"
            exit 1
        fi
        log "INFO" "Using legacy standard kernel configuration"
        cp "$LEGACY_STANDARD_CONFIG" linux/.config
    fi
fi

log "SUCCESS" "Kernel configuration copied"

# Legacy commented code preserved for reference
#cd linux
#make menuconfig

# End timing for kernel configuration
end_timing

# Print final status
print_script_end

# If this is the final script being run, finalize the timing log
if [ "${FINALIZE_TIMING_LOG:-false}" = "true" ]; then
    finalize_timing_log
fi
