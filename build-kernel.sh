#!/bin/bash
set -e

echo "Starting kernel build for BlissOS 6.9.9-zenith"

# Check if source exists
if [ ! -f "/kernel-source/Makefile" ]; then
    echo "Error: Kernel source not found in /kernel-source"
    echo "Please ensure kernel source is cloned to ./kernel-source-xanmod/"
    exit 1
fi

# Clean the build directory
echo "Cleaning build directory..."
rm -rf /kernel-build/*

# Use the kernel config from BlissOS as base
if [ -f "/config/kernel.config" ]; then
    echo "Using BlissOS kernel config as base"
    cp /config/kernel.config /kernel-build/.config
else
    echo "Error: No kernel config found at /config/kernel.config"
    echo "Please copy your kernel config to ./kernel.config"
    exit 1
fi

# Enable Broadcom WL driver for BCM4352
echo "Adding Broadcom BCM4352 wireless support..."
cat >> /kernel-build/.config << EOF

# Broadcom BCM4352 wireless configuration
CONFIG_WLAN_VENDOR_BROADCOM=y
CONFIG_WLAN_VENDOR_BROADCOM_WL=y
CONFIG_WL=y
CONFIG_CFG80211=y
CONFIG_MAC80211=y
CONFIG_MAC80211_HAS_RC=y
CONFIG_MAC80211_RC_MINSTREL=y
CONFIG_MAC80211_RC_DEFAULT_MINSTREL=y
CONFIG_MAC80211_RC_DEFAULT="minstrel_ht"
EOF

# Update config with current build environment
echo "Updating config for current build environment..."
make -C /kernel-source O=/kernel-build HOSTCC=clang CC=clang LLVM=1 olddefconfig

# Set build flags matching original build
export KBUILD_BUILD_USER="jack"
export KBUILD_BUILD_HOST="orion"
export KBUILD_BUILD_TIMESTAMP="Mon Jul 15 08:34:16 EDT 2024"

# Compiler flags from original build
export KCFLAGS="-O3 -march=native -pipe"
export KCPPFLAGS="-O3 -march=native -pipe"

# Build with clang and LTO
make -C /kernel-source \
    O=/kernel-build \
    CC=clang \
    HOSTCC=clang \
    HOSTCXX=clang++ \
    LD=ld.lld \
    HOSTLD=ld.lld \
    AR=llvm-ar \
    NM=llvm-nm \
    STRIP=llvm-strip \
    OBJCOPY=llvm-objcopy \
    OBJDUMP=llvm-objdump \
    LLVM=1 \
    LLVM_IAS=1 \
    -j$(nproc) \
    bzImage modules

echo "Build completed successfully!"
echo "Kernel image: /kernel-build/arch/x86/boot/bzImage"
echo "Modules in: /kernel-build/"