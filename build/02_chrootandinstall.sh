#!/bin/bash
#
# Configure Alpine Linux chroot and install packages
#

# Define script name for error handling
SCRIPT_NAME=$(basename "$0")

# Source common error handling
source ./error_handling.sh

# Initialize error handling
init_error_handling

# Check if we should resume from a checkpoint
check_resume_point "$1"

# Configure DNS for the chroot environment
log "INFO" "Setting up DNS for chroot environment"
cat > alpine-minirootfs/etc/resolv.conf << EOF
nameserver 1.1.1.1
nameserver 8.8.4.4
EOF

# Create installation script
log "INFO" "Creating installation script"
# Determine which packages to install based on module configuration
PACKAGES="openrc nano mc bash parted dropbear dropbear-ssh efibootmgr \
    e2fsprogs e2fsprogs-extra dosfstools \
    dmraid fuse gawk grep sed util-linux wget"

# Add ZFS support if enabled
if [ "${INCLUDE_ZFS:-true}" = "true" ]; then
    PACKAGES="$PACKAGES zfs"
    log "INFO" "Including ZFS support"
fi

# Add BTRFS support if enabled
if [ "${INCLUDE_BTRFS:-false}" = "true" ]; then
    PACKAGES="$PACKAGES btrfs-progs"
    log "INFO" "Including Btrfs support"
fi

# Add recovery tools if enabled
if [ "${INCLUDE_RECOVERY_TOOLS:-true}" = "true" ]; then
    PACKAGES="$PACKAGES testdisk ddrescue rsync unzip tar"
    log "INFO" "Including recovery tools"
fi

# Add network tools if enabled
if [ "${INCLUDE_NETWORK_TOOLS:-true}" = "true" ]; then
    # Note: We use dropbear-ssh instead of openssh-client to avoid conflicts
    PACKAGES="$PACKAGES curl rsync iperf3 tcpdump"
    log "INFO" "Including network tools"
fi

# Add crypto support if enabled
if [ "${INCLUDE_CRYPTO:-true}" = "true" ]; then
    PACKAGES="$PACKAGES cryptsetup lvm2 mdadm"
    log "INFO" "Including encryption support"
fi

# Add TUI dependencies if enabled
if [ "${INCLUDE_TUI:-true}" = "true" ]; then
    PACKAGES="$PACKAGES ncurses-terminfo-base less"
    log "INFO" "Including TUI dependencies"
fi

cat > alpine-minirootfs/mk.sh << EOF
#!/bin/ash
set -e

echo "[INFO] Setting hostname"
echo onerecovery > /etc/hostname && hostname -F /etc/hostname
echo 127.0.1.1 onerecovery onerecovery >> /etc/hosts

echo "[INFO] Updating package lists"
apk update

echo "[INFO] Upgrading installed packages"
apk upgrade

echo "[INFO] Installing required packages"
apk add $PACKAGES

echo "[INFO] Cleaning package cache"
rm /var/cache/apk/*

echo "[INFO] Installation completed successfully"
exit 0
EOF

# Make installation script executable
chmod +x alpine-minirootfs/mk.sh
log "INFO" "Installation script created and made executable"

# Execute chroot
log "INFO" "Entering chroot environment to install packages"
chroot alpine-minirootfs /bin/ash /mk.sh
log "SUCCESS" "Chroot installation completed successfully"

# Clean up installation script
rm alpine-minirootfs/mk.sh
log "INFO" "Removed installation script"

# Print final status
print_script_end