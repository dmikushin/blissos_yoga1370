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

# CRITICAL: Check if broadcom-wl was actually compiled
echo -n "Checking if broadcom-wl was compiled... "
if [ -d "/kernel-build/drivers/net/wireless/broadcom-wl" ]; then
    WL_OBJECTS=$(find /kernel-build/drivers/net/wireless/broadcom-wl -name "*.o" 2>/dev/null | wc -l)
    if [ "$WL_OBJECTS" -gt 0 ]; then
        echo "✓ FOUND ($WL_OBJECTS object files)"
        find /kernel-build/drivers/net/wireless/broadcom-wl -name "*.o" -exec ls -lh {} \; | head -5 | sed 's/^/  /'
    else
        echo "✗ FAILED - NO OBJECT FILES!"
        echo "ERROR: broadcom-wl directory exists but contains no compiled objects!"
        echo "The driver was NOT compiled. Check that:"
        echo "  1. CONFIG_WLAN_VENDOR_BROADCOM_WL is set in .config"
        echo "  2. The Makefile in drivers/net/wireless/ includes broadcom-wl"
        echo "  3. The driver source files are valid"
        ls -la /kernel-build/drivers/net/wireless/broadcom-wl/ 2>/dev/null | head -10
        exit 1
    fi
else
    echo "✗ CRITICAL FAILURE!"
    echo "ERROR: /kernel-build/drivers/net/wireless/broadcom-wl directory does not exist!"
    echo "The driver was completely skipped during kernel build!"
    echo ""
    echo "Checking what's in drivers/net/wireless/:"
    ls -la /kernel-build/drivers/net/wireless/ | grep -E "broadcom|wl" || echo "No broadcom directories found!"
    echo ""
    echo "Checking kernel source:"
    ls -la /kernel-source/drivers/net/wireless/ | grep -E "broadcom|wl" || echo "No broadcom directories found!"
    exit 1
fi

# Check if vmlinux contains BCM4352 driver symbols
if [ -f "/kernel-build/vmlinux" ]; then
    echo -n "Checking vmlinux for broadcom-wl specific symbols... "
    # Look for symbols specific to the broadcom-wl driver:
    # wl_pci_probe, wl_attach, wl_module_init, wl_ioctl, wl_cfg80211_* functions
    BCM_SYMBOLS=$(nm /kernel-build/vmlinux 2>/dev/null | grep -E " [tT] (wl_pci_probe|wl_attach|wl_module_init|wl_ioctl|wl_cfg80211_attach|wl_cfg80211_detach|wl_open|wl_close|wl_start|wl_free)" | wc -l)
    if [ "$BCM_SYMBOLS" -gt 0 ]; then
        echo "✓ FOUND ($BCM_SYMBOLS symbols)"
        echo "Sample broadcom-wl driver functions in vmlinux:"
        nm /kernel-build/vmlinux 2>/dev/null | grep -E " [tT] (wl_pci_probe|wl_attach|wl_module_init|wl_ioctl|wl_cfg80211_attach|wl_cfg80211_detach|wl_open|wl_close|wl_start|wl_free)" | head -5 | sed 's/^/  /'
    else
        echo "✗ NOT FOUND"
        echo "WARNING: broadcom-wl driver symbols not found in vmlinux!"
        echo "Looking for any 'wl_' symbols as fallback:"
        nm /kernel-build/vmlinux 2>/dev/null | grep " [tT] wl_" | head -5 | sed 's/^/  /'
    fi
else
    echo "Warning: vmlinux not found, skipping symbol check"
fi

# Check if System.map contains broadcom-wl symbols
if [ -f "/kernel-build/System.map" ]; then
    echo -n "Checking System.map for broadcom-wl symbols... "
    MAP_SYMBOLS=$(grep -E " [tT] (wl_pci_probe|wl_attach|wl_module_init|wl_ioctl|wl_cfg80211_attach|wl_cfg80211_detach|wl_open|wl_close|wl_start|wl_free)" /kernel-build/System.map 2>/dev/null | wc -l)
    if [ "$MAP_SYMBOLS" -gt 0 ]; then
        echo "✓ FOUND ($MAP_SYMBOLS symbols)"
        grep -E " [tT] (wl_pci_probe|wl_attach|wl_module_init|wl_ioctl|wl_cfg80211_attach|wl_cfg80211_detach|wl_open|wl_close|wl_start|wl_free)" /kernel-build/System.map 2>/dev/null | head -5 | sed 's/^/  /'
    else
        echo "✗ NOT FOUND"
        echo "Checking for any wl_ symbols:"
        grep " [tT] wl_" /kernel-build/System.map 2>/dev/null | head -5 | sed 's/^/  /' || echo "  No wl_ symbols found at all!"
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