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

# Version information
ALPINE_VERSION="3.21"      # Alpine Linux version to use
KERNEL_VERSION="6.12.19"   # Linux kernel version
ZFS_VERSION="2.3.0"        # ZFS version

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

# Function to safely source library files with error checking
source_library() {
    local library_file=$1
    local required=${2:-false}
    
    if [ -f "$library_file" ]; then
        # Source the library
        source "$library_file"
        return 0
    else
        if [ "$required" = "true" ]; then
            echo -e "${RED}[ERROR]${NC} Required library file not found: $library_file"
            exit 1
        else
            echo -e "${YELLOW}[WARNING]${NC} Library file not found: $library_file"
            return 1
        fi
    fi
}

# Function to initialize all standard libraries
source_libraries() {
    local script_path=${1:-"."}
    
    # Track loaded libraries to prevent duplication
    if [ -z "${LIBRARIES_LOADED:-}" ]; then
        # First time initialization
        export LIBRARIES_LOADED="80_common"
        
        # Error handling
        if source_library "$script_path/81_error_handling.sh"; then
            # Initialize error handling if available
            init_error_handling
            LIBRARIES_LOADED="$LIBRARIES_LOADED:81_error_handling"
        else
            echo -e "${YELLOW}[WARNING]${NC} Error handling is limited"
        fi
        
        # Build helpers
        if source_library "$script_path/82_build_helper.sh"; then
            LIBRARIES_LOADED="$LIBRARIES_LOADED:82_build_helper"
        fi
        
        # Optional configuration helpers
        if source_library "$script_path/83_config_helper.sh" false; then
            LIBRARIES_LOADED="$LIBRARIES_LOADED:83_config_helper"
        fi
        
        # Build core library (new)
        if [ -f "$script_path/84_build_core.sh" ]; then
            # Ensure it's executable
            if [ ! -x "$script_path/84_build_core.sh" ]; then
                chmod +x "$script_path/84_build_core.sh" 2>/dev/null || echo -e "${YELLOW}[WARNING]${NC} Could not make build core library executable"
            fi
            
            if source_library "$script_path/84_build_core.sh"; then
                LIBRARIES_LOADED="$LIBRARIES_LOADED:84_build_core"
            fi
        fi
    else
        echo -e "${BLUE}[INFO]${NC} Libraries already loaded: $LIBRARIES_LOADED"
    fi
    
    return 0
}

# Function to initialize the script with a standard header
# This should be the ONLY place that prints the banner
initialize_script() {
    # Print the banner
    print_banner
    
    # Set flag to prevent duplicate banners
    export BANNER_PRINTED=true
}

# Timing functions for build performance tracking
# ==========================================

# Global timing variables
GLOBAL_BUILD_START_TIME=$(date +%s)

# Get script directory for absolute paths
COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Define timing log with absolute path for consistency across scripts
TIMING_LOG_FILE="${COMMON_DIR}/build_timing.log"

# Timing function for build steps
log_timing() {
    local step_name="$1"
    local step_duration="$2"
    local log_file="${TIMING_LOG_FILE}"
    
    # Create log file with header if it doesn't exist
    if [ ! -f "$log_file" ]; then
        echo "==========================================" > "$log_file"
        echo "OneRecovery Build Timing Log" >> "$log_file"
        echo "Started at: $(date)" >> "$log_file"
        echo "==========================================" >> "$log_file"
        echo "" >> "$log_file"
        echo "STEP                               DURATION" >> "$log_file"
        echo "----------------------------------------" >> "$log_file"
    fi
    
    # Format timing information (right-aligned)
    local formatted_time=$(printf "%-35s %6ds" "$step_name" "$step_duration")
    echo "$formatted_time" >> "$log_file"
    
    # Also log to console
    log "INFO" "[TIMING] $step_name: ${step_duration}s"
}

# Start timing for a step
start_timing() {
    STEP_NAME="$1"
    STEP_START_TIME=$(date +%s)
    log "INFO" "[TIMING] Starting: $STEP_NAME"
}

# End timing for a step
end_timing() {
    local current_time=$(date +%s)
    local duration=$((current_time - STEP_START_TIME))
    log_timing "$STEP_NAME" "$duration"
}

# Finalize timing log with summary
finalize_timing_log() {
    local build_end_time=$(date +%s)
    local build_duration=$((build_end_time - GLOBAL_BUILD_START_TIME))
    local build_minutes=$((build_duration / 60))
    local build_seconds=$((build_duration % 60))
    
    # Add total build time to timing log
    log_timing "TOTAL BUILD TIME" "$build_duration"
    
    # Add footer to timing log
    echo "" >> "${TIMING_LOG_FILE}"
    echo "==========================================" >> "${TIMING_LOG_FILE}"
    echo "Build completed at: $(date)" >> "${TIMING_LOG_FILE}"
    echo "Total build time: ${build_minutes}m ${build_seconds}s" >> "${TIMING_LOG_FILE}"
    echo "==========================================" >> "${TIMING_LOG_FILE}"
    
    log "INFO" "Detailed timing log saved to: ${TIMING_LOG_FILE}"
    
    return "$build_duration"
}

# Export all functions for use in other scripts
export -f log
export -f print_banner
export -f print_section
export -f is_container
export -f is_github_actions
export -f is_docker_container
export -f is_restricted_environment
export -f source_library
export -f source_libraries
export -f initialize_script
export -f log_timing
export -f start_timing
export -f end_timing
export -f finalize_timing_log