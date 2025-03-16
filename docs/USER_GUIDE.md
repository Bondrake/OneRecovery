# OneRecovery User Guide

This comprehensive guide explains how to build, install, and use OneRecovery for system recovery operations.

## Table of Contents

1. [Overview](#overview)
2. [Building OneRecovery](#building-onerecovery)
   - [Using Docker](#using-docker-recommended)
   - [Building Natively](#building-natively)
   - [Build Options](#build-options)
3. [Installation](#installation)
   - [macOS Installation](#macos-installation)
   - [PC/Windows Installation](#pcwindows-installation)
   - [USB Flash Drive Installation](#usb-flash-drive-installation)
4. [Using OneRecovery](#using-onerecovery)
   - [Text User Interface](#text-user-interface)
   - [Common Recovery Operations](#common-recovery-operations)
   - [Working with Filesystems](#working-with-filesystems)
   - [Network Connectivity](#network-connectivity)
5. [Troubleshooting](#troubleshooting)
   - [Boot Issues](#boot-issues)
   - [Hardware Compatibility](#hardware-compatibility)
   - [Common Errors](#common-errors)
6. [Advanced Usage](#advanced-usage)
   - [Custom Configurations](#custom-configurations)
   - [Recovery Scenarios](#recovery-scenarios)
   - [Performance Considerations](#performance-considerations)

## Overview

OneRecovery is a lightweight Linux distribution contained in a single EFI executable file that runs on any UEFI computer (PC or Mac) without installation. It provides a comprehensive set of tools for system recovery, data rescue, and hardware diagnostics.

### Key Features

- **Single EFI File**: Boots directly from UEFI without additional bootloaders
- **Advanced Filesystems**: Support for ZFS, Btrfs, ext4, XFS, and more
- **Hardware Diagnostics**: Tools for hardware testing and analysis
- **Network Support**: Ethernet, WiFi, and remote recovery capabilities
- **Data Recovery**: Specialized tools for rescuing data from failed systems
- **Boot Repair**: Tools to fix common boot problems across operating systems
- **Text UI**: Full-featured text-based user interface for easy navigation
- **Size Optimized**: Minimal builds under 50MB, full builds under 150MB

### Project History

OneRecovery is a fork of the original OneFileLinux project, which hasn't been maintained for over 5 years. This modernized version features:

- Updated Linux kernel (6.10.x) and Alpine Linux (3.21.0)
- ZFS filesystem support
- Enhanced system utilities for recovery and disk management
- Streamlined user experience with automatic root login
- Size and performance optimizations

## Building OneRecovery

### Using Docker (Recommended)

The easiest way to build OneRecovery is using Docker, which provides a consistent build environment regardless of your host system.

#### Prerequisites

- Docker installed and running
- Git
- At least 4GB free RAM
- At least 10GB free disk space

#### Build Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/OneRecovery.git
   cd OneRecovery/docker
   ```

2. Make the build script executable:
   ```bash
   chmod +x build-onerecovery.sh
   ```

3. Run the build with default settings:
   ```bash
   ./build-onerecovery.sh
   ```

4. For a full build with all features:
   ```bash
   ./build-onerecovery.sh -b "--full"
   ```

5. For a minimal build:
   ```bash
   ./build-onerecovery.sh -b "--minimal"
   ```

#### Docker Build Options

The `build-onerecovery.sh` script supports several options:

```
Usage: ./build-onerecovery.sh [options]

Options:
  -h, --help            Display this help message
  -c, --clean           Clean the Docker environment before building
  -v, --verbose         Enable verbose output
  -b, --build-args ARG  Pass build arguments to the build script
  -e, --env-file FILE   Specify a custom .env file
  -i, --interactive     Run in interactive mode (shell inside container)
  -p, --pull            Pull the latest base image before building
  --no-cache            Build the Docker image without using cache
```

#### Build Artifacts

After a successful build, the output file (`OneRecovery.efi`) will be placed in the `output/` directory in the root of the repository.

### Building Natively

If you prefer to build on your local system without Docker:

#### Prerequisites

For Debian/Ubuntu-based systems:
```bash
sudo apt-get update
sudo apt-get install build-essential git autoconf automake libtool \
  util-linux libelf-dev libssl-dev zlib1g-dev libzstd-dev liblz4-dev \
  upx xz-utils zstd curl wget sudo python3 gcc g++ make patch \
  libncurses-dev e2fsprogs coreutils mtools xorriso squashfs-tools
```

For Alpine Linux:
```bash
apk add build-base git autoconf automake libtool util-linux elfutils-dev \
  openssl-dev zlib-dev zstd-dev lz4-dev upx xz zstd curl wget sudo \
  python3 gcc g++ make patch ncurses-dev e2fsprogs coreutils mtools \
  xorriso squashfs-tools
```

#### Build Steps

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/OneRecovery.git
   cd OneRecovery
   ```

2. Run the build scripts sequentially:
   ```bash
   cd build
   ./build.sh
   ```

3. Or run each build step manually:
   ```bash
   ./00_prepare.sh   # Prepare the build environment
   ./01_get.sh       # Download and extract sources
   ./02_chrootandinstall.sh  # Set up chroot and install packages
   ./03_conf.sh      # Configure the system
   ./04_build.sh     # Build the final EFI file
   ```

4. After successful completion, the `OneRecovery.efi` file will be created in the repository root directory.

5. Optional: Clean up build artifacts:
   ```bash
   ./99_cleanup.sh
   ```

### Build Options

OneRecovery offers several build configurations to balance features and size:

#### Build Types

| Build Type | Description | Size | Command |
|------------|-------------|------|---------|
| Minimal | Core functionality only | ~30-50MB | `--minimal` |
| Standard | Basic recovery features | ~60-90MB | (default) |
| Full | All features and tools | ~100-150MB | `--full` |

#### Advanced Package Groups

You can customize your build with these package groups:

| Package Group | Size Impact | Description | Flag |
|---------------|-------------|-------------|------|
| Advanced FS | ~10MB | Extra filesystem tools | `--with-advanced-fs` |
| Disk Diagnostics | ~15MB | Hardware testing tools | `--with-disk-diag` |
| Network Tools | ~12MB | Network diagnostics | `--with-network-diag` |
| System Tools | ~8MB | Advanced system utilities | `--with-system-tools` |
| Data Recovery | ~20MB | Data rescue utilities | `--with-data-recovery` |
| Boot Repair | ~15MB | Bootloader repair tools | `--with-boot-repair` |
| Advanced Editors | ~5MB | Text editors and tools | `--with-editors` |
| Security Tools | ~10MB | Security analysis tools | `--with-security` |

#### Detailed Build Script Options

The `build.sh` script accepts numerous options to customize your build. Here's a comprehensive list of all available options:

##### Build Types
```
--minimal              Minimal build optimized for size (~30-50% smaller)
--full                 Full build with all available components
```

##### Size Optimization Options
```
--with-compression     Enable EFI file compression (default: yes)
--without-compression  Disable EFI file compression (faster boot)
--compression-tool=TOOL Select compression tool (upx, xz, zstd) (default: upx)
```

##### Build Performance Options
```
--use-cache            Enable source and build caching (default: yes)
--no-cache             Disable source and build caching
--cache-dir=DIR        Set cache directory (default: ~/.onerecovery/cache)
--jobs=N               Set number of parallel build jobs (default: CPU cores)
--keep-ccache          Keep compiler cache between builds (default: yes)
--no-keep-ccache       Clear compiler cache between builds
--use-swap             Create swap file if memory is low (default: no)
--no-swap              Do not create swap file even if memory is low
--interactive-config   Use interactive kernel configuration (menuconfig)
--no-interactive-config Use non-interactive kernel config (default)
```

##### Security Options
```
--password=PASS        Set custom root password (CAUTION: visible in process list)
--random-password      Generate random root password (default)
--no-password          Create root account with no password (unsafe)
--password-length=N    Set length of random password (default: 12)
```

##### Optional Modules
```
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
```

##### Advanced Package Groups
```
--with-advanced-fs     Include advanced filesystem tools
--without-advanced-fs  Exclude advanced filesystem tools
--with-disk-diag       Include disk and hardware diagnostics
--without-disk-diag    Exclude disk and hardware diagnostics
--with-network-diag    Include network diagnostics and VPN tools
--without-network-diag Exclude network diagnostics and VPN tools
--with-system-tools    Include advanced system utilities
--without-system-tools Exclude advanced system utilities
--with-data-recovery   Include data recovery utilities
--without-data-recovery Exclude data recovery utilities
--with-boot-repair     Include boot repair tools
--without-boot-repair  Exclude boot repair tools
--with-editors         Include advanced text editors
--without-editors      Exclude advanced text editors
--with-security        Include security tools
--without-security     Exclude security tools
--with-all-advanced    Include all advanced package groups
--without-all-advanced Exclude all advanced package groups
```

##### Configuration Management
```
--save-config          Save current configuration as default
--show-config          Display current build configuration
```

#### Common Build Command Examples

```bash
# Minimal build with only ZFS support
./build.sh --minimal --with-zfs --without-all-advanced

# Standard build with advanced filesystem tools and data recovery
./build.sh --with-advanced-fs --with-data-recovery

# Full featured build with everything included
./build.sh --full

# Custom build with specific tools
./build.sh --with-zfs --with-btrfs --with-network-tools --with-disk-diag

# Minimal build with high compression
./build.sh --minimal --compression-tool=xz

# Build without compression for faster boot time
./build.sh --without-compression

# Custom build with specific performance settings
./build.sh --jobs=8 --cache-dir=/tmp/cache --use-swap

# Build with interactive kernel configuration
./build.sh --interactive-config

# Build with a custom root password
./build.sh --password=mypassword

# Build with a specific random password length
./build.sh --random-password --password-length=16
```

#### EFI Partition Size Considerations

When planning to use OneRecovery, keep in mind these EFI partition size guidelines:

- **Minimal build**: 100MB EFI partition is sufficient
- **Standard build**: 150MB EFI partition recommended
- **Full build**: 260MB EFI partition recommended

Most modern systems have EFI partitions ranging from 100MB to 260MB.

## Installation

### macOS Installation

1. **Download OneRecovery.efi**
   From the releases page or build it yourself.

2. **Mount the EFI System Partition**
   ```bash
   diskutil list               # Identify your EFI partition (typically disk0s1)
   diskutil mount disk0s1      # Replace with your EFI partition identifier
   ```

3. **Copy OneRecovery.efi to the EFI Partition**
   ```bash
   cp ~/Downloads/OneRecovery.efi /Volumes/EFI/
   ```

4. **Configure Boot Options**
   
   Since macOS El Capitan, System Integrity Protection (SIP) requires boot option changes to be made from Recovery Mode:
   
   1. Check SIP status: `csrutil status` (Enabled by default)
   2. Restart and hold **CMD+R** during startup to enter Recovery Mode
   3. Open Terminal from Utilities menu
   4. Mount the EFI partition (step 2)
   5. Set the boot option:
      ```bash
      bless --mount /Volumes/EFI --setBoot --nextonly --file /Volumes/EFI/OneRecovery.efi
      ```
      
   This configures a one-time boot of OneRecovery, preserving your default boot order.

5. **Reboot to Start OneRecovery**
   
   After using OneRecovery, type `reboot` in the Linux console to return to macOS. Repeat steps 2 and 4 from Recovery Mode for subsequent uses.

### PC/Windows Installation

There are multiple methods to boot OneRecovery on PC systems. The following procedure works for most systems without built-in UEFI Shell access.

1. **Access the EFI System Partition**
   
   Windows 10+ systems installed in UEFI mode typically have a 100MB EFI partition.
   You will need either:
   - A Linux live USB to access this partition
   - An existing installation of OneRecovery via USB
   
2. **Configure NVRAM Boot Option**
   
   Using Linux, add a boot entry with efibootmgr:
   ```bash
   efibootmgr --disk /dev/sda --part 1 --create --label "OneRecovery" --loader /OneRecovery.efi
   ```
   
   Replace `/dev/sda` with your disk path and `--part 1` with your EFI partition number.

3. **Boot OneRecovery**
   
   Boot into your computer's boot menu (typically F12, F10, or Esc during startup) and select "OneRecovery".

### USB Flash Drive Installation

For portable use or when direct EFI partition access is difficult:

1. **Format a USB Drive with GPT Partition Scheme**
   
   In Windows:
   ```
   1. Open Administrator Command Prompt
   2. Run diskpart
   3. list disk
   4. select disk N (replace N with your USB drive number)
   5. clean
   6. convert gpt
   7. create partition primary
   8. format fs=fat32 quick
   9. assign
   10. exit
   ```
   
   In macOS:
   ```bash
   diskutil list                        # Find your USB drive
   diskutil eraseDisk FAT32 ONERECOVERY GPT /dev/diskN  # Replace diskN with your USB
   ```
   
   In Linux:
   ```bash
   sudo gdisk /dev/sdX                  # Replace sdX with your USB drive
   # Create a new GPT table (o), create a partition (n), write changes (w)
   sudo mkfs.vfat -F 32 /dev/sdX1       # Format the partition
   ```

2. **Install OneRecovery**
   
   Create the directory structure and copy the file:
   
   Windows:
   ```
   mkdir -p X:\EFI\BOOT          # Replace X: with your USB drive letter
   copy OneRecovery.efi X:\EFI\BOOT\BOOTx64.EFI
   ```
   
   macOS/Linux:
   ```bash
   mkdir -p /Volumes/ONERECOVERY/EFI/BOOT   # macOS
   # OR
   mkdir -p /mnt/usb/EFI/BOOT               # Linux (mount point may vary)
   
   cp OneRecovery.efi /Volumes/ONERECOVERY/EFI/BOOT/BOOTx64.EFI   # macOS
   # OR
   cp OneRecovery.efi /mnt/usb/EFI/BOOT/BOOTx64.EFI               # Linux
   ```

3. **Boot from USB**
   
   Select the USB drive from your computer's boot menu.

## Using OneRecovery

### Text User Interface

When you boot OneRecovery, it automatically logs in as root and launches the text-based user interface (TUI). The TUI provides an easy-to-use menu system for common recovery operations.

#### Main Menu

The main menu provides access to the following functions:

1. **System Information**: Hardware details, disk information, and system status
2. **Filesystem Tools**: Mount, unmount, check, and repair filesystems
3. **Data Recovery**: Tools for rescuing lost or damaged data
4. **Disk Management**: Partition, format, and manage disks
5. **Network Tools**: Configure network interfaces and run diagnostics
6. **Boot Repair**: Fix boot issues on Windows, Linux, and macOS
7. **Advanced Tools**: Additional system utilities and diagnostic tools
8. **Help**: Documentation and usage information

Navigate the menu using arrow keys, Tab, and Enter. Press 'q' or Escape to go back or exit menus.

### Common Recovery Operations

#### Mounting Filesystems

1. From the main menu, select "Filesystem Tools"
2. Choose "Mount Filesystem"
3. Select the partition to mount
4. Specify the mount point (or use the default)
5. Select filesystem type (if not automatically detected)

Example command-line alternative:
```bash
mount /dev/sda1 /mnt
```

#### Checking and Repairing Filesystems

1. From the main menu, select "Filesystem Tools"
2. Choose "Check/Repair Filesystem"
3. Select the partition to check
4. Choose between "Check Only" or "Check and Repair"

Example command-line alternatives:
```bash
# For ext2/3/4
fsck.ext4 -f /dev/sda1

# For ZFS
zpool import -f poolname
zpool scrub poolname

# For Btrfs
btrfs check /dev/sda1
```

#### Recovering Deleted Files

1. From the main menu, select "Data Recovery"
2. Choose "Recover Deleted Files"
3. Select the partition to scan
4. Select file types to recover
5. Specify a destination for recovered files

Example command-line alternative:
```bash
testdisk /dev/sda
```

#### Disk Partitioning

1. From the main menu, select "Disk Management"
2. Choose "Partition Disk"
3. Select the disk to partition
4. Follow the interactive prompts

Example command-line alternatives:
```bash
fdisk /dev/sda
# OR
gdisk /dev/sda   # For GPT partitioning
```

#### Fixing Boot Issues

1. From the main menu, select "Boot Repair"
2. Choose the operating system type (Windows, Linux, macOS)
3. Follow the guided repair process

### Working with Filesystems

#### ZFS Operations

OneRecovery includes comprehensive ZFS support. Common operations:

```bash
# Import pool
zpool import -f poolname

# Check pool status
zpool status poolname

# Repair pool (scrub)
zpool scrub poolname

# Export pool cleanly
zpool export poolname

# Mount ZFS dataset
zfs mount poolname/dataset

# List all datasets
zfs list

# Take a snapshot
zfs snapshot poolname/dataset@snapshot1
```

#### Btrfs Operations

If your build includes Btrfs support:

```bash
# Mount Btrfs filesystem
mount -t btrfs /dev/sda1 /mnt

# Check filesystem
btrfs check /dev/sda1

# Repair filesystem
btrfs check --repair /dev/sda1

# List subvolumes
btrfs subvolume list /mnt

# Mount specific subvolume
mount -t btrfs -o subvol=subvolname /dev/sda1 /mnt
```

#### Working with Encrypted Volumes

```bash
# Open LUKS encrypted volume
cryptsetup luksOpen /dev/sda1 mydisk

# Mount the decrypted volume
mount /dev/mapper/mydisk /mnt

# Close encrypted volume
umount /mnt
cryptsetup luksClose mydisk
```

### Network Connectivity

#### Configuring Wired Network

1. From the main menu, select "Network Tools"
2. Choose "Configure Network Interface"
3. Select the Ethernet interface
4. Choose between DHCP or Static IP configuration

Example command-line alternative:
```bash
# Using DHCP
dhclient eth0

# Static IP configuration
ip addr add 192.168.1.100/24 dev eth0
ip route add default via 192.168.1.1
echo "nameserver 8.8.8.8" > /etc/resolv.conf
```

#### Configuring Wireless Network

If your build includes wireless tools:

1. From the main menu, select "Network Tools"
2. Choose "Configure Wireless Network"
3. Select the wireless interface
4. Scan for networks and select one
5. Enter the network password

Example command-line alternative:
```bash
# Scan for networks
iwlist wlan0 scan

# Connect to WPA/WPA2 network
wpa_passphrase MyNetwork MyPassword > /etc/wpa_supplicant.conf
wpa_supplicant -B -i wlan0 -c /etc/wpa_supplicant.conf
dhclient wlan0
```

#### Remote Access

If your build includes SSH:

1. From the main menu, select "Network Tools"
2. Choose "Enable SSH Server"
3. Set a root password when prompted

The system will display the IP address and connection instructions.

Example command-line alternative:
```bash
# Start SSH server
passwd root  # Set a password
/etc/init.d/sshd start

# Check your IP address
ip addr show
```

## Troubleshooting

### Boot Issues

#### System Doesn't Boot OneRecovery

1. Verify that your system boots in UEFI mode, not legacy BIOS
2. Check that the EFI file is in the correct location
3. For USB boot, ensure the drive is formatted as GPT with FAT32
4. Try using the UEFI boot menu (F12, F10, Esc, etc. during startup)

#### Black Screen After Booting

1. Try booting with basic video mode (add `nomodeset` to kernel parameters)
2. If using NVIDIA graphics, try the `nouveau.modeset=0` kernel parameter

#### No Keyboard or Mouse Input

1. Check that USB ports are working
2. Try different USB ports, particularly USB 2.0 ports
3. For exotic hardware, try a PS/2 keyboard if available

### Hardware Compatibility

#### Storage Devices Not Detected

1. Check SATA/NVMe controller mode in BIOS (AHCI mode is preferred)
2. For NVMe drives, ensure your build includes NVMe support
3. For unusual storage controllers, load additional drivers:
   ```bash
   modprobe driver_name
   ```

#### Network Interfaces Not Working

1. Check if the interface is detected:
   ```bash
   ip link show
   ```
2. For wireless adapters, verify driver loading:
   ```bash
   lspci -k | grep -A 3 Network
   ```
3. Load additional drivers if needed:
   ```bash
   modprobe driver_name
   ```

### Common Errors

#### "No such file or directory" when mounting

The specified device doesn't exist or has a different name. Check available devices:
```bash
fdisk -l
# OR
lsblk
```

#### "Unknown filesystem type" when mounting

Your build may not include support for that filesystem. Try specifying the filesystem type:
```bash
mount -t filesystem_type /dev/device /mount_point
```

#### "Can't read superblock" when checking filesystem

The filesystem may be severely corrupted. Try alternative superblocks:
```bash
# For ext filesystems, find backup superblocks
mke2fs -n /dev/device

# Then use a backup superblock
fsck.ext4 -b 32768 /dev/device
```

#### ZFS pool can't be imported

Try forcing the import:
```bash
zpool import -f pool_name
# If that fails, try with all pools
zpool import -fA
# For severe cases, try 
zpool import -fFX pool_name
```

## Advanced Usage

### Custom Configurations

#### Adding Custom Utilities

If you've built OneRecovery yourself, you can add custom utilities by:

1. Modifying the package list in `02_chrootandinstall.sh`
2. Adding custom scripts to the `zfiles/` directory
3. Rebuilding the system

#### Creating Custom Recovery Scripts

Create custom recovery scripts by adding them to the system:

1. Mount your root filesystem:
   ```bash
   mount /dev/sda1 /mnt
   ```

2. Create a script in a persistent location:
   ```bash
   vi /mnt/usr/local/bin/my-recovery.sh
   chmod +x /mnt/usr/local/bin/my-recovery.sh
   ```

### Recovery Scenarios

#### Recovering from Deleted Partition Table

1. Boot into OneRecovery
2. Use TestDisk to scan for lost partitions:
   ```bash
   testdisk /dev/sda
   ```
3. Follow the prompts to search for lost partitions
4. Write the recovered partition table

#### Rescuing Files from Failed Drive

1. Boot into OneRecovery
2. If the drive is physically failing, create a disk image:
   ```bash
   ddrescue /dev/failed_drive /mnt/backup/disk.img /mnt/backup/logfile
   ```
3. Mount the image and recover files:
   ```bash
   mount -o loop /mnt/backup/disk.img /mnt/recovered
   ```

#### Fixing Boot Problems

1. Boot into OneRecovery
2. For Linux boot issues:
   ```bash
   mount /dev/sda1 /mnt            # Mount root filesystem
   mount /dev/sda2 /mnt/boot       # Mount boot filesystem if separate
   mount --bind /dev /mnt/dev
   mount --bind /proc /mnt/proc
   mount --bind /sys /mnt/sys
   chroot /mnt
   grub-install /dev/sda
   update-grub
   exit
   ```

3. For Windows boot issues, use the Boot Repair menu option

### Performance Considerations

#### Working with Large Drives

For large drives (>2TB), use these optimizations:

1. Set a larger block size when creating filesystems:
   ```bash
   mkfs.ext4 -b 4096 /dev/device
   ```

2. For large file operations, adjust buffer size:
   ```bash
   cp --buffer-size=16M source destination
   ```

#### Memory Optimization

If OneRecovery is running slowly due to memory constraints:

1. Create and use a swap file:
   ```bash
   dd if=/dev/zero of=/tmp/swap bs=1M count=1024
   mkswap /tmp/swap
   swapon /tmp/swap
   ```

2. Clear disk caches if needed:
   ```bash
   echo 3 > /proc/sys/vm/drop_caches
   ```

#### Speeding Up Filesystem Checks

For large filesystems, speed up checks by:

1. Using multiple passes with optimized options:
   ```bash
   # For ext4
   fsck.ext4 -C0 -f -y /dev/device
   ```

2. For ZFS scrubs, set a higher priority:
   ```bash
   zpool scrub -p high poolname
   ```

---

This User Guide is continuously improved. Please refer to the official documentation repository for the latest version and additional information.