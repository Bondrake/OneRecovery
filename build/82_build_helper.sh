#!/bin/bash
#
# OneRecovery Build Helper (82_build_helper.sh)
# Cross-environment build utilities for consistent builds in any environment
# Provides file operations, environment detection, and build utilities
# This is part of the library scripts (80-89 range)
#

# Detect environment types
is_github_actions() {
    [ -n "${GITHUB_ACTIONS:-}" ]
}

is_docker_container() {
    [ -n "${IN_DOCKER_CONTAINER:-}" ] || grep -q "docker\|container" /proc/1/cgroup 2>/dev/null || [ -f "/.dockerenv" ]
}

is_restricted_environment() {
    is_github_actions || is_docker_container
}

# Print environment information
print_environment_info() {
    echo "OneRecovery Build Environment:"
    echo "------------------------------"
    
    if is_github_actions; then
        echo "GitHub Actions: YES"
        echo "Runner OS: ${RUNNER_OS:-Unknown}"
        echo "GitHub Repository: ${GITHUB_REPOSITORY:-Unknown}"
    else
        echo "GitHub Actions: NO"
    fi
    
    if is_docker_container; then
        echo "Docker Container: YES"
    else
        echo "Docker Container: NO"
    fi
    
    echo "Running as user: $(id -un) ($(id -u))"
    echo "System: $(uname -s) $(uname -m)"
    echo "CPU Cores: $(nproc 2>/dev/null || echo "Unknown")"
    echo "------------------------------"
}

# Fix permissions for scripts in a directory
fix_script_permissions() {
    local dir=$1
    
    if [ -d "$dir" ]; then
        echo "Fixing script permissions in $dir"
        find "$dir" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
        
        if [ -d "$dir/scripts" ]; then
            chmod -R +x "$dir/scripts" 2>/dev/null || true
        fi
        
        # Make common build scripts executable
        for script in configure autogen.sh bootstrap.sh; do
            if [ -f "$dir/$script" ]; then
                chmod +x "$dir/$script" 2>/dev/null || true
            fi
        done
    fi
}

# Create necessary directories with proper permissions
ensure_directory() {
    local dir=$1
    local mode=${2:-755}
    
    if [ ! -d "$dir" ]; then
        echo "Creating directory: $dir"
        if is_restricted_environment; then
            mkdir -p "$dir" 2>/dev/null || sudo mkdir -p "$dir"
            chmod "$mode" "$dir" 2>/dev/null || sudo chmod "$mode" "$dir"
        else
            mkdir -p "$dir"
            chmod "$mode" "$dir"
        fi
    fi
}

# Extract archive with environment awareness
extract_archive() {
    local archive=$1
    local target=$2
    local strip_components=${3:-0}
    
    if [ ! -f "$archive" ]; then
        echo "Error: Archive not found: $archive"
        return 1
    fi
    
    ensure_directory "$target"
    
    echo "Extracting $archive to $target"
    
    if is_restricted_environment; then
        # Use appropriate extraction method based on file type
        case "$archive" in
            *.tar.gz|*.tgz)
                if [ $strip_components -gt 0 ]; then
                    sudo tar -xzf "$archive" -C "$target" --strip-components=$strip_components
                else
                    sudo tar -xzf "$archive" -C "$target"
                fi
                sudo chown -R $(id -u):$(id -g) "$target"
                ;;
            *.tar.xz)
                if [ $strip_components -gt 0 ]; then
                    sudo tar -xf "$archive" -C "$target" --strip-components=$strip_components
                else
                    sudo tar -xf "$archive" -C "$target"
                fi
                sudo chown -R $(id -u):$(id -g) "$target"
                ;;
            *.zip)
                unzip -o "$archive" -d "$target"
                ;;
            *)
                echo "Unsupported archive format: $archive"
                return 1
                ;;
        esac
    else
        # Standard environment
        case "$archive" in
            *.tar.gz|*.tgz)
                if [ $strip_components -gt 0 ]; then
                    tar -xzf "$archive" -C "$target" --strip-components=$strip_components
                else
                    tar -xzf "$archive" -C "$target"
                fi
                ;;
            *.tar.xz)
                if [ $strip_components -gt 0 ]; then
                    tar -xf "$archive" -C "$target" --strip-components=$strip_components
                else
                    tar -xf "$archive" -C "$target"
                fi
                ;;
            *.zip)
                unzip -o "$archive" -d "$target"
                ;;
            *)
                echo "Unsupported archive format: $archive"
                return 1
                ;;
        esac
    fi
    
    return $?
}

# Copy files with environment awareness
safe_copy() {
    local src=$1
    local dest=$2
    local mode=${3:-644}
    
    if [ ! -f "$src" ]; then
        echo "Warning: Source file not found: $src"
        return 1
    fi
    
    echo "Copying $src to $dest"
    
    if is_restricted_environment; then
        # Create the destination directory if needed
        local dest_dir=$(dirname "$dest")
        ensure_directory "$dest_dir"
        
        # Copy and set permissions
        sudo cp "$src" "$dest"
        sudo chmod "$mode" "$dest"
    else
        # Create the destination directory if needed
        local dest_dir=$(dirname "$dest")
        ensure_directory "$dest_dir"
        
        # Copy and set permissions
        cp "$src" "$dest"
        chmod "$mode" "$dest"
    fi
    
    return $?
}

# Create symlinks with environment awareness
safe_symlink() {
    local target=$1
    local link_name=$2
    
    echo "Creating symlink: $link_name -> $target"
    
    if is_restricted_environment; then
        # Create the destination directory if needed
        local link_dir=$(dirname "$link_name")
        ensure_directory "$link_dir"
        
        # Create the symlink
        sudo ln -sf "$target" "$link_name" 2>/dev/null || ln -sf "$target" "$link_name"
    else
        # Create the destination directory if needed
        local link_dir=$(dirname "$link_name")
        ensure_directory "$link_dir"
        
        # Create the symlink
        ln -sf "$target" "$link_name"
    fi
    
    return $?
}

# Configure Alpine Linux with proper error handling
configure_alpine() {
    local rootfs_dir=$1
    local zfiles_dir=$2
    
    if [ ! -d "$rootfs_dir" ]; then
        echo "Error: Alpine root directory not found: $rootfs_dir"
        return 1
    fi
    
    # Create runlevel directories with proper permissions
    ensure_directory "$rootfs_dir/etc/runlevels/sysinit" "777"
    
    # Create service symlinks
    for service in mdev devfs dmesg syslog hwdrivers networking; do
        safe_symlink "/etc/init.d/$service" "$rootfs_dir/etc/runlevels/sysinit/$service"
    done
    
    # Set up terminal access
    safe_symlink "/sbin/agetty" "$rootfs_dir/sbin/getty"
    
    # Copy configuration files if zfiles directory exists
    if [ -d "$zfiles_dir" ]; then
        # Create network directory
        ensure_directory "$rootfs_dir/etc/network"
        
        # Copy files if they exist
        if [ -f "$zfiles_dir/interfaces" ]; then
            safe_copy "$zfiles_dir/interfaces" "$rootfs_dir/etc/network/interfaces"
        else
            echo "Creating default interfaces file"
            echo "auto lo" > "/tmp/interfaces.tmp"
            echo "iface lo inet loopback" >> "/tmp/interfaces.tmp"
            safe_copy "/tmp/interfaces.tmp" "$rootfs_dir/etc/network/interfaces"
            rm "/tmp/interfaces.tmp"
        fi
        
        if [ -f "$zfiles_dir/resolv.conf" ]; then
            safe_copy "$zfiles_dir/resolv.conf" "$rootfs_dir/etc/resolv.conf"
        else
            echo "Creating default resolv.conf"
            echo "nameserver 8.8.8.8" > "/tmp/resolv.conf.tmp"
            safe_copy "/tmp/resolv.conf.tmp" "$rootfs_dir/etc/resolv.conf"
            rm "/tmp/resolv.conf.tmp"
        fi
        
        if [ -f "$zfiles_dir/profile" ]; then
            safe_copy "$zfiles_dir/profile" "$rootfs_dir/etc/profile"
        fi
        
        if [ -f "$zfiles_dir/shadow" ]; then
            safe_copy "$zfiles_dir/shadow" "$rootfs_dir/etc/shadow"
        fi
        
        if [ -f "$zfiles_dir/init" ]; then
            safe_copy "$zfiles_dir/init" "$rootfs_dir/init" "755"
        fi
        
        if [ -f "$zfiles_dir/onerecovery-tui" ]; then
            safe_copy "$zfiles_dir/onerecovery-tui" "$rootfs_dir/onerecovery-tui" "755"
        fi
    else
        echo "Warning: zfiles directory not found: $zfiles_dir"
    fi
    
    # Configure console settings if inittab exists
    if [ -f "$rootfs_dir/etc/inittab" ]; then
        if is_restricted_environment; then
            sudo sed -i 's/^#ttyS0/ttyS0/' "$rootfs_dir/etc/inittab"
            sudo sed -i 's|\(/sbin/getty \)|\1 -a root |' "$rootfs_dir/etc/inittab"
        else
            sed -i 's/^#ttyS0/ttyS0/' "$rootfs_dir/etc/inittab"
            sed -i 's|\(/sbin/getty \)|\1 -a root |' "$rootfs_dir/etc/inittab"
        fi
    fi
    
    return 0
}

# Setup kernel configuration
setup_kernel_config() {
    local kernel_dir=$1
    local config_type=$2
    local zfiles_dir=$3
    
    if [ ! -d "$kernel_dir" ]; then
        echo "Error: Kernel directory not found: $kernel_dir"
        return 1
    fi
    
    # Fix script permissions
    fix_script_permissions "$kernel_dir"
    
    # Check for existing config
    if [ ! -f "$kernel_dir/.config" ]; then
        echo "Kernel config not found, creating one"
        
        if [ "$config_type" = "minimal" ] && [ -f "$zfiles_dir/kernel-minimal.config" ]; then
            echo "Copying minimal kernel config from zfiles"
            safe_copy "$zfiles_dir/kernel-minimal.config" "$kernel_dir/.config"
        elif [ -f "$zfiles_dir/.config" ]; then
            echo "Copying standard kernel config from zfiles"
            safe_copy "$zfiles_dir/.config" "$kernel_dir/.config"
        else
            echo "No config found in zfiles, creating default config"
            # Create a minimal kernel config
            cat > "/tmp/minimal.config" << EOF
# Minimal kernel configuration
CONFIG_64BIT=y
CONFIG_X86_64=y
CONFIG_SMP=y
CONFIG_MODULES=y
CONFIG_MODULE_UNLOAD=y
CONFIG_EFI=y
CONFIG_EFI_STUB=y
CONFIG_BLK_DEV_INITRD=y
CONFIG_BINFMT_ELF=y
CONFIG_FS_POSIX_ACL=y
CONFIG_TMPFS=y
CONFIG_TMPFS_POSIX_ACL=y
CONFIG_PROC_FS=y
CONFIG_SYSFS=y
CONFIG_DEVTMPFS=y
CONFIG_UNIX=y
CONFIG_NET=y
CONFIG_INET=y
CONFIG_BLK_DEV=y
CONFIG_BLK_DEV_SD=y
CONFIG_ATA=y
CONFIG_SATA_AHCI=y
CONFIG_USB_SUPPORT=y
CONFIG_USB=y
CONFIG_USB_EHCI_HCD=y
CONFIG_USB_XHCI_HCD=y
CONFIG_USB_STORAGE=y
CONFIG_EXT4_FS=y
CONFIG_CRYPTO=y
EOF
            safe_copy "/tmp/minimal.config" "$kernel_dir/.config"
            rm "/tmp/minimal.config"
        fi
        
        # Run olddefconfig to ensure the config is valid
        if is_restricted_environment; then
            (cd "$kernel_dir" && make olddefconfig)
        else
            (cd "$kernel_dir" && make olddefconfig)
        fi
    fi
    
    return 0
}

# Setup and configure ZFS build environment
setup_zfs() {
    local zfs_dir=$1
    local kernel_dir=$2
    
    if [ ! -d "$zfs_dir" ]; then
        echo "Error: ZFS directory not found: $zfs_dir"
        return 1
    fi
    
    # Fix script permissions
    fix_script_permissions "$zfs_dir"
    
    # Ensure autogen.sh and configure are executable
    if [ -f "$zfs_dir/autogen.sh" ]; then
        chmod +x "$zfs_dir/autogen.sh"
    fi
    
    if [ -f "$zfs_dir/configure" ]; then
        chmod +x "$zfs_dir/configure"
    fi
    
    # Run autogen.sh if configure doesn't exist
    if [ ! -f "$zfs_dir/configure" ]; then
        echo "Running autogen.sh to generate configure script"
        (cd "$zfs_dir" && ./autogen.sh)
    fi
    
    return 0
}

# Determine optimal number of build threads
get_optimal_threads() {
    local available_memory_kb=0
    local total_cores=0
    
    # Detect available memory
    if [ -f "/proc/meminfo" ]; then
        available_memory_kb=$(grep MemAvailable /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
    fi
    
    # If memory detection failed, try total memory with a reduction factor
    if [ "$available_memory_kb" -eq 0 ] && [ -f "/proc/meminfo" ]; then
        local total_memory_kb=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}' || echo 0)
        available_memory_kb=$((total_memory_kb * 7 / 10)) # Use 70% of total memory
    fi
    
    # Detect total cores
    total_cores=$(nproc 2>/dev/null || echo 2)
    
    # Calculate a safe number of threads based on available memory
    # Empirically, each compilation thread needs ~2GB for kernel compilation
    if [ "$available_memory_kb" -gt 0 ]; then
        local safe_threads=$(awk "BEGIN {print int($available_memory_kb/1024/1024/2)}")
        
        # Ensure at least 1 thread and no more than total cores
        safe_threads=$(( safe_threads < 1 ? 1 : safe_threads ))
        safe_threads=$(( safe_threads > total_cores ? total_cores : safe_threads ))
        
        echo "$safe_threads"
    else
        # Default to 2 threads if memory detection failed
        echo "2"
    fi
}

# Print a section header
print_section() {
    local title=$1
    echo "===================================================================="
    echo "  $title"
    echo "===================================================================="
}

# Use print_banner from 80_common.sh instead of duplicating it here

# Docker-specific extraction handling function
docker_handle_extraction() {
    local src_file="$1"
    local dest_dir="$2"
    
    log "INFO" "Special handling for extraction of $src_file to $dest_dir"
    
    # Create temporary extraction directory
    local temp_extract_dir="/tmp/onerecovery_extract_temp"
    mkdir -p "$temp_extract_dir"
    chmod 777 "$temp_extract_dir" 2>/dev/null || true
    
    # Create destination directory first
    mkdir -p "$dest_dir"
    
    # Extract as root first to a temp location
    if [[ "$src_file" == *.tar.gz ]]; then
        tar -xzf "$src_file" -C "$temp_extract_dir"
    elif [[ "$src_file" == *.tar.xz ]]; then
        # For .tar.xz files, must decompress and extract separately
        xz -dc "$src_file" | tar -x -C "$temp_extract_dir"
    fi
    
    # Check if extraction succeeded
    if [ $? -ne 0 ] || [ -z "$(ls -A "$temp_extract_dir")" ]; then
        log "WARNING" "Initial extraction failed, trying alternative method"
        # Try using tar with xf directly
        if [[ "$src_file" == *.tar.xz ]]; then
            tar -xf "$src_file" -C "$temp_extract_dir" --no-same-owner
        fi
    fi
    
    # Check again if extraction succeeded
    if [ -z "$(ls -A "$temp_extract_dir")" ]; then
        log "ERROR" "All extraction methods failed for $src_file"
        return 1
    fi
    
    # Copy files to final location with correct permissions
    cp -a "$temp_extract_dir"/* "$dest_dir"/ || true
    
    # Clean up
    rm -rf "$temp_extract_dir"/*
    
    # Set permissions if possible
    chmod -R 755 "$dest_dir" 2>/dev/null || true
    
    # Verify final directory has content
    if [ -z "$(ls -A "$dest_dir")" ]; then
        log "ERROR" "Failed to extract content to $dest_dir"
        return 1
    fi
    
    log "SUCCESS" "Extraction completed successfully to $dest_dir"
    return 0
}

# Docker-specific Alpine minirootfs preparation
prepare_alpine_minirootfs() {
    local rootfs_dir=${1:-"alpine-minirootfs"}
    
    if [ ! -d "$rootfs_dir" ]; then
        log "WARNING" "Alpine minirootfs directory not found: $rootfs_dir"
        return 1
    fi
    
    log "INFO" "Preparing Alpine minirootfs for Docker environment"
    
    # Ensure permissions allow writing to all subdirectories
    find "$rootfs_dir" -type d -exec chmod 755 {} \; 2>/dev/null || true
    
    # Make sure root-owned directories are writable by all users
    # This is necessary for the build scripts to create symlinks
    mkdir -p "$rootfs_dir/etc/runlevels/sysinit"
    chmod -R 777 "$rootfs_dir/etc/runlevels" 2>/dev/null || true
    
    log "SUCCESS" "Set proper permissions on Alpine minirootfs"
    return 0
}

# Cross-environment chroot helpers
# -------------------------------------

# Prepares a chroot environment with proper mount handling based on environment
prepare_chroot() {
    local chroot_dir="$1"
    local mount_special=${2:-true}
    
    # Make sure the directory exists
    if [ ! -d "$chroot_dir" ]; then
        log "ERROR" "Chroot directory not found: $chroot_dir"
        return 1
    fi
    
    log "INFO" "Preparing chroot environment: $chroot_dir"
    
    # Create essential directories
    mkdir -p "$chroot_dir/proc" "$chroot_dir/sys" "$chroot_dir/dev" "$chroot_dir/dev/pts" 2>/dev/null || true
    
    # Check if we're running in a Docker container
    if is_docker_container; then
        log "INFO" "Running in Docker container - using simplified chroot preparation"
        
        # In Docker, just mount proc if requested and it's not already mounted
        if [ "$mount_special" = true ] && ! mountpoint -q "$chroot_dir/proc" 2>/dev/null; then
            log "INFO" "Mounting proc filesystem"
            mount -t proc none "$chroot_dir/proc" 2>/dev/null || log "WARNING" "Could not mount proc (this is normal in Docker)"
        fi
        
        # Set safe permissions on special directories
        chmod 555 "$chroot_dir/proc" 2>/dev/null || true
        if [ -d "$chroot_dir/var/empty" ]; then
            chmod 555 "$chroot_dir/var/empty" 2>/dev/null || true
        fi
    else
        # Standard non-Docker environment
        log "INFO" "Preparing standard chroot environment"
        
        if [ "$mount_special" = true ]; then
            # Mount special filesystems if they're not already mounted
            if ! mountpoint -q "$chroot_dir/proc" 2>/dev/null; then
                mount -t proc none "$chroot_dir/proc" || log "WARNING" "Could not mount proc"
            fi
            
            if ! mountpoint -q "$chroot_dir/sys" 2>/dev/null; then
                mount -t sysfs none "$chroot_dir/sys" || log "WARNING" "Could not mount sysfs"
            fi
            
            if ! mountpoint -q "$chroot_dir/dev" 2>/dev/null; then
                mount -o bind /dev "$chroot_dir/dev" || log "WARNING" "Could not bind mount /dev"
            fi
            
            if ! mountpoint -q "$chroot_dir/dev/pts" 2>/dev/null; then
                mount -o bind /dev/pts "$chroot_dir/dev/pts" || log "WARNING" "Could not bind mount /dev/pts"
            fi
        fi
    fi
    
    # Copy resolv.conf for network connectivity
    if [ -f "/etc/resolv.conf" ]; then
        cp "/etc/resolv.conf" "$chroot_dir/etc/resolv.conf" 2>/dev/null || log "WARNING" "Could not copy resolv.conf"
    fi
    
    return 0
}

# Cleans up a chroot environment by unmounting filesystems
cleanup_chroot() {
    local chroot_dir="$1"
    
    log "INFO" "Cleaning up chroot environment: $chroot_dir"
    
    # Check if we're running in a Docker container
    if is_docker_container; then
        log "INFO" "Running in Docker container - using simplified chroot cleanup"
        
        # In Docker, just try to unmount proc
        if mountpoint -q "$chroot_dir/proc" 2>/dev/null; then
            umount "$chroot_dir/proc" 2>/dev/null || log "WARNING" "Could not unmount proc (this is normal in Docker)"
        fi
    else
        # Normal full chroot cleanup
        log "INFO" "Cleaning up standard chroot environment"
        
        # Unmount special filesystems in reverse order
        if mountpoint -q "$chroot_dir/dev/pts" 2>/dev/null; then
            umount "$chroot_dir/dev/pts" 2>/dev/null || log "WARNING" "Could not unmount dev/pts"
        fi
        
        if mountpoint -q "$chroot_dir/dev" 2>/dev/null; then
            umount "$chroot_dir/dev" 2>/dev/null || log "WARNING" "Could not unmount dev"
        fi
        
        if mountpoint -q "$chroot_dir/sys" 2>/dev/null; then
            umount "$chroot_dir/sys" 2>/dev/null || log "WARNING" "Could not unmount sys"
        fi
        
        if mountpoint -q "$chroot_dir/proc" 2>/dev/null; then
            umount "$chroot_dir/proc" 2>/dev/null || log "WARNING" "Could not unmount proc"
        fi
    fi
    
    return 0
}

# Runs a command in the chroot environment
run_in_chroot() {
    local chroot_dir="$1"
    local command="$2"
    local mount_special=${3:-true}
    
    # Prepare the chroot environment
    prepare_chroot "$chroot_dir" "$mount_special"
    
    # Run the command
    log "INFO" "Running command in chroot: $command"
    chroot "$chroot_dir" /bin/sh -c "$command"
    local exit_code=$?
    
    # Clean up the chroot environment
    cleanup_chroot "$chroot_dir"
    
    return $exit_code
}

# Get the latest Alpine Linux minor version for a major version
get_latest_alpine_version() {
    local base_version="${1:-$ALPINE_VERSION}"  # Default to global ALPINE_VERSION
    local fallback_patch="${2:-3}"              # Default patch version if check fails
    local timeout_seconds="${3:-5}"             # Default timeout of 5 seconds
    
    # Extract major.minor version
    local major_minor=$(echo "$base_version" | grep -oE '^[0-9]+\.[0-9]+')
    if [ -z "$major_minor" ]; then
        log "ERROR" "Invalid Alpine version format: $base_version"
        echo "${major_minor}.${fallback_patch}"
        return 1
    fi
    
    log "INFO" "Checking for latest Alpine $major_minor.x release..."
    
    # Create a temporary file for the version information
    local tmp_file=$(mktemp)
    
    # Try to get the latest version from the Alpine website
    if timeout "$timeout_seconds" wget -q -O "$tmp_file" "https://alpinelinux.org/downloads/" 2>/dev/null; then
        # Extract the latest version for the major.minor series
        local latest_version=$(grep -oE "alpine-minirootfs-${major_minor}\.[0-9]+-x86_64\.tar\.gz" "$tmp_file" | sort -V | tail -n1 | grep -oE "${major_minor}\.[0-9]+" || echo "")
        
        # Clean up
        rm -f "$tmp_file"
        
        if [ -n "$latest_version" ]; then
            log "SUCCESS" "Found latest Alpine version: $latest_version"
            echo "$latest_version"
            return 0
        fi
    else
        log "WARNING" "Failed to check for latest Alpine version (timeout)"
    fi
    
    # Clean up in case of failure
    rm -f "$tmp_file" 2>/dev/null || true
    
    # Fall back to default patch version
    local fallback_version="${major_minor}.${fallback_patch}"
    log "INFO" "Using fallback Alpine version: $fallback_version"
    echo "$fallback_version"
    return 0
}

# Function to get Alpine minirootfs URL
get_alpine_minirootfs_url() {
    local version="${1:-$ALPINE_VERSION}"
    local arch="${2:-x86_64}"
    
    # If version is just major.minor, try to get the latest patch version
    if [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
        version=$(get_latest_alpine_version "$version")
    fi
    
    local major_minor=$(echo "$version" | cut -d. -f1,2)
    local alpine_file="alpine-minirootfs-${version}-${arch}.tar.gz"
    local alpine_url="http://dl-cdn.alpinelinux.org/alpine/v${major_minor}/releases/${arch}/${alpine_file}"
    
    echo "$alpine_url"
}

# Export all functions
export -f is_github_actions
export -f is_docker_container
export -f is_restricted_environment
export -f print_environment_info
export -f fix_script_permissions
export -f ensure_directory
export -f extract_archive
export -f safe_copy
export -f safe_symlink
export -f configure_alpine
export -f setup_kernel_config
export -f setup_zfs
export -f get_optimal_threads
export -f print_section
# print_banner is now imported from 80_common.sh
export -f docker_handle_extraction
export -f prepare_alpine_minirootfs
export -f prepare_chroot
export -f cleanup_chroot
export -f run_in_chroot
export -f get_latest_alpine_version
export -f get_alpine_minirootfs_url