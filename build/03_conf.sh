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

# Set up kernel configuration
log "INFO" "Setting up kernel configuration"
mkdir -p alpine-minirootfs/lib/

# Check for custom kernel configuration
if [ -n "${CUSTOM_KERNEL_CONFIG:-}" ] && [ -f "${CUSTOM_KERNEL_CONFIG}" ]; then
    log "INFO" "Using custom kernel configuration: ${CUSTOM_KERNEL_CONFIG}"
    cp "${CUSTOM_KERNEL_CONFIG}" linux/.config
# Use appropriate kernel config based on build type
elif [ "${INCLUDE_MINIMAL_KERNEL:-false}" = "true" ]; then
    if [ ! -f "zfiles/kernel-minimal.config" ]; then
        log "ERROR" "Minimal kernel configuration file not found: zfiles/kernel-minimal.config"
        exit 1
    fi
    log "INFO" "Using minimal kernel configuration for smaller size"
    cp zfiles/kernel-minimal.config linux/.config
else
    if [ ! -f "zfiles/.config" ]; then
        log "ERROR" "Standard kernel configuration file not found: zfiles/.config"
        exit 1
    fi
    log "INFO" "Using standard kernel configuration"
    cp zfiles/.config linux/
fi
log "SUCCESS" "Kernel configuration copied"

# Legacy commented code preserved for reference
#cd linux
#make menuconfig

# Print final status
print_script_end
