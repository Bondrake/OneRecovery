#!/bin/bash
# Kernel configuration minimizer script
# Takes an existing kernel config and minimizes it for size and performance

# Set up colored output
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[0;33m"
BLUE="\033[0;34m"
RESET="\033[0m"

# Simple logging function
log() {
    local level="$1"
    shift
    local message="$*"
    
    case "$level" in
        "INFO") echo -e "${BLUE}[INFO]${RESET} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${RESET} $message" ;;
        "WARNING") echo -e "${YELLOW}[WARNING]${RESET} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${RESET} $message" ;;
        *) echo -e "$message" ;;
    esac
}

# Apply a config option
apply_config_option() {
    local config_file="$1"
    local option="$2"
    local value="$3"
    
    # Remove existing option if present
    if grep -q "^$option=" "$config_file" || grep -q "^# $option is not set" "$config_file"; then
        sed -i "/^$option=/d" "$config_file"
        sed -i "/^# $option is not set/d" "$config_file"
    fi
    
    # Apply new value
    if [ "$value" = "n" ]; then
        echo "# $option is not set" >> "$config_file"
    else
        echo "$option=$value" >> "$config_file"
    fi
}

# Minimize kernel configuration
minimize_kernel_config() {
    local config_file="$1"
    
    if [ ! -f "$config_file" ]; then
        log "ERROR" "Kernel config file not found: $config_file"
        return 1
    fi
    
    log "INFO" "Minimizing kernel configuration: $config_file"
    
    # Create a backup
    cp "$config_file" "${config_file}.backup"
    log "INFO" "Created backup: ${config_file}.backup"
    
    # Options to minimize for a recovery environment
    local minimization_count=0
    
    # Disable IPv6 (not needed for most recovery operations)
    apply_config_option "$config_file" "CONFIG_IPV6" "n"
    ((minimization_count++))
    
    # Disable unused network protocols
    apply_config_option "$config_file" "CONFIG_INET_XFRM_MODE_TRANSPORT" "n"
    apply_config_option "$config_file" "CONFIG_INET_XFRM_MODE_TUNNEL" "n"
    apply_config_option "$config_file" "CONFIG_INET_XFRM_MODE_BEET" "n"
    apply_config_option "$config_file" "CONFIG_INET_LRO" "n"
    apply_config_option "$config_file" "CONFIG_INET_DIAG" "n"
    ((minimization_count+=5))
    
    # Disable unused filesystems
    apply_config_option "$config_file" "CONFIG_JFS_FS" "n"  
    apply_config_option "$config_file" "CONFIG_REISERFS_FS" "n"
    apply_config_option "$config_file" "CONFIG_GFS2_FS" "n"
    apply_config_option "$config_file" "CONFIG_OCFS2_FS" "n"
    apply_config_option "$config_file" "CONFIG_NTFS_FS" "n"  # Use NTFS3 instead if needed
    apply_config_option "$config_file" "CONFIG_UBIFS_FS" "n"
    apply_config_option "$config_file" "CONFIG_JFFS2_FS" "n"
    apply_config_option "$config_file" "CONFIG_CRAMFS" "n"
    apply_config_option "$config_file" "CONFIG_MINIX_FS" "n"
    ((minimization_count+=9))
    
    # Disable unnecessary input support
    apply_config_option "$config_file" "CONFIG_INPUT_JOYSTICK" "n"
    apply_config_option "$config_file" "CONFIG_INPUT_TABLET" "n"
    apply_config_option "$config_file" "CONFIG_INPUT_TOUCHSCREEN" "n"
    apply_config_option "$config_file" "CONFIG_INPUT_MISC" "n"
    ((minimization_count+=4))
    
    # Disable graphics drivers (minimal EFI framebuffer is enough)
    apply_config_option "$config_file" "CONFIG_DRM" "n"
    apply_config_option "$config_file" "CONFIG_DRM_AMDGPU" "n"
    apply_config_option "$config_file" "CONFIG_DRM_RADEON" "n"
    apply_config_option "$config_file" "CONFIG_DRM_NOUVEAU" "n"
    apply_config_option "$config_file" "CONFIG_DRM_I915" "n"
    ((minimization_count+=5))
    
    # Enable basic graphics
    apply_config_option "$config_file" "CONFIG_FB" "y"
    apply_config_option "$config_file" "CONFIG_FB_EFI" "y"
    apply_config_option "$config_file" "CONFIG_FB_VESA" "y"
    apply_config_option "$config_file" "CONFIG_VGA_CONSOLE" "y"
    apply_config_option "$config_file" "CONFIG_FRAMEBUFFER_CONSOLE" "y"
    
    # Disable sound
    apply_config_option "$config_file" "CONFIG_SOUND" "n"
    apply_config_option "$config_file" "CONFIG_SND" "n"
    ((minimization_count+=2))
    
    # Disable wireless networking 
    apply_config_option "$config_file" "CONFIG_WLAN" "n"
    apply_config_option "$config_file" "CONFIG_WIRELESS" "n"
    ((minimization_count+=2))
    
    # Disable virtualization
    apply_config_option "$config_file" "CONFIG_KVM" "n"
    apply_config_option "$config_file" "CONFIG_VHOST" "n"
    apply_config_option "$config_file" "CONFIG_HYPERVISOR_GUEST" "n"
    apply_config_option "$config_file" "CONFIG_PARAVIRT" "n"
    ((minimization_count+=4))
    
    # Disable debugging
    apply_config_option "$config_file" "CONFIG_DEBUG_KERNEL" "n"
    apply_config_option "$config_file" "CONFIG_DEBUG_INFO" "n"
    apply_config_option "$config_file" "CONFIG_KGDB" "n"
    apply_config_option "$config_file" "CONFIG_MAGIC_SYSRQ" "n"
    apply_config_option "$config_file" "CONFIG_DEBUG_FS" "n"
    apply_config_option "$config_file" "CONFIG_SLUB_DEBUG" "n"
    apply_config_option "$config_file" "CONFIG_PM_DEBUG" "n"
    apply_config_option "$config_file" "CONFIG_PM_ADVANCED_DEBUG" "n"
    apply_config_option "$config_file" "CONFIG_PM_TEST_SUSPEND" "n"
    apply_config_option "$config_file" "CONFIG_CRC_T10DIF" "n"
    apply_config_option "$config_file" "CONFIG_DEBUG_MEMORY_INIT" "n"
    apply_config_option "$config_file" "CONFIG_DETECT_HUNG_TASK" "n"
    apply_config_option "$config_file" "CONFIG_TIMER_STATS" "n"
    ((minimization_count+=13))
    
    # Optimize for size
    apply_config_option "$config_file" "CONFIG_CC_OPTIMIZE_FOR_SIZE" "y"
    apply_config_option "$config_file" "CONFIG_KERNEL_XZ" "y"
    apply_config_option "$config_file" "CONFIG_KERNEL_GZIP" "n"
    apply_config_option "$config_file" "CONFIG_MODULE_COMPRESS" "y"
    apply_config_option "$config_file" "CONFIG_MODULE_COMPRESS_XZ" "y"
    
    # Add kernel config tag
    echo "# OneFileLinux Minimal Kernel Configuration" > "${config_file}.tmp"
    echo "# Generated from Alpine Linux LTS kernel config" >> "${config_file}.tmp"
    echo "# Size-optimized for recovery environment" >> "${config_file}.tmp"
    echo "# $(date)" >> "${config_file}.tmp"
    cat "$config_file" >> "${config_file}.tmp"
    mv "${config_file}.tmp" "$config_file"
    
    log "SUCCESS" "Minimized kernel configuration with $minimization_count options changed"
    return 0
}

# Usage demonstration
if [[ "$0" == "${BASH_SOURCE[0]}" ]]; then
    # Script was executed directly, not sourced
    
    # Check for required arguments
    if [ $# -lt 1 ]; then
        echo "Usage: $0 <kernel_config_file>"
        echo "Example: $0 kernel.config"
        exit 1
    fi
    
    # Run the function with provided arguments
    minimize_kernel_config "$1"
    exit $?
fi