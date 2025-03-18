# OneRecovery Build System Migration Tasks

## Critical Tasks

1. **Move build logic from 85_cross_env_build.sh back to 04_build.sh**
   - Copy all core build functionality from 85_cross_env_build.sh to 04_build.sh
   - Ensure all improvements made to 85_cross_env_build.sh are preserved
   - Test to ensure build works after the migration

2. **Update Docker entrypoint.sh**
   - [DONE] Replace all references to 85_cross_env_build.sh with 04_build.sh
   - [DONE] Remove legacy build system concept
   - Test Docker builds after migration

3. **Update GitHub Actions workflow**
   - [DONE] Ensure the workflow uses the standard build sequence
   - [DONE] Properly applies kernel configs via 03_conf.sh
   - Test GitHub Actions builds after migration

## Documentation Updates

4. **Update READMEs and build documentation**
   - `/docker/README.md`: Remove references to 85_cross_env_build.sh
   - `/build/README.md`: Update build instructions to reflect new process
   - `/docs/BUILD_DOCS.md`: Remove references to cross env and legacy build system
   - Any other documentation files that reference the build process

5. **Update CLAUDE.md**
   - Update build commands and process information

## Final Steps

6. **Cleanup**
   - After thorough testing, consider deprecating 85_cross_env_build.sh
   - Update any remaining scripts that might reference the cross-env build

## Notes

- The GitHub Actions workflow now uses the proper build sequence (01_get.sh, 02_chrootandinstall.sh, 03_conf.sh, 04_build.sh)
- Docker builds will use 04_build.sh directly with the migrated functionality
- Maintaining backward compatibility is important during the transition

_This migration consolidates the build system to simplify maintenance and ensure consistency across different build environments._