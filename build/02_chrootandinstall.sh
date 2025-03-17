#!/bin/bash
#
# Configure Alpine Linux chroot and install packages
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
    # Add ZFS and required dependencies
    PACKAGES="$PACKAGES zfs util-linux-dev"
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

# Add advanced filesystem tools if enabled
if [ "${INCLUDE_ADVANCED_FS:-false}" = "true" ]; then
    ADVANCED_FS_PACKAGES="ntfs-3g xfsprogs gdisk exfatprogs f2fs-tools"
    PACKAGES="$PACKAGES $ADVANCED_FS_PACKAGES"
    log "INFO" "Including advanced filesystem tools: $ADVANCED_FS_PACKAGES"
fi

# Add disk and hardware diagnostics if enabled
if [ "${INCLUDE_DISK_DIAG:-false}" = "true" ]; then
    DISK_DIAG_PACKAGES="smartmontools hdparm nvme-cli dmidecode lshw"
    PACKAGES="$PACKAGES $DISK_DIAG_PACKAGES"
    log "INFO" "Including disk and hardware diagnostics: $DISK_DIAG_PACKAGES"
fi

# Add network diagnostics if enabled
if [ "${INCLUDE_NETWORK_DIAG:-false}" = "true" ]; then
    NETWORK_DIAG_PACKAGES="ethtool nmap wireguard-tools openvpn"
    PACKAGES="$PACKAGES $NETWORK_DIAG_PACKAGES"
    log "INFO" "Including network diagnostics and VPN tools: $NETWORK_DIAG_PACKAGES"
fi

# Add system tools if enabled
if [ "${INCLUDE_SYSTEM_TOOLS:-false}" = "true" ]; then
    SYSTEM_TOOLS_PACKAGES="htop strace pciutils usbutils"
    PACKAGES="$PACKAGES $SYSTEM_TOOLS_PACKAGES"
    log "INFO" "Including advanced system tools: $SYSTEM_TOOLS_PACKAGES"
fi

# Add data recovery tools if enabled (photorec is part of testdisk)
if [ "${INCLUDE_DATA_RECOVERY:-false}" = "true" ]; then
    DATA_RECOVERY_PACKAGES="testdisk"
    PACKAGES="$PACKAGES $DATA_RECOVERY_PACKAGES"
    log "INFO" "Including advanced data recovery tools: $DATA_RECOVERY_PACKAGES"
fi

# Add boot repair tools if enabled
if [ "${INCLUDE_BOOT_REPAIR:-false}" = "true" ]; then
    BOOT_REPAIR_PACKAGES="grub"
    PACKAGES="$PACKAGES $BOOT_REPAIR_PACKAGES"
    log "INFO" "Including boot repair tools: $BOOT_REPAIR_PACKAGES"
fi

# Add advanced editors if enabled
if [ "${INCLUDE_EDITORS:-false}" = "true" ]; then
    EDITORS_PACKAGES="vim tmux jq"
    PACKAGES="$PACKAGES $EDITORS_PACKAGES"
    log "INFO" "Including advanced text editors: $EDITORS_PACKAGES"
fi

# Add security tools if enabled
if [ "${INCLUDE_SECURITY:-false}" = "true" ]; then
    SECURITY_PACKAGES="openssl"
    PACKAGES="$PACKAGES $SECURITY_PACKAGES"
    log "INFO" "Including security tools: $SECURITY_PACKAGES"
fi

# Add extra packages if specified
if [ -n "${EXTRA_PACKAGES:-}" ]; then
    # Convert comma-separated list to space-separated list
    EXTRA_PACKAGES_LIST=$(echo "$EXTRA_PACKAGES" | tr ',' ' ')
    PACKAGES="$PACKAGES $EXTRA_PACKAGES_LIST"
    log "INFO" "Including extra packages: $EXTRA_PACKAGES_LIST"
fi

cat > alpine-minirootfs/mk.sh << EOF
#!/bin/ash
set -e

echo "[INFO] Setting hostname"
echo onerecovery > /etc/hostname && hostname -F /etc/hostname
echo 127.0.1.1 onerecovery onerecovery >> /etc/hosts

echo "[INFO] Updating package lists"
apk update

# Enable community repository for dev packages
echo "http://dl-cdn.alpinelinux.org/alpine/v3.21/community" >> /etc/apk/repositories
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