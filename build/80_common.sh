#!/bin/bash
#
# OneRecovery Common Functions (80_common.sh)
# Shared basic utilities used across all build scripts
# This is part of the library scripts (80-89 range)
#

# Color codes for better visibility
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Log file for build errors
BUILD_LOG="build_error.log"

# Function to print messages with optional timestamp and colors
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

# Print OneRecovery banner
print_banner() {
    local script_name=${1:-$SCRIPT_NAME}
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
    echo -e "${GREEN}   OneRecovery: $script_name  ${NC}"
    echo "----------------------------------------------------"
}

# Function to print section header
print_section() {
    local title=$1
    echo "===================================================================="
    echo "  $title"
    echo "===================================================================="
}

# Environment detection functions
# =========================

# Check if we're running in a container environment
is_container() {
    # First check the environment variable set by the entrypoint script
    if [ "${IN_DOCKER_CONTAINER}" = "true" ]; then
        return 0
    fi
    
    # Check if we're in GitHub Actions
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
        return 0
    fi
    
    # Fallback to traditional detection methods
    grep -q "docker\|container" /proc/1/cgroup 2>/dev/null || [ -f "/.dockerenv" ]
    return $?
}

# Check if we're running in GitHub Actions specifically
is_github_actions() {
    [ -n "${GITHUB_ACTIONS:-}" ]
}

# Check if we're running in a Docker container
is_docker_container() {
    [ "${IN_DOCKER_CONTAINER}" = "true" ] || grep -q "docker\|container" /proc/1/cgroup 2>/dev/null || [ -f "/.dockerenv" ]
}

# Check if we're in any restricted environment 
is_restricted_environment() {
    is_github_actions || is_container
}

# Export all functions for use in other scripts
export -f log
export -f print_banner
export -f print_section
export -f is_container
export -f is_github_actions
export -f is_docker_container
export -f is_restricted_environment