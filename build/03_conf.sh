#!/bin/bash
#
# Configure Alpine Linux system services and settings
#

# Define script name for error handling
SCRIPT_NAME=$(basename "$0")

# Source common error handling
source ./error_handling.sh

# Initialize error handling
init_error_handling

# Check if we should resume from a checkpoint
check_resume_point "$1"

# Configure system services for sysinit runlevel
log "INFO" "Setting up system services in sysinit runlevel"
mkdir -p ./alpine-minirootfs/etc/runlevels/sysinit
ln -fs /etc/init.d/mdev ./alpine-minirootfs/etc/runlevels/sysinit/mdev
ln -fs /etc/init.d/devfs ./alpine-minirootfs/etc/runlevels/sysinit/devfs
ln -fs /etc/init.d/dmesg ./alpine-minirootfs/etc/runlevels/sysinit/dmesg
ln -fs /etc/init.d/syslog ./alpine-minirootfs/etc/runlevels/sysinit/syslog
ln -fs /etc/init.d/hwdrivers ./alpine-minirootfs/etc/runlevels/sysinit/hwdrivers
ln -fs /etc/init.d/networking ./alpine-minirootfs/etc/runlevels/sysinit/networking
log "SUCCESS" "System services configured"

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
