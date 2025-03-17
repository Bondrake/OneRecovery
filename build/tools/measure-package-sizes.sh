#!/bin/bash
#
# OneRecovery Package Size Analysis Script
# Measures the size impact of each advanced package group on the final EFI file
#
# This script conducts a thorough size analysis by:
#
# 1. Building 36 different EFI configurations:
#    - Tests each of the 8 advanced package groups independently
#    - Tests combinations with 4 compression methods (none, UPX, ZSTD, XZ)
#    - Includes baseline and full builds for comparison
#
# 2. Generating detailed reports:
#    - CSV files with precise size measurements
#    - Formatted text reports with human-readable size information
#    - Comprehensive Markdown report with tables comparing all options
#    - Summary showing both absolute size impact and percentage increases
#
# 3. Analyzing compression efficiency:
#    - Determines compression ratio for each package group
#    - Compares effectiveness of different compression algorithms
#    - Identifies which package groups compress most efficiently
#
# Usage:
#   cd build/tools
#   ./measure-package-sizes.sh
#
# Output (in /output/size-analysis/):
#   - efi-files/             - Contains all 36 built EFI files for comparison
#   - logs/                  - Build logs for each configuration
#   - size-report-*.csv      - Raw size data in CSV format
#   - size-report-*.txt      - Human-readable text reports
#   - summary-report.csv     - Combined data comparing all configurations
#   - summary-report.txt     - Text summary of all measurements
#   - size-analysis-report.md - Complete Markdown report with tables and charts
#
# The results let you:
# 1. See exactly how many bytes each package group adds
# 2. Identify which groups have the largest/smallest impact
# 3. Determine the most space-efficient compression method
# 4. Make informed decisions about which packages to include
# 5. Optimize builds for different size constraints
#

# Define script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
OUTPUT_DIR="$(cd "$BUILD_DIR/../output" && pwd)"
RESULTS_DIR="$OUTPUT_DIR/size-analysis"

# Define colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print banner
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
    echo -e "${GREEN}   OneRecovery Size Analysis Tool  ${NC}"
    echo "----------------------------------------------------"
}

# Package groups to test
declare -a PACKAGE_GROUPS=(
    "advanced-fs"     # Advanced filesystem tools
    "disk-diag"       # Disk and hardware diagnostics
    "network-diag"    # Network diagnostics and VPN
    "system-tools"    # Advanced system utilities
    "data-recovery"   # Advanced data recovery tools
    "boot-repair"     # Boot repair utilities
    "editors"         # Advanced text editors
    "security"        # Security analysis tools
)

# Log function
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
            ;;
        "SUCCESS")
            echo -e "${GREEN}[SUCCESS]${NC} $message"
            ;;
        *)
            echo -e "$message"
            ;;
    esac
}

# Create directories
create_dirs() {
    mkdir -p "$RESULTS_DIR"
    mkdir -p "$RESULTS_DIR/efi-files"
    mkdir -p "$RESULTS_DIR/logs"
}

# Clean previous results
clean_previous() {
    if [ -d "$RESULTS_DIR" ]; then
        log "INFO" "Cleaning previous results..."
        rm -rf "$RESULTS_DIR"
        create_dirs
    fi
}

# Build core configuration with no advanced packages
build_baseline() {
    local compression=$1
    local basename="baseline"
    local compname="${basename}-${compression}"
    
    log "INFO" "Building baseline (no advanced packages) with $compression compression..."
    
    # Define build arguments
    local build_args="--with-zfs --with-recovery-tools --with-network-tools --without-all-advanced"
    
    # Add compression settings
    if [ "$compression" == "none" ]; then
        build_args="$build_args --without-compression"
    else
        build_args="$build_args --with-compression --compression-tool=$compression"
    fi

    # Run the build
    cd "$BUILD_DIR"
    
    # Clean up any previous build artifacts
    ./99_cleanup.sh > "$RESULTS_DIR/logs/${compname}-cleanup.log" 2>&1
    
    # Run the cross-environment build
    ./85_cross_env_build.sh $build_args > "$RESULTS_DIR/logs/${compname}-build.log" 2>&1
    
    # Check if build was successful
    if [ -f "$OUTPUT_DIR/OneRecovery.efi" ]; then
        # Copy the EFI file for analysis
        cp "$OUTPUT_DIR/OneRecovery.efi" "$RESULTS_DIR/efi-files/OneRecovery-${compname}.efi"
        log "SUCCESS" "Baseline build with $compression compression completed"
        return 0
    else
        log "ERROR" "Baseline build with $compression compression failed"
        return 1
    fi
}

# Build with specific package group
build_with_package_group() {
    local group=$1
    local compression=$2
    local compname="${group}-${compression}"
    
    log "INFO" "Building with $group package group and $compression compression..."
    
    # Define build arguments
    local build_args="--with-zfs --with-recovery-tools --with-network-tools --without-all-advanced --with-${group}"
    
    # Add compression settings
    if [ "$compression" == "none" ]; then
        build_args="$build_args --without-compression"
    else
        build_args="$build_args --with-compression --compression-tool=$compression"
    fi

    # Run the build
    cd "$BUILD_DIR"
    
    # Clean up any previous build artifacts
    ./99_cleanup.sh > "$RESULTS_DIR/logs/${compname}-cleanup.log" 2>&1
    
    # Run the cross-environment build
    ./85_cross_env_build.sh $build_args > "$RESULTS_DIR/logs/${compname}-build.log" 2>&1
    
    # Check if build was successful
    if [ -f "$OUTPUT_DIR/OneRecovery.efi" ]; then
        # Copy the EFI file for analysis
        cp "$OUTPUT_DIR/OneRecovery.efi" "$RESULTS_DIR/efi-files/OneRecovery-${compname}.efi"
        log "SUCCESS" "Build with $group package group and $compression compression completed"
        return 0
    else
        log "ERROR" "Build with $group package group and $compression compression failed"
        return 1
    fi
}

# Build with all package groups
build_full() {
    local compression=$1
    local basename="full"
    local compname="${basename}-${compression}"
    
    log "INFO" "Building full configuration (all packages) with $compression compression..."
    
    # Define build arguments
    local build_args="--full"
    
    # Add compression settings
    if [ "$compression" == "none" ]; then
        build_args="$build_args --without-compression"
    else
        build_args="$build_args --with-compression --compression-tool=$compression"
    fi

    # Run the build
    cd "$BUILD_DIR"
    
    # Clean up any previous build artifacts
    ./99_cleanup.sh > "$RESULTS_DIR/logs/${compname}-cleanup.log" 2>&1
    
    # Run the cross-environment build
    ./85_cross_env_build.sh $build_args > "$RESULTS_DIR/logs/${compname}-build.log" 2>&1
    
    # Check if build was successful
    if [ -f "$OUTPUT_DIR/OneRecovery.efi" ]; then
        # Copy the EFI file for analysis
        cp "$OUTPUT_DIR/OneRecovery.efi" "$RESULTS_DIR/efi-files/OneRecovery-${compname}.efi"
        log "SUCCESS" "Full build with $compression compression completed"
        return 0
    else
        log "ERROR" "Full build with $compression compression failed"
        return 1
    fi
}

# Analyze results
analyze_results() {
    local compression=$1
    local report_file="$RESULTS_DIR/size-report-${compression}.txt"
    local csv_file="$RESULTS_DIR/size-report-${compression}.csv"
    local baseline_file="$RESULTS_DIR/efi-files/OneRecovery-baseline-${compression}.efi"
    local full_file="$RESULTS_DIR/efi-files/OneRecovery-full-${compression}.efi"
    
    # Check if baseline file exists
    if [ ! -f "$baseline_file" ]; then
        log "ERROR" "Baseline file not found: $baseline_file"
        return 1
    fi
    
    # Get baseline size
    local baseline_size=$(stat -c %s "$baseline_file" 2>/dev/null || stat -f %z "$baseline_file")
    
    # Create header for report
    echo "OneRecovery Size Analysis Report (${compression} compression)" > "$report_file"
    echo "=========================================================" >> "$report_file"
    echo "" >> "$report_file"
    echo "Baseline size (no advanced packages): $(numfmt --to=iec-i --suffix=B $baseline_size) ($baseline_size bytes)" >> "$report_file"
    echo "" >> "$report_file"
    echo "Advanced Package Group Size Contributions:" >> "$report_file"
    echo "----------------------------------------" >> "$report_file"
    
    # CSV header
    echo "Package Group,Size (bytes),Size (human),Increase (bytes),Increase (%)" > "$csv_file"
    
    # Record baseline in CSV
    echo "baseline,$baseline_size,$(numfmt --to=iec-i --suffix=B $baseline_size),0,0%" >> "$csv_file"
    
    # Analyze each package group
    for group in "${PACKAGE_GROUPS[@]}"; do
        local group_file="$RESULTS_DIR/efi-files/OneRecovery-${group}-${compression}.efi"
        
        if [ -f "$group_file" ]; then
            local group_size=$(stat -c %s "$group_file" 2>/dev/null || stat -f %z "$group_file")
            local size_increase=$((group_size - baseline_size))
            local percent_increase=$(awk "BEGIN {printf \"%.2f\", ($size_increase / $baseline_size) * 100}")
            
            echo "$group: $(numfmt --to=iec-i --suffix=B $group_size) ($group_size bytes)" >> "$report_file"
            echo "  - Increase over baseline: $(numfmt --to=iec-i --suffix=B $size_increase) ($size_increase bytes, +${percent_increase}%)" >> "$report_file"
            
            # Add to CSV
            echo "$group,$group_size,$(numfmt --to=iec-i --suffix=B $group_size),$size_increase,${percent_increase}%" >> "$csv_file"
        else
            echo "$group: Build failed or file not found" >> "$report_file"
            echo "$group,0,0,0,0%" >> "$csv_file"
        fi
    done
    
    # Add full build analysis if available
    if [ -f "$full_file" ]; then
        local full_size=$(stat -c %s "$full_file" 2>/dev/null || stat -f %z "$full_file")
        local full_increase=$((full_size - baseline_size))
        local full_percent=$(awk "BEGIN {printf \"%.2f\", ($full_increase / $baseline_size) * 100}")
        
        echo "" >> "$report_file"
        echo "Full build (all advanced packages): $(numfmt --to=iec-i --suffix=B $full_size) ($full_size bytes)" >> "$report_file"
        echo "  - Increase over baseline: $(numfmt --to=iec-i --suffix=B $full_increase) ($full_increase bytes, +${full_percent}%)" >> "$report_file"
        
        # Add to CSV
        echo "full-build,$full_size,$(numfmt --to=iec-i --suffix=B $full_size),$full_increase,${full_percent}%" >> "$csv_file"
    else
        echo "" >> "$report_file"
        echo "Full build: Failed or file not found" >> "$report_file"
    fi
    
    log "SUCCESS" "Analysis for $compression compression completed"
    log "INFO" "Report saved to: $report_file"
    log "INFO" "CSV data saved to: $csv_file"
}

# Create summary report comparing compression methods
create_summary() {
    local summary_file="$RESULTS_DIR/summary-report.txt"
    local summary_csv="$RESULTS_DIR/summary-report.csv"
    
    echo "OneRecovery Size Analysis Summary" > "$summary_file"
    echo "=================================" >> "$summary_file"
    echo "" >> "$summary_file"
    
    # CSV header
    echo "Package Group,Uncompressed (bytes),UPX (bytes),UPX Reduction (%),ZSTD (bytes),ZSTD Reduction (%),XZ (bytes),XZ Reduction (%)" > "$summary_csv"
    
    # Process baseline and each package group
    process_group() {
        local group=$1
        local none_file="$RESULTS_DIR/efi-files/OneRecovery-${group}-none.efi"
        local upx_file="$RESULTS_DIR/efi-files/OneRecovery-${group}-upx.efi"
        local zstd_file="$RESULTS_DIR/efi-files/OneRecovery-${group}-zstd.efi"
        local xz_file="$RESULTS_DIR/efi-files/OneRecovery-${group}-xz.efi"
        
        echo "$group Configuration:" >> "$summary_file"
        
        # Check if files exist
        if [ ! -f "$none_file" ]; then
            echo "  Uncompressed: Not available" >> "$summary_file"
            return
        fi
        
        # Get sizes
        local none_size=$(stat -c %s "$none_file" 2>/dev/null || stat -f %z "$none_file")
        
        echo "  Uncompressed: $(numfmt --to=iec-i --suffix=B $none_size) ($none_size bytes)" >> "$summary_file"
        
        # CSV entry start
        local csv_line="$group,$none_size"
        
        # Process each compression method
        for comp in upx zstd xz; do
            local comp_file="$RESULTS_DIR/efi-files/OneRecovery-${group}-${comp}.efi"
            
            if [ -f "$comp_file" ]; then
                local comp_size=$(stat -c %s "$comp_file" 2>/dev/null || stat -f %z "$comp_file")
                local size_reduction=$((none_size - comp_size))
                local percent_reduction=$(awk "BEGIN {printf \"%.2f\", ($size_reduction / $none_size) * 100}")
                
                echo "  $comp compression: $(numfmt --to=iec-i --suffix=B $comp_size) ($comp_size bytes)" >> "$summary_file"
                echo "    - Reduction: $(numfmt --to=iec-i --suffix=B $size_reduction) ($size_reduction bytes, -${percent_reduction}%)" >> "$summary_file"
                
                # Add to CSV line
                csv_line="$csv_line,$comp_size,${percent_reduction}"
            else
                echo "  $comp compression: Not available" >> "$summary_file"
                csv_line="$csv_line,0,0"
            fi
        done
        
        # Write CSV line
        echo "$csv_line" >> "$summary_csv"
    }
    
    # Process baseline
    process_group "baseline"
    echo "" >> "$summary_file"
    
    # Process each package group
    for group in "${PACKAGE_GROUPS[@]}"; do
        process_group "$group"
        echo "" >> "$summary_file"
    done
    
    # Process full build
    process_group "full"
    
    log "SUCCESS" "Summary report created"
    log "INFO" "Summary report saved to: $summary_file"
    log "INFO" "Summary CSV data saved to: $summary_csv"
}

# Create Markdown report
create_markdown_report() {
    local md_file="$RESULTS_DIR/size-analysis-report.md"
    
    echo "# OneRecovery Size Analysis Report" > "$md_file"
    echo "" >> "$md_file"
    echo "## Overview" >> "$md_file"
    echo "" >> "$md_file"
    echo "This report analyzes the size impact of each advanced package group on the final EFI file, both with and without compression." >> "$md_file"
    echo "" >> "$md_file"
    
    # Add baseline information
    echo "## Baseline Configuration" >> "$md_file"
    echo "" >> "$md_file"
    echo "The baseline configuration includes:" >> "$md_file"
    echo "- ZFS support" >> "$md_file"
    echo "- Basic recovery tools" >> "$md_file"
    echo "- Basic network tools" >> "$md_file"
    echo "- No advanced package groups" >> "$md_file"
    echo "" >> "$md_file"
    
    # Create a table for baseline sizes
    echo "| Compression | Size | Reduction |" >> "$md_file"
    echo "|------------|------|-----------|" >> "$md_file"
    
    local none_file="$RESULTS_DIR/efi-files/OneRecovery-baseline-none.efi"
    local none_size=0
    
    if [ -f "$none_file" ]; then
        none_size=$(stat -c %s "$none_file" 2>/dev/null || stat -f %z "$none_file")
        echo "| None | $(numfmt --to=iec-i --suffix=B $none_size) | 0% |" >> "$md_file"
    else
        echo "| None | N/A | N/A |" >> "$md_file"
    fi
    
    for comp in upx zstd xz; do
        local comp_file="$RESULTS_DIR/efi-files/OneRecovery-baseline-${comp}.efi"
        
        if [ -f "$comp_file" ]; then
            local comp_size=$(stat -c %s "$comp_file" 2>/dev/null || stat -f %z "$comp_file")
            local size_reduction=$((none_size - comp_size))
            local percent_reduction=$(awk "BEGIN {printf \"%.2f\", ($size_reduction / $none_size) * 100}")
            
            echo "| ${comp} | $(numfmt --to=iec-i --suffix=B $comp_size) | -${percent_reduction}% |" >> "$md_file"
        else
            echo "| ${comp} | N/A | N/A |" >> "$md_file"
        fi
    done
    
    echo "" >> "$md_file"
    
    # Add package group information
    echo "## Advanced Package Groups" >> "$md_file"
    echo "" >> "$md_file"
    echo "Each package group was tested individually to measure its impact on the final EFI file size." >> "$md_file"
    echo "" >> "$md_file"
    
    # Create a table for uncompressed sizes
    echo "### Uncompressed Size Impact" >> "$md_file"
    echo "" >> "$md_file"
    echo "| Package Group | Size | Increase over Baseline | Percentage Increase |" >> "$md_file"
    echo "|---------------|------|------------------------|---------------------|" >> "$md_file"
    
    for group in "${PACKAGE_GROUPS[@]}"; do
        local group_file="$RESULTS_DIR/efi-files/OneRecovery-${group}-none.efi"
        
        if [ -f "$group_file" ]; then
            local group_size=$(stat -c %s "$group_file" 2>/dev/null || stat -f %z "$group_file")
            local size_increase=$((group_size - none_size))
            local percent_increase=$(awk "BEGIN {printf \"%.2f\", ($size_increase / $none_size) * 100}")
            
            echo "| $group | $(numfmt --to=iec-i --suffix=B $group_size) | $(numfmt --to=iec-i --suffix=B $size_increase) | +${percent_increase}% |" >> "$md_file"
        else
            echo "| $group | N/A | N/A | N/A |" >> "$md_file"
        fi
    done
    
    # Add full build information
    local full_file="$RESULTS_DIR/efi-files/OneRecovery-full-none.efi"
    
    if [ -f "$full_file" ]; then
        local full_size=$(stat -c %s "$full_file" 2>/dev/null || stat -f %z "$full_file")
        local full_increase=$((full_size - none_size))
        local full_percent=$(awk "BEGIN {printf \"%.2f\", ($full_increase / $none_size) * 100}")
        
        echo "| **Full Build** | $(numfmt --to=iec-i --suffix=B $full_size) | $(numfmt --to=iec-i --suffix=B $full_increase) | +${full_percent}% |" >> "$md_file"
    else
        echo "| **Full Build** | N/A | N/A | N/A |" >> "$md_file"
    fi
    
    echo "" >> "$md_file"
    
    # Add compressed sizes section
    for comp in upx zstd xz; do
        echo "### ${comp} Compressed Size Impact" >> "$md_file"
        echo "" >> "$md_file"
        echo "| Package Group | Size | Increase over Baseline | Percentage Increase | Compression Ratio |" >> "$md_file"
        echo "|---------------|------|------------------------|---------------------|-------------------|" >> "$md_file"
        
        local comp_baseline_file="$RESULTS_DIR/efi-files/OneRecovery-baseline-${comp}.efi"
        local comp_baseline_size=0
        
        if [ -f "$comp_baseline_file" ]; then
            comp_baseline_size=$(stat -c %s "$comp_baseline_file" 2>/dev/null || stat -f %z "$comp_baseline_file")
        else
            continue
        fi
        
        for group in "${PACKAGE_GROUPS[@]}"; do
            local group_comp_file="$RESULTS_DIR/efi-files/OneRecovery-${group}-${comp}.efi"
            local group_none_file="$RESULTS_DIR/efi-files/OneRecovery-${group}-none.efi"
            
            if [ -f "$group_comp_file" ] && [ -f "$group_none_file" ]; then
                local group_comp_size=$(stat -c %s "$group_comp_file" 2>/dev/null || stat -f %z "$group_comp_file")
                local group_none_size=$(stat -c %s "$group_none_file" 2>/dev/null || stat -f %z "$group_none_file")
                local size_increase=$((group_comp_size - comp_baseline_size))
                local percent_increase=$(awk "BEGIN {printf \"%.2f\", ($size_increase / $comp_baseline_size) * 100}")
                local comp_ratio=$(awk "BEGIN {printf \"%.2f\", ($group_none_size / $group_comp_size)}")
                
                echo "| $group | $(numfmt --to=iec-i --suffix=B $group_comp_size) | $(numfmt --to=iec-i --suffix=B $size_increase) | +${percent_increase}% | ${comp_ratio}x |" >> "$md_file"
            else
                echo "| $group | N/A | N/A | N/A | N/A |" >> "$md_file"
            fi
        done
        
        # Add full build information for this compression
        local full_comp_file="$RESULTS_DIR/efi-files/OneRecovery-full-${comp}.efi"
        local full_none_file="$RESULTS_DIR/efi-files/OneRecovery-full-none.efi"
        
        if [ -f "$full_comp_file" ] && [ -f "$full_none_file" ]; then
            local full_comp_size=$(stat -c %s "$full_comp_file" 2>/dev/null || stat -f %z "$full_comp_file")
            local full_none_size=$(stat -c %s "$full_none_file" 2>/dev/null || stat -f %z "$full_none_file")
            local full_increase=$((full_comp_size - comp_baseline_size))
            local full_percent=$(awk "BEGIN {printf \"%.2f\", ($full_increase / $comp_baseline_size) * 100}")
            local full_ratio=$(awk "BEGIN {printf \"%.2f\", ($full_none_size / $full_comp_size)}")
            
            echo "| **Full Build** | $(numfmt --to=iec-i --suffix=B $full_comp_size) | $(numfmt --to=iec-i --suffix=B $full_increase) | +${full_percent}% | ${full_ratio}x |" >> "$md_file"
        else
            echo "| **Full Build** | N/A | N/A | N/A | N/A |" >> "$md_file"
        fi
        
        echo "" >> "$md_file"
    done
    
    # Add conclusions
    echo "## Conclusions" >> "$md_file"
    echo "" >> "$md_file"
    echo "- Package group with the largest size impact: " >> "$md_file"
    echo "- Package group with the smallest size impact: " >> "$md_file"
    echo "- Most efficient compression method: " >> "$md_file"
    echo "- Recommended configuration for size-constrained environments: " >> "$md_file"
    echo "" >> "$md_file"
    
    echo "## Raw Data" >> "$md_file"
    echo "" >> "$md_file"
    echo "Raw size data in bytes is available in the CSV files generated alongside this report:" >> "$md_file"
    echo "- `size-report-none.csv` - Uncompressed sizes" >> "$md_file"
    echo "- `size-report-upx.csv` - UPX compressed sizes" >> "$md_file"
    echo "- `size-report-zstd.csv` - ZSTD compressed sizes" >> "$md_file"
    echo "- `size-report-xz.csv` - XZ compressed sizes" >> "$md_file"
    echo "- `summary-report.csv` - Combined summary data" >> "$md_file"
    
    log "SUCCESS" "Markdown report created"
    log "INFO" "Markdown report saved to: $md_file"
}

# Main function
main() {
    print_banner
    log "INFO" "Starting OneRecovery package size analysis"
    
    # Create directories
    clean_previous
    create_dirs
    
    # Run builds with no compression
    log "INFO" "Testing uncompressed builds..."
    build_baseline "none"
    for group in "${PACKAGE_GROUPS[@]}"; do
        build_with_package_group "$group" "none"
    done
    build_full "none"
    analyze_results "none"
    
    # Run builds with UPX compression
    log "INFO" "Testing UPX compressed builds..."
    build_baseline "upx"
    for group in "${PACKAGE_GROUPS[@]}"; do
        build_with_package_group "$group" "upx"
    done
    build_full "upx"
    analyze_results "upx"
    
    # Run builds with ZSTD compression
    log "INFO" "Testing ZSTD compressed builds..."
    build_baseline "zstd"
    for group in "${PACKAGE_GROUPS[@]}"; do
        build_with_package_group "$group" "zstd"
    done
    build_full "zstd"
    analyze_results "zstd"
    
    # Run builds with XZ compression
    log "INFO" "Testing XZ compressed builds..."
    build_baseline "xz"
    for group in "${PACKAGE_GROUPS[@]}"; do
        build_with_package_group "$group" "xz"
    done
    build_full "xz"
    analyze_results "xz"
    
    # Create summary and markdown reports
    create_summary
    create_markdown_report
    
    log "SUCCESS" "Package size analysis completed"
    log "INFO" "Results are available in: $RESULTS_DIR"
    log "INFO" "See the Markdown report for a detailed analysis: $RESULTS_DIR/size-analysis-report.md"
}

# Execute main function
main "$@"