# Project Moved!

  **⚠️ This repository is no longer maintained ⚠️**

  ### OneRecovery has been renamed to OneFileLinux!

  This project has moved to a new home and returned to its original upstream name:
  https://github.com/Bondrake/OneFileLinux

  #### Why the name change?
  We've adopted the original "OneFileLinux" name to honor the project's heritage and to better reflect its purpose: a complete Linux system in a single file. This simplifies project discovery and
  better aligns with the original vision.

  The new repository includes:
  - Modern kernel (6.12) and Alpine Linux (3.21)
  - ZFS and Btrfs support
  - Comprehensive recovery tools
  - Improved build system
  - Docker support
  - Continuous integration via GitHub Actions

  All future development, issues, and pull requests should be directed to the new repository.

  Thank you for your interest in this project!

# OneRecovery

OneRecovery is a single-file EFI-based Linux recovery environment designed for data recovery, system repair, and diagnostics.

<img width=600 alt="OneRecovery" src="https://hub.zhovner.com/img/one-file-linux.png" />

## Why OneRecovery?

OneRecovery provides a powerful system recovery solution with unique advantages:

- **Zero Installation Required**: No need to create additional partitions or modify your system
- **No External Media Needed**: Once copied to your EFI partition, it's always available
- **Boot Directly From UEFI**: No additional boot managers required
- **Works With Encrypted Disks**: Compatible with FileVault, BitLocker, and dm-crypt
- **Leave No Trace**: Configure for one-time boot without changing default boot sequence
- **Hardware-Level Access**: Direct access to hardware not available in virtual machines

## Features

- **Single EFI File**: Boots directly from UEFI without additional bootloaders
- **Advanced Filesystems**: Support for ZFS, Btrfs, ext4, XFS, and more
- **Hardware Diagnostics**: Tools for hardware testing and analysis
- **Network Support**: Ethernet, WiFi, and remote recovery capabilities
- **Data Recovery**: Specialized tools for rescuing data from failed systems
- **Boot Repair**: Tools to fix common boot problems across operating systems
- **Text UI**: Full-featured text-based user interface for easy navigation
- **Ultra Size Optimized**: Minimal builds around 4MB, standard builds around 20MB

## Getting Started

### Building with Docker (Recommended)

The easiest way to build OneRecovery is using Docker, which provides a consistent build environment:

```bash
# Clone the repository
git clone https://github.com/yourusername/OneRecovery.git
cd OneRecovery/docker

# Build with default settings
./build-onerecovery.sh

# Or build with specific options
./build-onerecovery.sh -b "--full"
./build-onerecovery.sh -b "--minimal"
```

See the [Docker build documentation](docker/README.md) for more details.

### Building Natively

If you prefer to build on your local system:

```bash
# Install build dependencies (Ubuntu/Debian example)
sudo apt-get update
sudo apt-get install build-essential git autoconf automake libtool \
  util-linux libelf-dev libssl-dev zlib1g-dev libzstd-dev liblz4-dev \
  upx xz-utils zstd curl wget sudo python3 gcc g++ make patch \
  libncurses-dev e2fsprogs coreutils mtools xorriso squashfs-tools

# Clone the repository
git clone https://github.com/yourusername/OneRecovery.git
cd OneRecovery

# Run the build
cd build
./build.sh
```

## Build Options

OneRecovery offers several build configurations to balance features and size:

| Build Type | Description | Size | Command |
|------------|-------------|------|---------|
| Minimal | Core functionality only | ~4MB | `--minimal` |
| Standard | Basic recovery features | ~20MB | (default) |
| Full | All features and tools | ~40-60MB | `--full` |

### Advanced Package Groups

You can customize your build with these package groups:

| Package Group | Size Impact | Description | Flag | Included Packages |
|---------------|-------------|-------------|------|-------------------|
| Advanced FS | ~10MB | Extra filesystem tools | `--with-advanced-fs` | ntfs-3g, xfsprogs, gptfdisk, exfatprogs, f2fs-tools |
| Disk Diagnostics | ~15MB | Hardware testing tools | `--with-disk-diag` | smartmontools, hdparm, nvme-cli, dmidecode, lshw |
| Network Diagnostics | ~12MB | Network diagnostics | `--with-network-diag` | ethtool, nmap, wireguard-tools, openvpn |
| System Tools | ~8MB | Advanced system utilities | `--with-system-tools` | htop, strace, pciutils, usbutils |
| Data Recovery | ~20MB | Data rescue utilities | `--with-data-recovery` | testdisk (includes photorec) |
| Boot Repair | ~15MB | Bootloader repair tools | `--with-boot-repair` | grub |
| Advanced Editors | ~5MB | Text editors and tools | `--with-editors` | vim, tmux, jq |
| Security Tools | ~10MB | Security analysis tools | `--with-security` | openssl |

## Installation

1. Copy the generated `OneRecovery.efi` to your EFI System Partition (ESP):
   ```bash
   sudo mkdir -p /boot/efi/EFI/OneRecovery
   sudo cp output/OneRecovery.efi /boot/efi/EFI/OneRecovery/
   ```

2. Add a boot entry (optional, you can also boot it directly from UEFI):
   ```bash
   sudo efibootmgr --create --disk /dev/sda --part 1 --label "OneRecovery" --loader '\EFI\OneRecovery\OneRecovery.efi'
   ```

3. Boot into UEFI and select OneRecovery from the boot menu.

For detailed installation instructions for macOS, Windows, and creating bootable USB drives, see the [User Guide](docs/USER_GUIDE.md).

## EFI Partition Size Considerations

When planning to use OneRecovery, keep in mind these EFI partition size guidelines:

- **Minimal build**: 100MB EFI partition is sufficient
- **Standard build**: 150MB EFI partition recommended
- **Full build**: 260MB EFI partition recommended

Most modern systems have EFI partitions ranging from 100MB to 260MB.

## Documentation

- [User Guide](docs/USER_GUIDE.md)
- [Docker Build Instructions](docker/README.md)
- [Future Improvements](FUTURE_IMPROVEMENTS.md)
- [Contributing Guidelines](CONTRIBUTING.md)

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgements

- Based on Alpine Linux
- Uses the Linux kernel
- ZFS implementation from OpenZFS
- Many open source recovery tools

## Contributing

Contributions are welcome! Please see our [Contributing Guidelines](CONTRIBUTING.md) for more information.
