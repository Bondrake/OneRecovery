# OneRecovery Build System

This directory contains the build system for OneRecovery. For complete documentation, see the [main README](../README.md).

## Quick Start

```bash
# Build with default options
sudo ./build.sh

# Build without ZFS support (smaller image)
sudo ./build.sh --without-zfs

# Build with minimal components
sudo ./build.sh --minimal
```

## Directory Structure

- `00_prepare.sh` - Prepares build environment and installs dependencies
- `01_get.sh` - Downloads Alpine Linux, Linux kernel, and ZFS sources
- `02_chrootandinstall.sh` - Sets up chroot and installs packages
- `03_conf.sh` - Configures system services and settings
- `04_build.sh` - Builds kernel and creates EFI executable
- `99_cleanup.sh` - Removes build artifacts
- `build.sh` - Unified build script
- `zfiles/` - Configuration files for the build
  - `.config` - Kernel configuration
  - `init` - System initialization script
  - `interfaces` - Network configuration
  - `profile` - System profile
  - `resolv.conf` - DNS configuration
  - `shadow` - User accounts configuration

## Configuration

The build process can be customized using command-line flags. Run `./build.sh --help` for a complete list of options.

## Advanced Usage

```bash
# Resume from last successful step
./build.sh -r

# Build with verbose output
./build.sh -v

# Run only specific step
./build.sh build
```

For detailed build instructions, troubleshooting, and component descriptions, see the [main README](../README.md).
