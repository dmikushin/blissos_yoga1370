FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install basic build dependencies
# Note: Some packages may pull in gcc as dependency, we'll remove it after
RUN apt-get update && apt-get install -y \
    make \
    bc \
    bison \
    flex \
    libssl-dev \
    libelf-dev \
    wget \
    git \
    curl \
    ca-certificates \
    python3 \
    python3-pip \
    cpio \
    rsync \
    kmod \
    libncurses5-dev \
    lz4 \
    zstd \
    zip \
    unzip \
    && apt-get remove -y gcc g++ cpp && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# Download EXACT Android Clang toolchain r498229b
# Using sparse checkout to get only the specific clang version
RUN apt-get update && apt-get install -y git-lfs && \
    git clone --filter=blob:none --sparse \
    https://android.googlesource.com/platform/prebuilts/clang/host/linux-x86 \
    /tmp/clang-repo && \
    cd /tmp/clang-repo && \
    git sparse-checkout set clang-r498229b && \
    git checkout ba7da711271d310dda6b5134d8f4448f6a276a27 && \
    mv clang-r498229b /opt/clang && \
    cd / && \
    rm -rf /tmp/clang-repo && \
    apt-get remove -y git-lfs && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/*

# Set up environment variables for the toolchain
ENV PATH="/opt/clang/bin:${PATH}"
ENV CLANG_TRIPLE=x86_64-linux-gnu
ENV CROSS_COMPILE=x86_64-linux-gnu-
ENV CC=clang
ENV CXX=clang++
ENV AR=llvm-ar
ENV NM=llvm-nm
ENV OBJCOPY=llvm-objcopy
ENV OBJDUMP=llvm-objdump
ENV STRIP=llvm-strip
ENV LD=ld.lld

# Verify toolchain setup and configure cc using update-alternatives
RUN echo "=== Verifying toolchain setup ===" && \
    which clang && clang --version && \
    echo "=== Checking for gcc (should NOT be found) ===" && \
    ! which gcc && echo "✓ gcc is not installed" || echo "⚠ gcc found, will be overridden" && \
    echo "=== Setting up cc/c++ alternatives ===" && \
    update-alternatives --install /usr/bin/cc cc /opt/clang/bin/clang 100 && \
    update-alternatives --install /usr/bin/c++ c++ /opt/clang/bin/clang++ 100 && \
    update-alternatives --set cc /opt/clang/bin/clang && \
    update-alternatives --set c++ /opt/clang/bin/clang++ && \
    echo "=== Verifying cc points to clang ===" && \
    cc --version 2>&1 | head -1 && \
    echo "✓ cc configured via update-alternatives" && \
    echo "=== All checks passed ==="

# Create build directories
RUN mkdir -p /kernel-source /kernel-build

WORKDIR /kernel-build

# Build scripts
COPY build-kernel.sh /usr/local/bin/
COPY install-broadcom-driver.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/build-kernel.sh /usr/local/bin/install-broadcom-driver.sh

CMD ["/usr/local/bin/build-kernel.sh"]
