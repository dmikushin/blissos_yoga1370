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

# Verify driver is properly integrated in kernel source
echo "Verifying broadcom-wl driver integration..."
if [ ! -d "/kernel-source/drivers/net/wireless/broadcom-wl" ]; then
    echo "ERROR: broadcom-wl driver not found in kernel source!"
    echo "Expected at: /kernel-source/drivers/net/wireless/broadcom-wl"
    exit 1
fi

if ! grep -q "broadcom-wl/Kconfig" /kernel-source/drivers/net/wireless/Kconfig; then
    echo "ERROR: broadcom-wl not integrated in Kconfig!"
    echo "Missing: source \"drivers/net/wireless/broadcom-wl/Kconfig\""
    exit 1
fi

if ! grep -q "CONFIG_WLAN_VENDOR_BROADCOM_WL.*broadcom-wl" /kernel-source/drivers/net/wireless/Makefile; then
    echo "ERROR: broadcom-wl not integrated in Makefile!"
    echo "Missing: obj-\$(CONFIG_WLAN_VENDOR_BROADCOM_WL) += broadcom-wl/"
    exit 1
fi
echo "✓ Driver properly integrated in kernel source"

# Enable Broadcom WL driver for BCM4352
echo "Adding Broadcom BCM4352 wireless support to config..."
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

# Verify that CONFIG_WLAN_VENDOR_BROADCOM_WL is set correctly after olddefconfig
echo "Verifying BCM4352 driver configuration..."
if grep -q "CONFIG_WLAN_VENDOR_BROADCOM_WL=y" /kernel-build/.config; then
    echo "✓ Driver configured as built-in (=y)"
elif grep -q "CONFIG_WLAN_VENDOR_BROADCOM_WL=m" /kernel-build/.config; then
    echo "⚠ Driver configured as module (=m)"
    echo "Forcing built-in configuration..."
    sed -i 's/CONFIG_WLAN_VENDOR_BROADCOM_WL=m/CONFIG_WLAN_VENDOR_BROADCOM_WL=y/' /kernel-build/.config
    echo "✓ Changed to built-in (=y)"
elif grep -q "# CONFIG_WLAN_VENDOR_BROADCOM_WL is not set" /kernel-build/.config; then
    echo "✗ ERROR: Driver was disabled by olddefconfig!"
    echo "Forcing configuration..."
    sed -i 's/# CONFIG_WLAN_VENDOR_BROADCOM_WL is not set/CONFIG_WLAN_VENDOR_BROADCOM_WL=y/' /kernel-build/.config
    # Also ensure dependencies are met
    grep -q "CONFIG_PCI=y" /kernel-build/.config || echo "CONFIG_PCI=y" >> /kernel-build/.config
    grep -q "CONFIG_CFG80211" /kernel-build/.config || echo "CONFIG_CFG80211=y" >> /kernel-build/.config
    echo "✓ Forced to built-in (=y)"
else
    echo "✗ ERROR: CONFIG_WLAN_VENDOR_BROADCOM_WL not found in .config!"
    echo "Adding it manually..."
    echo "CONFIG_WLAN_VENDOR_BROADCOM_WL=y" >> /kernel-build/.config
fi

# Run olddefconfig again to validate our changes
echo "Validating configuration..."
make -C /kernel-source O=/kernel-build HOSTCC=clang CC=clang LLVM=1 olddefconfig

# Final check
if ! grep -q "CONFIG_WLAN_VENDOR_BROADCOM_WL=y\|CONFIG_WLAN_VENDOR_BROADCOM_WL=m" /kernel-build/.config; then
    echo "CRITICAL ERROR: Unable to enable CONFIG_WLAN_VENDOR_BROADCOM_WL!"
    echo "Check that dependencies (PCI, CFG80211) are met."
    grep "CONFIG_PCI\|CONFIG_CFG80211" /kernel-build/.config | head -5
    exit 1
fi

# Set build flags matching original build
export KBUILD_BUILD_USER="jack"
export KBUILD_BUILD_HOST="orion"
export KBUILD_BUILD_TIMESTAMP="Mon Jul 15 08:34:16 EDT 2024"

# Compiler flags from original build
export KCFLAGS="-O3 -march=native -pipe"
export KCPPFLAGS="-O3 -march=native -pipe"

# DEBUG: Check broadcom-wl in source before build
echo "DEBUG: Checking broadcom-wl in kernel source before build:"
ls -la /kernel-source/drivers/net/wireless/broadcom-wl 2>/dev/null | head -5 || echo "  broadcom-wl NOT in source!"

# Build with clang and LTO
echo "Starting kernel build..."
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

# DEBUG: Check if broadcom-wl was processed during build
echo "DEBUG: Checking if broadcom-wl directory was created in build:"
ls -la /kernel-build/drivers/net/wireless/ | grep broadcom || echo "  No broadcom directories in build output!"

echo ""
echo "============================================="
echo "CRITICAL VERIFICATION: BCM4352 COMPILATION"
echo "============================================="

# THE ONLY CHECKS THAT MATTER:

# 1. Check specific object files that MUST exist if driver compiled
echo "Checking for REQUIRED object files:"
REQUIRED_FILES=(
    "/kernel-build/drivers/net/wireless/broadcom-wl/src/wl/sys/wl_linux.o"
    "/kernel-build/drivers/net/wireless/broadcom-wl/src/wl/sys/wl_cfg80211_hybrid.o"
    "/kernel-build/drivers/net/wireless/broadcom-wl/src/shared/linux_osl.o"
)

FAILED=0
for file in "${REQUIRED_FILES[@]}"; do
    if [ -f "$file" ]; then
        size=$(stat -c%s "$file" 2>/dev/null || echo "0")
        if [ "$size" -gt 1000 ]; then
            echo "  ✓ $file ($(ls -lh "$file" | awk '{print $5}'))"
        else
            echo "  ✗ $file exists but EMPTY or TINY!"
            FAILED=1
        fi
    else
        echo "  ✗ MISSING: $file"
        FAILED=1
    fi
done

if [ $FAILED -eq 1 ]; then
    echo ""
    echo "❌❌❌ BROADCOM-WL WAS NOT COMPILED! ❌❌❌"
    echo ""
    echo "Checking what exists in broadcom-wl directory:"
    if [ -d "/kernel-build/drivers/net/wireless/broadcom-wl" ]; then
        find /kernel-build/drivers/net/wireless/broadcom-wl -type f -name "*.o" -o -name "*.ko" -o -name "*.a" 2>/dev/null | while read f; do
            echo "  $(ls -lh "$f" 2>/dev/null)"
        done
    else
        echo "  Directory doesn't even exist!"
    fi
    exit 1
fi

# 2. For built-in: Check wl.o or built-in.a
if grep -q "CONFIG_WLAN_VENDOR_BROADCOM_WL=y" /kernel-build/.config; then
    echo ""
    echo "Checking for built-in driver object:"
    if [ -f "/kernel-build/drivers/net/wireless/broadcom-wl/wl.o" ]; then
        size=$(stat -c%s "/kernel-build/drivers/net/wireless/broadcom-wl/wl.o" 2>/dev/null || echo "0")
        if [ "$size" -gt 1000000 ]; then  # Should be > 1MB
            echo "  ✓ wl.o found ($(ls -lh /kernel-build/drivers/net/wireless/broadcom-wl/wl.o | awk '{print $5}'))"
        else
            echo "  ✗ wl.o exists but too small!"
            exit 1
        fi
    elif [ -f "/kernel-build/drivers/net/wireless/broadcom-wl/built-in.a" ]; then
        size=$(stat -c%s "/kernel-build/drivers/net/wireless/broadcom-wl/built-in.a" 2>/dev/null || echo "0")
        if [ "$size" -gt 1000000 ]; then  # Should be > 1MB
            echo "  ✓ built-in.a found ($(ls -lh /kernel-build/drivers/net/wireless/broadcom-wl/built-in.a | awk '{print $5}'))"
        else
            echo "  ✗ built-in.a exists but too small!"
            exit 1
        fi
    else
        echo "  ✗ Neither wl.o nor built-in.a found!"
        echo "  ❌ DRIVER NOT BUILT INTO KERNEL!"
        exit 1
    fi
fi

echo ""
echo "✅ BROADCOM-WL SUCCESSFULLY COMPILED!"
echo "============================================="

# REMOVED vmlinux and System.map checks - they are UNRELIABLE

