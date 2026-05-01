# syntax=docker/dockerfile:1.7

ARG RUST_VERSION=1
ARG DEBIAN_VERSION=bookworm

FROM --platform=$BUILDPLATFORM docker.io/tonistiigi/xx AS xx
FROM --platform=$BUILDPLATFORM rust:${RUST_VERSION}-slim-${DEBIAN_VERSION} AS base
FROM --platform=$BUILDPLATFORM rust:${RUST_VERSION}-slim-${DEBIAN_VERSION} AS toolchain

ARG DEBIAN_APT_MIRROR=http://deb.debian.org/debian
ARG DEBIAN_SECURITY_APT_MIRROR=http://deb.debian.org/debian-security
ARG LLVM_APT_MIRROR=https://apt.llvm.org
ARG RUSTUP_DIST_SERVER=https://static.rust-lang.org
ARG RUSTUP_UPDATE_ROOT=https://static.rust-lang.org/rustup
ARG RUSTUP_TOOLCHAIN=1.92.0
ENV RUSTUP_DIST_SERVER=${RUSTUP_DIST_SERVER}
ENV RUSTUP_UPDATE_ROOT=${RUSTUP_UPDATE_ROOT}
ENV RUSTUP_TOOLCHAIN=${RUSTUP_TOOLCHAIN}
ENV CARGO_NET_GIT_FETCH_WITH_CLI=true
ENV CARGO_NET_RETRY=10
ENV CARGO_HTTP_MULTIPLEXING=false

# Prevent deletion of apt cache
RUN rm -f /etc/apt/apt.conf.d/docker-clean

RUN <<EOF
    set -eux
    if [ -f /etc/apt/sources.list.d/debian.sources ]; then
        sed -i \
            -e "s|http://deb.debian.org/debian|${DEBIAN_APT_MIRROR}|g" \
            -e "s|https://deb.debian.org/debian|${DEBIAN_APT_MIRROR}|g" \
            -e "s|http://security.debian.org/debian-security|${DEBIAN_SECURITY_APT_MIRROR}|g" \
            -e "s|https://security.debian.org/debian-security|${DEBIAN_SECURITY_APT_MIRROR}|g" \
            -e "s|http://deb.debian.org/debian-security|${DEBIAN_SECURITY_APT_MIRROR}|g" \
            -e "s|https://deb.debian.org/debian-security|${DEBIAN_SECURITY_APT_MIRROR}|g" \
            /etc/apt/sources.list.d/debian.sources
    elif [ -f /etc/apt/sources.list ]; then
        sed -i \
            -e "s|http://deb.debian.org/debian|${DEBIAN_APT_MIRROR}|g" \
            -e "s|https://deb.debian.org/debian|${DEBIAN_APT_MIRROR}|g" \
            -e "s|http://security.debian.org/debian-security|${DEBIAN_SECURITY_APT_MIRROR}|g" \
            -e "s|https://security.debian.org/debian-security|${DEBIAN_SECURITY_APT_MIRROR}|g" \
            -e "s|http://deb.debian.org/debian-security|${DEBIAN_SECURITY_APT_MIRROR}|g" \
            -e "s|https://deb.debian.org/debian-security|${DEBIAN_SECURITY_APT_MIRROR}|g" \
            /etc/apt/sources.list
    fi
EOF

# Match Rustc version as close as possible
# rustc -vV
ARG LLVM_VERSION=21
# ENV RUSTUP_TOOLCHAIN=${RUST_VERSION}

# Install repo tools
# Line one: compiler tools
# Line two: curl, for downloading binaries and Git dependencies
# Line three: for xx-verify
# golang, cmake: For aws-lc-rs bindgen
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    apt-get update && apt-get install -y \
    pkg-config make jq \
    ca-certificates curl git gnupg \
    pax-utils \
    file
    # golang cmake

# LLVM packages
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked <<EOF
    set -eux
    . /etc/os-release
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://apt.llvm.org/llvm-snapshot.gpg.key \
        | gpg --dearmor -o /etc/apt/keyrings/apt.llvm.org.gpg
    echo "deb [signed-by=/etc/apt/keyrings/apt.llvm.org.gpg] ${LLVM_APT_MIRROR}/${VERSION_CODENAME}/ llvm-toolchain-${VERSION_CODENAME}-${LLVM_VERSION} main" \
        > /etc/apt/sources.list.d/llvm.list
    apt-get update
    apt-get install -y clang-${LLVM_VERSION} lldb-${LLVM_VERSION} lld-${LLVM_VERSION} clangd-${LLVM_VERSION}
EOF

# Create symlinks for LLVM tools
RUN <<EOF
    set -o xtrace
    # clang
    ln -s /usr/bin/clang-${LLVM_VERSION} /usr/bin/clang
    ln -s "/usr/bin/clang++-${LLVM_VERSION}" "/usr/bin/clang++"
    # lld
    ln -s /usr/bin/ld64.lld-${LLVM_VERSION} /usr/bin/ld64.lld
    ln -s /usr/bin/ld.lld-${LLVM_VERSION} /usr/bin/ld.lld
    ln -s /usr/bin/lld-${LLVM_VERSION} /usr/bin/lld
    ln -s /usr/bin/lld-link-${LLVM_VERSION} /usr/bin/lld-link
    ln -s /usr/bin/wasm-ld-${LLVM_VERSION} /usr/bin/wasm-ld
EOF

# Set up xx (cross-compilation scripts)
COPY --from=xx / /
ARG TARGETPLATFORM

# Install libraries linked by the binary
# xx-* are xx-specific meta-packages
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    xx-apt-get install -y \
    xx-c-essentials xx-cxx-essentials pkg-config \
    liburing-dev

# Set up Rust toolchain
WORKDIR /app
COPY ./rust-toolchain.toml .
RUN rustup toolchain install "${RUSTUP_TOOLCHAIN}" --profile minimal \
    && rustc --version \
    && xx-cargo --setup-target-triple

# Build binary
# Configure incremental compilation based on build context
ARG CARGO_INCREMENTAL=0
RUN echo "CARGO_INCREMENTAL=${CARGO_INCREMENTAL}" >> /etc/environment

# Configure pkg-config
RUN <<EOF
    set -o xtrace
    if command -v "$(xx-info)-pkg-config" >/dev/null 2>/dev/null; then
        echo "PKG_CONFIG_LIBDIR=/usr/lib/$(xx-info)/pkgconfig" >> /etc/environment
        echo "PKG_CONFIG=/usr/bin/$(xx-info)-pkg-config" >> /etc/environment
    fi
    echo "PKG_CONFIG_ALLOW_CROSS=true" >> /etc/environment
EOF

# Configure cc to use clang version
RUN <<EOF
    set -o xtrace
    echo "CC=clang" >> /etc/environment
    echo "CXX=clang++" >> /etc/environment
EOF

# Cross-language LTO
RUN <<EOF
    set -o xtrace
    echo "CFLAGS=-flto" >> /etc/environment
    echo "CXXFLAGS=-flto" >> /etc/environment
    # Linker is set to target-compatible clang by xx
    echo "RUSTFLAGS='-Clinker-plugin-lto -Clink-arg=-fuse-ld=lld'" >> /etc/environment
EOF

# Apply CPU-specific optimizations if TARGET_CPU is provided
ARG TARGET_CPU

RUN <<EOF
    set -o allexport
    set -o xtrace
    . /etc/environment
    if [ -n "${TARGET_CPU}" ]; then
        echo "CFLAGS='${CFLAGS} -march=${TARGET_CPU}'" >> /etc/environment
        echo "CXXFLAGS='${CXXFLAGS} -march=${TARGET_CPU}'" >> /etc/environment
        echo "RUSTFLAGS='${RUSTFLAGS} -C target-cpu=${TARGET_CPU}'" >> /etc/environment
    fi
EOF

# Prepare output directories
RUN mkdir /out

FROM toolchain AS builder


# Get source
COPY . .

# Restore timestamps from timelord cache if available
RUN --mount=type=cache,target=/timelord/ \
    if command -v timelord >/dev/null 2>&1; then \
        echo "Restoring timestamps from timelord cache"; \
        timelord sync --source-dir /app --cache-dir /timelord; \
    else \
        echo "Skipping timelord timestamp restore"; \
    fi

ARG TARGETPLATFORM

# Verify environment configuration
RUN xx-cargo --print-target-triple

# Conduwuit version info
ARG GIT_COMMIT_HASH
ARG GIT_COMMIT_HASH_SHORT
ARG GIT_REMOTE_URL
ARG GIT_REMOTE_COMMIT_URL
ARG CONDUWUIT_VERSION_EXTRA
ARG CONTINUWUITY_VERSION_EXTRA
ENV GIT_COMMIT_HASH=$GIT_COMMIT_HASH
ENV GIT_COMMIT_HASH_SHORT=$GIT_COMMIT_HASH_SHORT
ENV GIT_REMOTE_URL=$GIT_REMOTE_URL
ENV GIT_REMOTE_COMMIT_URL=$GIT_REMOTE_COMMIT_URL
ENV CONDUWUIT_VERSION_EXTRA=$CONDUWUIT_VERSION_EXTRA
ENV CONTINUWUITY_VERSION_EXTRA=$CONTINUWUITY_VERSION_EXTRA

ARG RUST_PROFILE=release
ARG CARGO_FEATURES="default"

# Build the binary
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git/db \
    --mount=type=cache,target=/app/target,id=continuwuity-cargo-target-${TARGET_CPU}-${TARGETPLATFORM}-${RUST_PROFILE} \
    bash <<'EOF'
    set -o allexport
    set -o xtrace
    . /etc/environment

    # Check if http3 feature is enabled and set appropriate RUSTFLAGS
    if echo "${CARGO_FEATURES}" | grep -q "http3"; then
        export RUSTFLAGS="${RUSTFLAGS} --cfg reqwest_unstable"
    else
        export RUSTFLAGS="${RUSTFLAGS}"
    fi

    RUST_PROFILE_DIR="${RUST_PROFILE}"
    if [[ "${RUST_PROFILE}" == "dev" ]]; then
        RUST_PROFILE_DIR="debug"
    fi

    TARGET_DIR=($(cargo metadata --no-deps --format-version 1 | \
            jq -r ".target_directory"))
    mkdir /out/sbin
    PACKAGE=conduwuit
    xx-cargo build --locked --profile ${RUST_PROFILE} \
        --no-default-features --features ${CARGO_FEATURES} \
        -p $PACKAGE;
    BINARIES=($(cargo metadata --no-deps --format-version 1 | \
        jq -r ".packages[] | select(.name == \"$PACKAGE\") | .targets[] | select( .kind | map(. == \"bin\") | any ) | .name"))
    for BINARY in "${BINARIES[@]}"; do
        echo $BINARY
        xx-verify $TARGET_DIR/$(xx-cargo --print-target-triple)/${RUST_PROFILE_DIR}/$BINARY
        cp $TARGET_DIR/$(xx-cargo --print-target-triple)/${RUST_PROFILE_DIR}/$BINARY /out/sbin/$BINARY
    done
EOF

# Generate Software Bill of Materials (SBOM)
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git/db \
    bash <<'EOF'
    set -o xtrace
    mkdir /out/sbom
    if ! cargo sbom --help >/dev/null 2>&1; then
        echo "cargo-sbom is not installed; skipping SBOM generation"
        exit 0
    fi
    typeset -A PACKAGES
    for BINARY in /out/sbin/*; do
        BINARY_BASE=$(basename ${BINARY})
        package=$(cargo metadata --no-deps --format-version 1 | jq -r ".packages[] | select(.targets[] | select( .kind | map(. == \"bin\") | any ) | .name == \"$BINARY_BASE\") | .name")
        if [ -z "$package" ]; then
            continue
        fi
        PACKAGES[$package]=1
    done
    for PACKAGE in $(echo ${!PACKAGES[@]}); do
        echo $PACKAGE
        cargo sbom --cargo-package $PACKAGE > /out/sbom/$PACKAGE.spdx.json
    done
EOF

# Extract dynamically linked dependencies
RUN <<'DEPS_EOF'
    set -o xtrace
    mkdir /out/libs /out/libs-root

    # Process each binary
    for BINARY in /out/sbin/*; do
        if lddtree_output=$(lddtree "$BINARY" 2>/dev/null) && [ -n "$lddtree_output" ]; then
            echo "$lddtree_output" | awk '{print $(NF-0) " " $1}' | sort -u -k 1,1 | \
                awk '{dest = ($2 ~ /^\//) ? "/out/libs-root" $2 : "/out/libs/" $2; print "install -D " $1 " " dest}' | \
                while read cmd; do eval "$cmd"; done
        fi
    done

    # Show what will be copied to runtime
    echo "=== Libraries being copied to runtime image:"
    find /out/libs* -type f 2>/dev/null | sort || echo "No libraries found"
DEPS_EOF

FROM ubuntu:latest AS prepper

# Create layer structure
RUN mkdir -p /layer1/etc/ssl/certs \
             /layer2/usr/lib \
             /layer3/sbin /layer3/sbom

# Copy SSL certs and root-path libraries to layer1 (ultra-stable)
COPY --from=base /etc/ssl/certs /layer1/etc/ssl/certs
COPY --from=builder /out/libs-root/ /layer1/

# Copy application libraries to layer2 (semi-stable)
COPY --from=builder /out/libs/ /layer2/usr/lib/

# Copy binaries and SBOM to layer3 (volatile)
COPY --from=builder /out/sbin/ /layer3/sbin/
COPY --from=builder /out/sbom/ /layer3/sbom/

# Fix permissions after copying
RUN chmod -R 755 /layer1 /layer2 /layer3

FROM scratch

WORKDIR /

# Copy ultra-stable layer (SSL certs, system libraries)
COPY --from=prepper /layer1/ /

# Copy semi-stable layer (application libraries)
COPY --from=prepper /layer2/ /

# Copy volatile layer (binaries, SBOM)
COPY --from=prepper /layer3/ /

# Inform linker where to find libraries
ENV LD_LIBRARY_PATH=/usr/lib

# Continuwuity default port
EXPOSE 8008

CMD ["/sbin/conduwuit"]
