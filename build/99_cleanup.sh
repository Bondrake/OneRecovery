#!/bin/bash
#
# OneRecovery cleanup script
# Removes build artifacts and temporary files
#

# Define script name for error handling
SCRIPT_NAME=$(basename "$0")

# Source common error handling
if [ -f "./error_handling.sh" ]; then
    source ./error_handling.sh
    
    # Initialize error handling
    init_error_handling
else
    # Minimal error handling if the file is not available
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    NC='\033[0m' # No Color
    
    log() {
        local level=$1
        local message=$2
        case "$level" in
            "INFO") echo -e "${BLUE}[INFO]${NC} $message" ;;
            "WARNING") echo -e "${YELLOW}[WARNING]${NC} $message" ;;
            "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
            "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
            *) echo -e "$message" ;;
        esac
    }
    
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
fi

# Print banner
print_banner

# Confirm cleanup with the user
if [ "${FORCE_CLEANUP:-false}" != "true" ]; then
    read -p "This will remove all build artifacts. Are you sure? [y/N] " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Cleanup cancelled by user"
        exit 0
    fi
fi

log "INFO" "Cleaning up build artifacts..."

# Clean up Alpine minirootfs
if [ -d "alpine-minirootfs" ] || [ -f "alpine-minirootfs*.tar.gz" ]; then
    log "INFO" "Removing Alpine minirootfs..."
    rm -rf alpine-minirootfs*
fi

# Clean up Linux kernel source
if [ -d "linux" ] || [ -d "linux-*" ] || [ -f "linux-*.tar.xz" ]; then
    log "INFO" "Removing Linux kernel source..."
    rm -rf linux*
fi

# Clean up ZFS source
if [ -d "zfs" ] || [ -d "zfs-*" ] || [ -f "zfs-*.tar.gz" ]; then
    log "INFO" "Removing ZFS source..."
    rm -rf zfs*
fi

# Clean up OneRecovery output
if [ -f "OneRecovery.efi" ]; then
    log "INFO" "Removing OneRecovery.efi..."
    rm -f OneRecovery.efi
fi

# Clean up build artifacts
if [ -f ".build_progress" ]; then
    log "INFO" "Removing build progress file..."
    rm -f .build_progress
fi

# Clean up extraction markers
log "INFO" "Removing extraction markers..."
find . -name ".extraction_complete" -type f -delete

# Clean up temporary files
log "INFO" "Removing temporary files..."
rm -f *.tmp
rm -f build_error.log

log "SUCCESS" "Cleanup completed successfully"