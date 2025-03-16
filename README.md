## One File Linux
Live linux distro combined in one file. Runs on any UEFI computer (PC or Mac) without installation. Just copy one file to EFI system partition and boot.

<img width=600 alt="One File Linux" src="https://hub.zhovner.com/img/one-file-linux.png" />

### Main advantages

* **No installation required** — no need to create additional paritions. Just copy one file to EFI system partition and add new boot entry to NVRAM.
  
* **No USB flash needed** — once copied to EFI partition, OneRecovery can boot any time from system disk.
  
* **No Boot Manager required (GRUB, rEFInd)** — boots directly by UEFI firmware, no additional software needed.
  
* **Doesn't change the boot sequence** — can boot only once, next reboot will return default settings.
  
* **Compatible with disk encryption** — works with macOS FileVault and dm-crypt. Because EFI system parition is not encrypted.

### Why?

This can be useful when you need Linux on bare metal and can't use USB flash. In comparison with Live USB flash, one file Linux setups permanently in EFI partition and can boot any time later.  
My personal goal is to use laptop's internal PCIe WiFi card for cracking WiFi with <b>aircrack-ng</b> and <b>reaver</b> software, since PCIe devices can't be forwarded into virtual machine. 

  
## Run on Macbook

#### 1. Download OneRecovery.efi.
  

#### 2. Mount EFI System Partition 

`diskutil mount diskN` 

where diskN is your EFI disk number.  
To find your EFI disk number use `diskutil list` command.  
  
<img width="500" alt="macOS diskutil list EFI partition" src="https://hub.zhovner.com/img/diskutil-list-efi.png" />

For me it will be: `diskutil mount disk0s1`

  
  
  
#### 3. Copy OneRecovery.efi to EFI partition
  
`cp ~/Downloads/OneRecovery.efi /Volumes/EFI/`

  
  
#### 4. Set boot option in NVRAM

On macOS since El Capitan enabled by default SIP (System Integrity Protection) prohibits to change boot options.  
To check SIP state run `csrutil status`. In normal situation it should be enabled.  
  
If SIP is enabled you can run `bless` only from Recovery console, otherwise it returns error.  
To boot in Recovery mode press <b>CMD+R</b> while boot and go to **_Utilities —> Terminal_** from top menu.  
In recovery console follow steps 2 and 4 every time you need to boot OneRecovery.  

`bless --mount /Volumes/EFI --setBoot --nextonly --file /Volumes/EFI/OneRecovery.efi`
  
  
This command sets NVRAM option to boot OneRecovery.efi only once. Next reboot will return default boot order. 
  
  
  
### 5. Reboot 

Reboot to run OneRecovery. Once you've done, type `reboot` in Linux console and go back to macOS.   
Every time when you need it again, follow steps 2 and 4 from recovery console.



## Run on PC
There are few ways how to run OneRecovery on PC motherboard. Some motherboards have builtin UEFI Shell that can run any efi binary from console.  
I will describe setup process for my old ThinkPad X220 that doesn't have UEFI shell. 

#### 1. Copy OneRecovery.efi to EFI partition 
  
If you use Windows 10 installed in EFI mode, you have EFI system partition 100 MB in size.  
You need to find out how to mount by itself. You can do this with OneRecovery.efi run from USB flash or any other linux distro.


#### 2. Add NVRAM boot option

I can't find out how to do this in Windows, so you probably need Linux for this.  
Replace `/dev/sda` to you disk path and `--part 2` to your EFI partition number.  
  
`efibootmgr --disk /dev/sda --part 2 --create --label "One File Linux" --loader /OneRecovery.efi`

#### 3. Choose One File Linux from boot menu

On my ThinkPad X220 I press F12 while power on to open boot menu. Hotkey depends on your motherboard.  
  
<img alt="ThinkPad X220 boot menu" width="600" src="https://hub.zhovner.com/img/thinkpad-x220-boot-menu.png" />



## Run from USB flash
The only benefit from running OneRecovery from USB flash, is that no additional software is required to create bootable flash drive.  
Just format flash drive as FAT32 in GPT scheme and copy OneRecovery.efi to default path:
  
`\EFI\BOOT\BOOTx64.EFI`  


#### Format in GPT scheme in Windows  

Windows does not allow to format flash drive in GPT scheme from GUI, so you need to use command line tool.  
1. Open `cmd.exe` as administrtor 
2. Type`diskpart`
3. `list disk` to see all disks
4. `select disk <disknumber>`
5. `clean` do delete parition table
6. `convert gpt` to convert disk in GPT scheme
7. `exit`

Then format drive from `diskmgmt.msc` in FAT32.



## About This Fork

OneRecovery is a fork of the original OneFileLinux project, which hasn't been maintained for over 5 years. This fork modernizes the codebase with current Linux kernel (6.10.x), updated Alpine Linux (3.21.0), and adds several important features:

- ZFS filesystem support
- Modern system utilities for recovery and disk management
- Automatic root login for easier access
- Size optimizations for better performance

## System Overview

### Architecture
OneRecovery creates a single EFI executable file that contains a complete Linux system, allowing it to boot directly via UEFI without installation. The core components are:

- Linux kernel (6.10.14)
- Alpine Linux minimal rootfs (3.21.0)
- ZFS filesystem support (2.3.0-rc3)
- System utilities for recovery operations

### Key Features
- **Non-invasive**: Runs without modifying existing systems
- **Hardware access**: Direct access to hardware components (like PCIe WiFi cards)
- **Filesystem support**: Handles ext4, ZFS, FAT32, etc.
- **Disk management**: LVM, RAID, encryption (cryptsetup)
- **Network tools**: DHCP, SSH (dropbear), basic utilities
- **Recovery tools**: Disk utilities, filesystem tools, debootstrap

### Use Cases
- Recovering data from systems with inaccessible primary OS
- Working with hardware that can't be virtualized
- Penetration testing using internal hardware
- Emergency system recovery and maintenance
- Working alongside encrypted filesystems

## Installation Instructions

### 1. Get the OneRecovery.efi file
Either download a pre-built release or build your own (see Build section below).

### 2. Choose an installation method

#### Option A: Direct Installation to EFI Partition
This method allows booting without external media:

1. Mount your EFI system partition
2. Copy OneRecovery.efi to the EFI partition
3. Configure your system to boot from this file (see macOS and PC instructions below)

#### Option B: USB Flash Drive
For portable use or when you can't access the EFI partition:

1. Format a USB flash drive as FAT32 with GPT partition scheme
2. Create the directory structure: `EFI/BOOT/`
3. Copy OneRecovery.efi to `/EFI/BOOT/BOOTx64.EFI`
4. Boot from the USB drive using your system's boot menu

### 3. Boot Configuration

#### For macOS:
```bash
# Mount EFI partition (first find it with diskutil list)
diskutil mount disk0s1  # Replace with your EFI partition

# Copy the file
cp path/to/OneRecovery.efi /Volumes/EFI/

# Set one-time boot option (must be done from Recovery Mode if SIP is enabled)
bless --mount /Volumes/EFI --setBoot --nextonly --file /Volumes/EFI/OneRecovery.efi
```

#### For PC/Windows:
```bash
# From Linux with efibootmgr:
efibootmgr --disk /dev/sda --part 1 --create --label "OneRecovery" --loader /OneRecovery.efi

# Or use your PC's boot menu (often F12, F10, or Esc at startup)
```

## Build your own 

You can build your own version of OneRecovery.  
It's based on Alpine Linux and vanilla kernel.  

### Build Process
The build process follows a sequential flow through numbered scripts:

1. `01_get.sh`: Downloads and extracts Alpine Linux, Linux kernel, and ZFS sources
2. `02_chrootandinstall.sh`: Sets up the chroot environment and installs packages
3. `03_conf.sh`: Configures system services, network, auto-login, and kernel settings
4. `04_build.sh`: Builds the kernel, modules, ZFS support, and packages everything into the EFI file
5. `99_cleanup.sh`: Removes build artifacts when finished

### Steps
1. Clone repository:  
   `git clone https://github.com/D4rk4/OneRecovery`

2. Run build scripts sequentially:  
   ```
   cd FoxBuild
   ./01_get.sh
   ./02_chrootandinstall.sh
   ./03_conf.sh
   ./04_build.sh
   ```
   
3. The final file will be created as `OneRecovery.efi` in the root directory
