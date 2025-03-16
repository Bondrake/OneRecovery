# OneRecovery

OneRecovery is a lightweight Linux distribution contained in a single EFI executable file that runs on any UEFI computer (PC or Mac) without installation. The system is deployed by copying a single file to the EFI system partition and configuring boot options.

<img width=600 alt="OneRecovery" src="https://hub.zhovner.com/img/one-file-linux.png" />

## Project History

OneRecovery is a fork of the original OneFileLinux project, which hasn't been maintained for over 5 years. This modernized version features:

- Updated Linux kernel (6.12.x) and Alpine Linux (3.21.3)
- ZFS filesystem support
- Enhanced system utilities for recovery and disk management
- Streamlined user experience with automatic root login
- Size and performance optimizations

## Key Advantages

- **Zero Installation Requirements**: No additional partitions needed; simply copy one file to the EFI system partition and add a boot entry to NVRAM.
  
- **No USB Flash Needed**: Once copied to the EFI partition, OneRecovery can boot any time from the system disk.
  
- **Direct Boot Capability**: Boots directly via UEFI firmware without requiring boot managers like GRUB or rEFInd.
  
- **Non-Disruptive Operation**: Can be configured for one-time boot, preserving the default boot sequence for subsequent reboots.
  
- **Encryption Compatibility**: Works alongside disk encryption solutions including macOS FileVault and Linux dm-crypt, as the EFI system partition remains unencrypted.

## Use Cases

OneRecovery provides direct hardware access capabilities not available in virtual machines, including:

- System recovery and data rescue operations
- Hardware diagnostics and testing
- Access to internal PCIe devices (such as WiFi cards for network diagnostics)
- Disk management and filesystem recovery with ZFS support

## Platform-Specific Installation

### EFI Partition Size Considerations

The EFI System Partition (ESP) typically has the following default sizes:
- Windows systems: 100-260 MB
- macOS systems: 200 MB
- Linux systems: 100-550 MB (varies by distribution)

When using the full build with all advanced package groups, the OneRecovery.efi file size can be up to 150-200 MB, which may approach or exceed the available space on some EFI partitions. Consider these options:

1. **Selective Package Groups**: Use only the package groups you need instead of `--with-all-advanced` or `--full`
2. **Resize EFI Partition**: On some systems, you can resize the EFI partition (requires advanced partitioning tools)
3. **Use USB Installation**: For larger builds, consider the USB flash drive installation method
4. **Use Compression**: Ensure compression is enabled with `--with-compression` (default)

> **Note**: If you encounter "No space left on device" errors when copying to the EFI partition, build a smaller version by excluding package groups you don't need.

### macOS Installation

1. **Download OneRecovery.efi**
   From the releases page or build it yourself.

2. **Mount the EFI System Partition**
   ```bash
   diskutil list               # Identify your EFI partition (typically disk0s1)
   diskutil mount disk0s1      # Replace with your EFI partition identifier
   ```
   
   <img width="500" alt="macOS diskutil list EFI partition" src="https://hub.zhovner.com/img/diskutil-list-efi.png" />

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
   
   <img alt="Boot menu example" width="600" src="https://hub.zhovner.com/img/thinkpad-x220-boot-menu.png" />

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

2. **Install OneRecovery**
   
   Create the directory structure and copy the file:
   ```
   mkdir -p X:\EFI\BOOT          # Replace X: with your USB drive letter
   copy OneRecovery.efi X:\EFI\BOOT\BOOTx64.EFI
   ```

3. **Boot from USB**
   
   Select the USB drive from your computer's boot menu.



## Technical Overview

### Architecture
OneRecovery creates a single EFI executable file that contains a complete Linux system, allowing it to boot directly via UEFI without installation. The core components are:

- Linux kernel (6.12.19)
- Alpine Linux minimal rootfs (3.21.3)
- ZFS filesystem support (2.3.0)
- System utilities for recovery operations

### Key Features
- **Non-invasive**: Runs without modifying existing systems
- **Text-based UI**: Simple menu-driven interface for common recovery tasks
  - Optional TUI component provides easy-to-navigate menus for disk operations
  - Includes wizards for common recovery tasks
  - Can be disabled with `--without-tui` for a minimal CLI-only interface
- **Hardware access**: Direct access to hardware components (like PCIe WiFi cards)
- **Filesystem support**: Handles ext4, ZFS, FAT32, etc.
- **Disk management**: LVM, RAID, encryption (cryptsetup)
- **Network tools**: DHCP, SSH (dropbear), basic utilities
- **Recovery tools**: Disk utilities, filesystem tools, debootstrap
- **Size optimization**: Configurable build options to reduce EFI file size

### Use Cases
- Recovering data from systems with inaccessible primary OS
- Working with hardware that can't be virtualized
- Penetration testing using internal hardware
- Emergency system recovery and maintenance
- Working alongside encrypted filesystems


## Building from Source

OneRecovery can be built from source using the build system. The build environment is based on Alpine Linux and the vanilla Linux kernel.

### Prerequisites

- **Linux build environment** (required): The build process uses Linux-specific tools and chroot, which won't work directly on macOS
  - If using macOS, you'll need to use a Linux virtual machine or container
  - Docker or a Linux VM (via UTM/VirtualBox/Parallels) is recommended for macOS users
- Standard build tools (gcc, make, etc.)
- Approximately 5GB of free disk space
- Internet connection for downloading source components
- Required packages:
  - Linux: `wget`, `tar`, `xz-utils`, `flex`, `bison`, `libssl-dev` (or `openssl-devel` on Fedora/RHEL)
  - On macOS/Docker: Install wget if needed: `brew install wget` (only for downloading, actual build requires Linux)

### Build Process

The build system (in the `build` directory) uses a sequence of numbered scripts with robust error handling:

1. `00_prepare.sh`: Detects OS, installs dependencies, and prepares the build environment
2. `01_get.sh`: Downloads and extracts Alpine Linux, Linux kernel, and ZFS sources
3. `02_chrootandinstall.sh`: Sets up the chroot environment and installs packages
4. `03_conf.sh`: Configures system services, network, auto-login, and kernel settings
5. `04_build.sh`: Builds the kernel, modules, ZFS support, and creates the EFI file
   - Supports interactive kernel configuration with the `--interactive-config` flag
   - Uses non-interactive defaults by default for automated builds
6. `99_cleanup.sh`: Removes build artifacts after successful build

All build scripts include:
- Comprehensive error handling with detailed diagnostic messages
- Prerequisite checking to ensure dependencies are met
- The ability to resume from checkpoints with the `--resume` flag
- Detailed logging to help troubleshoot build failures

### Build Instructions

#### Option 1: Single Command Build (Recommended)

1. Clone the repository:  
   ```bash
   git clone https://github.com/Bondrake/OneRecovery
   cd OneRecovery/build
   ```

2. Run the unified build script:
   ```bash
   sudo ./build.sh
   ```
   
   This will automatically:
   - Prepare the build environment (install dependencies)
   - Download all required components
   - Set up the chroot environment
   - Configure the system
   - Build the kernel and create the final EFI file

3. After successful completion, the `OneRecovery.efi` file will be created in the repository root directory.

#### Option 2: Step-by-Step Build

If you prefer more control over the build process, you can run each step manually:

1. Clone the repository:  
   ```bash
   git clone https://github.com/Bondrake/OneRecovery
   cd OneRecovery/build
   ```

2. Prepare the build environment:
   ```bash
   sudo ./00_prepare.sh     # Detects OS and installs required dependencies
   ```

3. Run the build scripts in sequence:  
   ```bash
   ./01_get.sh              # Download components
   sudo ./02_chrootandinstall.sh  # Set up chroot environment
   ./03_conf.sh             # Configure system
   ./04_build.sh            # Build kernel and create EFI file
   ```
   
4. After successful completion, the `OneRecovery.efi` file will be created in the repository root directory.

5. Optional: Clean up build artifacts:
   ```bash
   ./99_cleanup.sh
   ```

#### Size Optimization Options

OneRecovery offers several options to reduce the size of the final EFI file:

- **Minimal Build** (`--minimal`): Creates a substantially smaller EFI file by:
  - Excluding ZFS, recovery tools, and other optional components
  - Using a size-optimized kernel configuration (`kernel-minimal.config`)
  - Disabling unnecessary kernel modules and features
  - Reducing included drivers to essential hardware support only
  - Optimizing for size over performance (using compiler flags like -Os)

- **Component Selection**: Selectively include only needed components:
  - `--without-zfs`: Exclude ZFS support for smaller size
  - `--without-recovery-tools`: Skip TestDisk and other recovery utilities
  - `--without-network-tools`: Skip advanced networking tools
  - `--without-crypto`: Skip encryption-related tools
  - `--without-tui`: Skip the Text User Interface for minimal CLI experience
  
- **Advanced Package Groups**: Carefully select only required advanced package groups to control size:
  - Each advanced package group has a different size impact (from ~4 MB to ~20 MB)
  - Including all advanced packages adds approximately 75 MB to the EFI file size
  - See the Advanced Package Groups section for size estimates of each group

- **EFI Compression** (`--with-compression`, on by default):
  - Compresses the final EFI file using compression tools
  - Multiple compression options available:
    - UPX (default): 20-30% size reduction with fast decompression
    - XZ: 30-40% size reduction but slower decompression
    - ZSTD: Balanced compression ratio and speed
  - Select with `--compression-tool=TOOL` (options: upx, xz, zstd)
  - Can be disabled with `--without-compression` for faster boot time

These optimization options can be combined as needed to balance size, features, and performance.

#### Advanced Build Options

The unified build script offers several options for customizing the build process:

```bash
Usage: ./build.sh [options] [STEP]

Options:
  -h, --help          Display this help message
  -c, --clean-start   Run cleanup script before starting (removes previous builds)
  -v, --verbose       Enable verbose output
  -s, --skip-prepare  Skip environment preparation step
  -r, --resume        Resume from last successful step (if possible)
  -C, --clean-end     Run cleanup script after successful build

Steps:
  all                 Run all build steps (default)
  prepare             Run only environment preparation (00_prepare.sh)
  get                 Run through downloading sources (01_get.sh)
  chroot              Run through chroot and install (02_chrootandinstall.sh)
  conf                Run through configuration (03_conf.sh)
  build               Run only the build step (04_build.sh)
  clean               Run only cleanup (99_cleanup.sh)

Optional Modules:
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
  --minimal              Minimal build with only essential components
  --full                 Full build with all available components and advanced package groups [~75 MB larger]
  --save-config          Save current configuration as default
  --show-config          Display current build configuration
  
Advanced Package Groups (with estimated EFI size impact):
  --with-advanced-fs     Include advanced filesystem tools (ntfs-3g, xfsprogs, etc.) [~7 MB]
  --with-disk-diag       Include disk & hardware diagnostics (smartmontools, etc.) [~8 MB] 
  --with-network-diag    Include network diagnostics and VPN tools [~15 MB]
  --with-system-tools    Include advanced system utilities (htop, strace, etc.) [~7 MB]
  --with-data-recovery   Include additional data recovery tools [~5 MB]
  --with-boot-repair     Include boot repair utilities (grub) [~10 MB]
  --with-editors         Include advanced text editors (vim, tmux, jq) [~20 MB]
  --with-security        Include security tools (openssl) [~4 MB]
  --with-all-advanced    Include all advanced package groups [~75 MB total]
  --without-all-advanced Exclude all advanced package groups

Build Configuration Management:
  --save-config          Save current configuration to build.conf for future builds
  --show-config          Display current build configuration
  --cache-dir=DIR        Set directory for caching sources (default: ~/.onerecovery/cache)
  --jobs=N               Set number of parallel build jobs (default: CPU cores)
  
Customization Options:
  --kernel-config=PATH   Use custom kernel configuration file
  --extra-packages=LIST  Install additional Alpine packages (comma-separated)
  
Compression Options:
  --with-compression     Enable EFI file compression (default: yes)
  --without-compression  Disable EFI file compression
  --compression-tool=TOOL Select compression tool: upx, xz, or zstd (default: upx)
  
Build Performance Options:
  --use-cache            Enable source and build caching (default: yes)
  --no-cache             Disable source and build caching
  --keep-ccache          Keep compiler cache between builds (default: yes)
  --no-keep-ccache       Clear compiler cache between builds
  --use-swap             Create swap file if memory is low (default: no)
  --no-swap              Do not create swap file even if memory is low
  
Kernel Configuration Options:
  --interactive-config   Use interactive kernel configuration (menuconfig)
  --no-interactive-config Use non-interactive kernel config (default)

The kernel configuration options control how the Linux kernel is configured:
- With `--interactive-config`, the build pauses at the kernel configuration step, displaying
  the menuconfig interface where you can customize all kernel options
- With `--no-interactive-config` (default), the build uses olddefconfig to automatically accept
  defaults for all new configuration options, enabling non-interactive builds
  
Security Options:
  --password=PASS        Set custom root password (CAUTION: visible in process list)
  --random-password      Generate random root password (default)
  --no-password          Create root account with no password (unsafe)
  --password-length=N    Set length of random password (default: 12)

The security options determine how the root account is configured:
- With `--random-password` (default), a secure random password is generated and saved to 
  `onerecovery-password.txt` in the build directory
- With `--password=PASS`, your specified password is used (note: visible in process list)
- With `--no-password`, an empty password is set (NOT RECOMMENDED for security reasons)

The password is securely hashed using SHA-512 and stored in the system's shadow file. 
The script supports multiple hashing methods (OpenSSL, mkpasswd) with automatic fallback.

Examples:
- `./build.sh -c` - Clean previous build and start fresh
- `./build.sh -r` - Resume build from last successful step
- `./build.sh build` - Run only the final build step
- `./build.sh -v` - Build with verbose output
- `./build.sh --without-zfs` - Build without ZFS support (smaller image)
- `./build.sh --minimal` - Build with minimal components for a smaller image
- `./build.sh --without-compression` - Disable EFI compression for faster boot time
- `./build.sh --with-btrfs --without-crypto` - Custom component selection
- `./build.sh --without-tui` - Build without the Text User Interface
- `./build.sh --full` - Build with all available components
- `./build.sh --compression-tool=zstd` - Use ZSTD compression instead of UPX
- `./build.sh --minimal --compression-tool=xz` - Minimal build with maximum compression
- `./build.sh --jobs=8` - Use 8 parallel build jobs
- `./build.sh --cache-dir=/tmp/cache` - Use custom cache directory
- `./build.sh --no-cache` - Perform a clean build without caching
- `./build.sh --use-swap` - Create swap file if system has low memory
- `./build.sh --password=SecurePass123` - Set specific root password
- `./build.sh --random-password` - Generate a secure random password
- `./build.sh --password-length=16` - Use longer random password
- `./build.sh --interactive-config` - Use interactive kernel configuration for custom kernel options
- `./build.sh --kernel-config=/path/to/custom.config` - Use a custom kernel configuration file
- `./build.sh --extra-packages=htop,vim,tmux` - Install additional Alpine packages
- `./build.sh --with-advanced-fs --with-disk-diag` - Add advanced filesystem and disk diagnostic tools
- `./build.sh --with-all-advanced` - Include all advanced package groups
- `./build.sh --with-editors --with-system-tools` - Add advanced editors and system utilities

### Balancing Size and Functionality

When building OneRecovery, consider these best practices:

1. **EFI Partition Size Constraints**: Standard EFI partitions are 100-260 MB on most systems
2. **Package Group Selection**: Choose only the advanced package groups you need for your specific use case
3. **Test on Target Systems**: Verify that your build fits on the EFI partitions of your target systems
4. **Compression Importance**: For full builds, compression is essential - UPX is fastest, while XZ offers better compression

Remember that each advanced package group adds size to the final EFI file. Consider using `--with-specific-groups` instead of `--with-all-advanced` for targeted functionality while keeping the file size manageable.

## License

OneRecovery is released under the [MIT License](LICENSE).
