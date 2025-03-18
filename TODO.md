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
   - [ ] Create a specialized script for extremely memory-constrained GitHub Actions builds
   - [ ] Add automatic kernel config minimization for memory-constrained builds

3. **Documentation Updates**
   - [ ] Update usage_modules function in build.sh to clarify direct vs. passthrough usage
   - [ ] Update documentation files to reflect new timing and performance features
   - [ ] Create a comprehensive guide on GitHub Actions build optimization

## Final Cleanup and Deprecation

1. **Script Cleanup**
   - [ ] After thorough testing, deprecate 85_cross_env_build.sh
   - [ ] Update any remaining scripts that might reference the cross-env build

2. **Future Enhancements**
   - [ ] Add automatic memory and thread detection to Docker build
   - [ ] Create dashboard for visualizing build performance metrics
   - [ ] Implement build cache validation to avoid unnecessary rebuilds
   - [ ] Add parallel downloading of dependencies for faster initial setup

_These timing and performance enhancements help optimize builds for various hardware configurations, especially resource-constrained environments like GitHub Actions._
