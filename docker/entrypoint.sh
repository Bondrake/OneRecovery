#!/bin/bash
# Docker entrypoint script for OneRecovery builder

# Fixed uid/gid or take from environment
USER_ID=${USER_ID:-1000}
GROUP_ID=${GROUP_ID:-1000}

echo "Starting with UID: $USER_ID, GID: $GROUP_ID"

# Update the builder user's uid/gid if needed
if [ "$USER_ID" != "1000" ] || [ "$GROUP_ID" != "1000" ]; then
    echo "Updating builder user to match host UID/GID"
    deluser builder
    addgroup -g $GROUP_ID builder
    adduser -D -u $USER_ID -G builder builder
    echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder
    chown -R $USER_ID:$GROUP_ID /onerecovery
    chown -R $USER_ID:$GROUP_ID /home/builder
fi

# Ensure the build directories have proper permissions
mkdir -p /onerecovery/build /onerecovery/output /onerecovery/.buildcache
chown -R $(id -u builder):$(id -g builder) /onerecovery

# Set working directory
cd /onerecovery/build

# Run the command as the builder user
if [ $# -eq 0 ]; then
    # Default command if none provided
    exec su-exec builder ./build.sh
else
    # Run whatever command was passed
    exec su-exec builder "$@"
fi