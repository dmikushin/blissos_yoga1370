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

echo ""
echo "============================================="
echo "Checking BCM4352 driver integration..."
echo "============================================="

# Check if vmlinux contains BCM4352 driver symbols
if [ -f "/kernel-build/vmlinux" ]; then
    echo -n "Checking vmlinux for BCM4352 symbols... "
    BCM_SYMBOLS=$(nm /kernel-build/vmlinux 2>/dev/null | grep -E "wl_linux_|wl_cfg80211_|bcm_" | wc -l)
    if [ "$BCM_SYMBOLS" -gt 0 ]; then
        echo "✓ FOUND ($BCM_SYMBOLS symbols)"
        echo "Sample BCM4352 functions in vmlinux:"
        nm /kernel-build/vmlinux 2>/dev/null | grep -E "wl_linux_|wl_cfg80211_|bcm_" | head -5 | sed 's/^/  /'
    else
        echo "✗ NOT FOUND"
        echo "WARNING: BCM4352 driver symbols not found in vmlinux!"
    fi
else
    echo "Warning: vmlinux not found, skipping symbol check"
fi

# Check if System.map contains BCM4352 symbols
if [ -f "/kernel-build/System.map" ]; then
    echo -n "Checking System.map for BCM4352 symbols... "
    MAP_SYMBOLS=$(grep -E "wl_linux_|wl_cfg80211_|bcm_" /kernel-build/System.map 2>/dev/null | wc -l)
    if [ "$MAP_SYMBOLS" -gt 0 ]; then
        echo "✓ FOUND ($MAP_SYMBOLS symbols)"
        grep -E "wl_linux_|wl_cfg80211_|bcm_" /kernel-build/System.map 2>/dev/null | head -5 | sed 's/^/  /'
    else
        echo "✗ NOT FOUND"
    fi
fi

# Check if driver was built as module or built-in
echo ""
echo -n "Driver configuration: "
if grep -q "CONFIG_WLAN_VENDOR_BROADCOM_WL=y" /kernel-build/.config 2>/dev/null; then
    echo "BUILT-IN (=y)"
    if [ "$BCM_SYMBOLS" -eq 0 ]; then
        echo "ERROR: Driver configured as built-in but symbols not found in kernel!"
        echo "Please check the build logs for errors."
        exit 1
    fi
elif grep -q "CONFIG_WLAN_VENDOR_BROADCOM_WL=m" /kernel-build/.config 2>/dev/null; then
    echo "MODULE (=m)"
    # Check if module was actually built
    if [ -f "/kernel-build/drivers/net/wireless/broadcom-wl/wl.ko" ]; then
        echo "  Module found: /kernel-build/drivers/net/wireless/broadcom-wl/wl.ko"
        echo "  Module info:"
        modinfo /kernel-build/drivers/net/wireless/broadcom-wl/wl.ko 2>/dev/null | head -5 | sed 's/^/    /'
    else
        echo "  WARNING: Module wl.ko not found!"
    fi
else
    echo "NOT CONFIGURED"
    echo "ERROR: CONFIG_WLAN_VENDOR_BROADCOM_WL is not set in kernel config!"
    exit 1
fi

# Final summary
echo ""
echo "============================================="
if [ "$BCM_SYMBOLS" -gt 0 ] || [ -f "/kernel-build/drivers/net/wireless/broadcom-wl/wl.ko" ]; then
    echo "✓ BCM4352 driver build verification PASSED"
else
    echo "✗ BCM4352 driver build verification FAILED"
    echo "Driver was not successfully integrated into the kernel!"
    exit 1
fi
echo "============================================="