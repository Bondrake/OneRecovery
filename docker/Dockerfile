FROM alpine:latest

# Install build dependencies
RUN apk add --no-cache \
    bash \
    build-base \
    linux-headers \
    git \
    autoconf \
    automake \
    libtool \
    util-linux \
    xz-dev \
    zlib-dev \
    zstd-dev \
    lz4-dev \
    openssl-dev \
    libelf \
    elfutils-dev \
    bison \
    flex \
    ccache \
    upx \
    xz \
    zstd \
    curl \
    wget \
    sudo \
    gcc \
    g++ \
    make \
    patch \
    python3 \
    ncurses-dev \
    e2fsprogs \
    coreutils \
    mtools \
    xorriso \
    squashfs-tools \
    kmod \
    bc \
    rsync \
    shadow \
    su-exec

# Create non-root user to run the build as
RUN adduser -D -u 1000 builder && \
    echo "builder ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/builder && \
    chmod 4755 /bin/busybox

# Set up build directories and cache locations
RUN mkdir -p /onerecovery/build /onerecovery/output /onerecovery/.buildcache && \
    chown -R builder:builder /onerecovery

# Create cache directories
RUN mkdir -p /onerecovery/.buildcache/sources \
             /onerecovery/.buildcache/packages \
             /onerecovery/.buildcache/ccache \
             /onerecovery/.buildcache/build && \
    chown -R builder:builder /onerecovery/.buildcache

# Configure ccache
ENV CCACHE_DIR=/onerecovery/.buildcache/ccache
ENV PATH=/usr/lib/ccache:$PATH
RUN su builder -c "ccache -M 5G"

# Copy entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Set workdir
WORKDIR /onerecovery

# Install a healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD ps aux | grep -v grep | grep -q "bash" || exit 1

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["./build.sh"]