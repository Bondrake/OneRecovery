#!/bin/bash
#
# Common error handling framework for OneRecovery build scripts
# Source this file in each build script
#

# Color codes for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file for build errors
BUILD_LOG="build_error.log"

# Function to print with timestamp
log() {
    local level=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    case "$level" in
        "INFO")
            echo -e "${BLUE}[INFO]${NC} $message"
            ;;
        "WARNING")
            echo -e "${YELLOW}[WARNING]${NC} $message"
            ;;
        "ERROR")
            echo -e "${RED}[ERROR]${NC} $message"
            # Write to log file with error handling
            if ! echo "[$timestamp] [ERROR] $message" >> "$BUILD_LOG" 2>/dev/null; then
                echo -e "${YELLOW}[WARNING]${NC} Could not write to log file. Continuing without logging."
            fi
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        *)
            echo -e "$message"
            ;;
    esac
}

# Function to handle errors in standard environments
handle_error() {
    local err_code=$?
    local line_num=$1
    local command="$2"
    
    if [ $err_code -ne 0 ]; then
        # List of non-critical errors that we can ignore in containerized environments
        local ignore_patterns=(
            "chmod.*permission denied"
            "mkdir.*permission denied"
            "chmod:.*Operation not permitted"
            "mkdir:.*Operation not permitted"
            "ln -fs.*permission denied"
            "chmod 777"
            "mkdir -p ./alpine-minirootfs"
            "write.*build_error.log: Permission denied"
        )
        
        # Check if command matches any ignore patterns and we're in a container
        local should_ignore=false
        if [ "${IN_DOCKER_CONTAINER:-}" = "true" ] || [ "${GITHUB_ACTIONS:-}" = "true" ] || grep -q "docker\|container" /proc/1/cgroup 2>/dev/null || [ -f "/.dockerenv" ]; then
            for pattern in "${ignore_patterns[@]}"; do
                if echo "$command" | grep -i -q "$pattern"; then
                    should_ignore=true
                    break
                fi
            done
        fi
        
        # For non-critical errors in containers, warn but continue
        if [ "$should_ignore" = true ]; then
            log "WARNING" "Non-critical command failed at line $line_num: $command"
            log "INFO" "Continuing build process despite this error"
            return 0
        fi
        
        # For critical errors, follow normal error handling
        log "ERROR" "Command failed with exit code $err_code at line $line_num: $command"
        log "ERROR" "Check $BUILD_LOG for details"
        
        # Attempt to provide helpful debug information
        case "$command" in
            *wget*)
                log "ERROR" "Network error or invalid URL. Check your internet connection."
                ;;
            *tar*)
                log "ERROR" "Archive extraction failed. The downloaded file may be corrupted."
                log "ERROR" "Try removing the file and running the script again."
                ;;
            *chroot*)
                log "ERROR" "Chroot failed. This may be due to permission issues or missing binaries."
                log "ERROR" "Make sure you are running as root/sudo."
                ;;
            *make*)
                log "ERROR" "Build failed. Check if all dependencies are installed."
                log "ERROR" "Run 00_prepare.sh again to ensure all required packages are installed."
                ;;
            *)
                log "ERROR" "Command failed. See error message above for details."
                ;;
        esac
        
        # Offer recovery options
        echo ""
        log "INFO" "To recover:"
        case "$SCRIPT_NAME" in
            "01_get.sh")
                log "INFO" "- Ensure your internet connection is working"
                log "INFO" "- Remove any partial downloaded files"
                log "INFO" "- Run ./01_get.sh again"
                ;;
            "02_chrootandinstall.sh")
                log "INFO" "- Ensure you have root/sudo privileges"
                log "INFO" "- Make sure alpine-minirootfs was extracted correctly"
                log "INFO" "- Run ./02_chrootandinstall.sh again"
                ;;
            "03_conf.sh")
                log "INFO" "- Check if the files in zfiles/ directory exist"
                log "INFO" "- Make sure alpine-minirootfs was configured correctly"
                log "INFO" "- Run ./03_conf.sh again"
                ;;
            "04_build.sh")
                log "INFO" "- Make sure all build dependencies are installed with ./00_prepare.sh"
                log "INFO" "- Check if kernel source was extracted correctly"
                log "INFO" "- For kernel build errors, see output above for specific errors"
                log "INFO" "- You can try running './04_build.sh' again"
                ;;
            *)
                log "INFO" "- Check the error message above"
                log "INFO" "- Fix the issue and try again"
                ;;
        esac
        
        exit $err_code
    fi
}

# Set up error trapping
trap_errors() {
    # In all environments, we use the same error handler with built-in container detection
    log "INFO" "Setting up error handling"
    
    # Still use set -e, but our error handler will decide whether to continue
    # based on the error type and environment
    set -e
    trap 'handle_error ${LINENO} "${BASH_COMMAND}"' ERR
}

# Check if prerequisites are met for this specific script
check_prerequisites() {
    case "$SCRIPT_NAME" in
        "01_get.sh")
            # Check for wget
            if ! command -v wget &> /dev/null; then
                log "ERROR" "wget not found. Install wget and try again."
                log "INFO" "Run ./00_prepare.sh to install required dependencies."
                exit 1
            fi
            ;;
        "02_chrootandinstall.sh")
            # Check for chroot capability
            if [ "$EUID" -ne 0 ]; then
                log "ERROR" "This script requires root/sudo privileges for chroot."
                log "INFO" "Run with sudo: sudo ./02_chrootandinstall.sh"
                exit 1
            fi
            
            # Check if minirootfs exists
            if [ ! -d "alpine-minirootfs" ]; then
                log "ERROR" "alpine-minirootfs directory not found."
                log "INFO" "Run ./01_get.sh first to download Alpine Linux."
                exit 1
            fi
            ;;
        "03_conf.sh")
            # Check if minirootfs exists
            if [ ! -d "alpine-minirootfs" ]; then
                log "ERROR" "alpine-minirootfs directory not found."
                log "INFO" "Run ./01_get.sh and ./02_chrootandinstall.sh first."
                exit 1
            fi
            
            # Check if zfiles exists
            if [ ! -d "zfiles" ]; then
                log "ERROR" "zfiles directory not found."
                exit 1
            fi
            ;;
        "04_build.sh")
            # Check if kernel source exists
            if [ ! -d "linux" ]; then
                log "ERROR" "linux directory not found."
                log "INFO" "Run ./01_get.sh first to download Linux kernel."
                exit 1
            fi
            
            # Check for build tools
            if ! command -v make &> /dev/null; then
                log "ERROR" "make not found. Install build tools and try again."
                log "INFO" "Run ./00_prepare.sh to install required dependencies."
                exit 1
            fi
            ;;
    esac
}

# Print OneRecovery banner
print_banner() {
    echo -e "${BLUE}"
    echo "      ____________  "
    echo "    /|------------| "
    echo "   /_|  .---.     | "
    echo "  |    /     \    | "
    echo "  |    \.6-6./    | "
    echo "  |    /\`\_/\`\    | "
    echo "  |   //  _  \\\   | "
    echo "  |  | \     / |  | "
    echo "  | /\`\_\`>  <_/\`\ | "
    echo "  | \__/'---'\__/ | "
    echo "  |_______________| "
    echo "                    "
    echo -e "${GREEN}   OneRecovery: $SCRIPT_NAME  ${NC}"
    echo "----------------------------------------------------"
}

# Function to print script start
print_script_start() {
    print_banner
}

# Function to print script end
print_script_end() {
    echo "----------------------------------------------------"
    log "SUCCESS" "$SCRIPT_NAME completed successfully"
    echo "----------------------------------------------------"
}

# Function to check if the script can resume from a checkpoint
check_resume_point() {
    if [ -n "$1" ] && [ "$1" = "--resume" ]; then
        log "INFO" "Resuming from last successful checkpoint"
        RESUME_MODE=true
    else
        RESUME_MODE=false
    fi
}

# Generate a secure random password
generate_random_password() {
    local length=${1:-12}
    local chars="A-Za-z0-9_!@#$%^&*()"
    
    # Method 1: Using /dev/urandom (Linux, macOS)
    if [ -r "/dev/urandom" ]; then
        local password=$(tr -dc "$chars" < /dev/urandom | head -c "$length")
        echo "$password"
    # Method 2: Using OpenSSL (fallback)
    elif command -v openssl &> /dev/null; then
        local password=$(openssl rand -base64 $((length * 2)) | tr -dc "$chars" | head -c "$length")
        echo "$password"
    # Method 3: Using built-in $RANDOM (last resort)
    else
        local password=""
        local charcount=${#chars}
        for i in $(seq 1 "$length"); do
            local rand=$((RANDOM % charcount))
            password="${password}${chars:$rand:1}"
        done
        echo "$password"
    fi
}

# Generate a password hash for /etc/shadow
create_password_hash() {
    local password="$1"
    
    # Method 1: Using OpenSSL (Linux, macOS)
    if command -v openssl &> /dev/null; then
        local hash=$(openssl passwd -6 "$password")
        echo "$hash"
    # Method 2: Using mkpasswd (many Linux distros)
    elif command -v mkpasswd &> /dev/null; then
        local hash=$(mkpasswd -m sha-512 "$password")
        echo "$hash"
    # Method 3: Failed to hash
    else
        log "ERROR" "No password hashing tool available (openssl or mkpasswd required)"
        echo "ERROR"
    fi
}

# Initialize error handling framework
init_error_handling() {
    # Try to create the log file with proper permissions
    if ! touch "$BUILD_LOG" 2>/dev/null; then
        echo -e "${YELLOW}[WARNING]${NC} Cannot create log file. Will continue without logging."
        BUILD_LOG="/dev/null"
    else
        # Make sure the log file is writable
        chmod 666 "$BUILD_LOG" 2>/dev/null || true
        echo "" > "$BUILD_LOG" 2>/dev/null || true
    fi
    
    trap_errors
    check_prerequisites
    print_script_start
}