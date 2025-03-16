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
cat ./zfiles/shadow > ./alpine-minirootfs/etc/shadow
cat ./zfiles/init > ./alpine-minirootfs/init
chmod +x ./alpine-minirootfs/init
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
if [ ! -f "zfiles/.config" ]; then
    log "ERROR" "Kernel configuration file not found: zfiles/.config"
    exit 1
fi
cp zfiles/.config linux/
log "SUCCESS" "Kernel configuration copied"

# Legacy commented code preserved for reference
#cd linux
#make menuconfig

# Print final status
print_script_end
