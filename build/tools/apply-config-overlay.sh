#!/bin/bash
# Kernel configuration overlay utility
# Applies a kernel configuration fragment over a base config

# Source common library
if [ -f "./80_common.sh" ]; then
    source ./80_common.sh
else
    echo "ERROR: Common library not found at $COMMON_LIB"
    echo "This script must be run from the tools directory of the OneRecovery build system."
    exit 1
fi


# Apply a kernel config overlay (fragment) to a base config
apply_config_overlay() {
    local overlay_file="$1"
    local base_config="$2"
    
    if [ ! -f "$overlay_file" ]; then
        log "ERROR" "Config overlay not found: $overlay_file"
        return 1
    fi
    
    if [ ! -f "$base_config" ]; then
        log "ERROR" "Base config not found: $base_config"
        return 1
    fi
    
    log "INFO" "Applying config overlay: $overlay_file to $base_config"
    
    # Count features being modified
    local features_added=0
    local features_modified=0
    
    # Process each line in the overlay file
    while IFS= read -r line; do
        # Skip comments and empty lines
        if [[ "$line" =~ ^[[:space:]]*# || -z "${line// }" ]]; then
            continue
        fi
        
        # Extract option name
        local option_name=$(echo "$line" | cut -d'=' -f1)
        
        # Check if option already exists in the base config
        if grep -q "^$option_name=" "$base_config" || grep -q "^# $option_name is not set" "$base_config"; then
            features_modified=$((features_modified+1))
            # Remove existing option from base config
            sed -i "/^$option_name=/d" "$base_config"
            sed -i "/^# $option_name is not set/d" "$base_config"
        else
            features_added=$((features_added+1))
        fi
        
        # Append new option
        echo "$line" >> "$base_config"
        
    done < "$overlay_file"
    
    log "SUCCESS" "Applied config overlay: $overlay_file"
    log "INFO" "Features added: $features_added, Features modified: $features_modified"
    return 0
}

# Run if executed directly
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    # Check for required arguments
    if [ $# -ne 2 ]; then
        echo "Usage: $0 <overlay_file> <base_config>"
        echo "Example: $0 features/zfs-support.conf kernel.config"
        exit 1
    fi
    
    # Run the function with provided arguments
    apply_config_overlay "$1" "$2"
    exit $?
fi