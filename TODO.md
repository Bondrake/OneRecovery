# OneRecovery Build System Tasks

## Build Timing and Performance Enhancement Tasks

1. **Build Timing System**
   - [DONE] Add timing functions to 80_common.sh
   - [DONE] Add timing to 01_get.sh
   - [DONE] Add timing to 02_chrootandinstall.sh
   - [DONE] Add timing to 03_conf.sh
   - [DONE] Add timing to 04_build.sh
   - [DONE] Add GitHub Actions artifact support for timing logs
   - [DONE] Update Docker build process for timing logs
   - [ ] Add script to analyze build timing logs and suggest optimizations

2. **Build Performance Optimizations**
   - [DONE] Add memory-optimized compiler flags function
   - [DONE] Enhance thread counting for memory-constrained environments
   - [DONE] Add direct passthrough mechanism for build arguments
   - [ ] Test GitHub Actions builds with timing and performance enhancements
   - [ ] Implement incremental build support to speed up rebuilds
   - [ ] Add parallelized download mechanism for source files

3. **Documentation Updates**
   - [DONE] Update usage_modules function in build.sh to clarify direct vs. passthrough usage
   - [DONE] Update CLAUDE.md with updated library architecture documentation
   - [DONE] Add comprehensive help text to 84_build_core.sh for consistent help across scripts
   - [DONE] Update Docker build scripts to use the -- passthrough mechanism consistently
   - [DONE] Update GitHub Actions workflow to use the -- passthrough mechanism
   - [ ] Create a comprehensive guide on GitHub Actions build optimization

## Final Cleanup and Deprecation

1. **Script Cleanup**
   - [DONE] Extract common build functions to 84_build_core.sh
   - [DONE] Deprecate and remove 85_cross_env_build.sh
   - [DONE] Update build.sh and 04_build.sh to use the shared 84_build_core.sh

2. **Future Enhancements**
   - [ ] Create dashboard for visualizing build performance metrics
   - [ ] Implement build cache validation to avoid unnecessary rebuilds

_The modular library architecture and standardized build process enables efficient development across diverse environments, from resource-constrained CI systems to powerful development workstations. By implementing consistent timing and passthrough mechanisms, we've created a foundation for ongoing performance optimization and feature development._