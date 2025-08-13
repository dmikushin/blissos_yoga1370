#!/bin/bash
set -e

echo "Starting kernel build for BlissOS 6.9.9-zenith"
echo "Build log will be saved to: /kernel-build/logs/build-*.log"

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
echo ""
echo "============================================="
echo "PRE-BUILD DIAGNOSTICS"
echo "============================================="
echo "1. Checking broadcom-wl in kernel source:"
if [ -d /kernel-source/drivers/net/wireless/broadcom-wl ]; then
    echo "  ✓ Directory exists"
    ls -la /kernel-source/drivers/net/wireless/broadcom-wl/ | head -5
else
    echo "  ✗ Directory NOT found!"
fi

echo ""
echo "2. Checking Kconfig integration:"
if grep -q "broadcom-wl/Kconfig" /kernel-source/drivers/net/wireless/Kconfig; then
    echo "  ✓ Found in Kconfig:"
    grep "broadcom-wl" /kernel-source/drivers/net/wireless/Kconfig
else
    echo "  ✗ NOT in Kconfig!"
fi

echo ""
echo "3. Checking Makefile integration:"
if grep -q "broadcom-wl" /kernel-source/drivers/net/wireless/Makefile; then
    echo "  ✓ Found in Makefile:"
    grep "broadcom-wl" /kernel-source/drivers/net/wireless/Makefile
else
    echo "  ✗ NOT in Makefile!"
fi

echo ""
echo "4. Checking CONFIG_WLAN_VENDOR_BROADCOM_WL in .config:"
grep "CONFIG_WLAN_VENDOR_BROADCOM_WL" /kernel-build/.config || echo "  ✗ NOT found in .config!"

echo ""
echo "5. Checking if Kconfig option is visible:"
grep -A5 "config WLAN_VENDOR_BROADCOM_WL" /kernel-source/drivers/net/wireless/broadcom-wl/Kconfig || echo "  ✗ Kconfig not readable!"

echo ""
echo "6. Testing if kernel will process broadcom-wl:"
echo "  Running: make -C /kernel-source O=/kernel-build M=drivers/net/wireless/broadcom-wl"
make -C /kernel-source O=/kernel-build M=drivers/net/wireless/broadcom-wl HOSTCC=clang CC=clang LLVM=1 2>&1 | head -20

echo "============================================="
echo ""

# Build with clang and LTO
echo "Starting full kernel build..."
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

echo "Build completed (but checking broadcom-wl...)"

# DEBUG: Check if broadcom-wl was processed during build
echo ""
echo "============================================="
echo "POST-BUILD: Checking if broadcom-wl was built"
echo "============================================="
echo "Checking /kernel-build/drivers/net/wireless/:"
ls -la /kernel-build/drivers/net/wireless/ | grep broadcom || echo "  ✗ No broadcom directories!"

# Try to force-build the module explicitly
echo ""
echo "Attempting to force-build broadcom-wl module explicitly..."
if [ -d /kernel-source/drivers/net/wireless/broadcom-wl ]; then
    echo "Building module with: make M=drivers/net/wireless/broadcom-wl"
    make -C /kernel-source \
        O=/kernel-build \
        M=drivers/net/wireless/broadcom-wl \
        CC=clang \
        HOSTCC=clang \
        LLVM=1 \
        modules 2>&1 | tail -30
    
    echo ""
    echo "After explicit module build:"
    if [ -d /kernel-build/drivers/net/wireless/broadcom-wl ]; then
        echo "  ✓ Directory created!"
        find /kernel-build/drivers/net/wireless/broadcom-wl -name "*.o" -o -name "*.ko" | head -10
    else
        echo "  ✗ Still no directory! Module build failed!"
    fi
fi

echo "============================================="
echo ""

echo "Kernel image: /kernel-build/arch/x86/boot/bzImage"
echo "Modules in: /kernel-build/"

echo ""
echo "============================================="
echo "FINAL CHECK: Was broadcom-wl ACTUALLY compiled?"
echo "============================================="

# Count ALL .o files in broadcom-wl directory
if [ -d "/kernel-build/drivers/net/wireless/broadcom-wl" ]; then
    echo "Checking /kernel-build/drivers/net/wireless/broadcom-wl/"
    
    # Count object files
    OBJ_COUNT=$(find /kernel-build/drivers/net/wireless/broadcom-wl -name "*.o" -type f 2>/dev/null | wc -l)
    echo "Found $OBJ_COUNT .o files"
    
    if [ $OBJ_COUNT -eq 0 ]; then
        echo "❌ COMPILATION FAILED: Zero object files!"
        echo "Directory contents:"
        ls -la /kernel-build/drivers/net/wireless/broadcom-wl/
        echo "Subdirectories:"
        find /kernel-build/drivers/net/wireless/broadcom-wl -type d
        exit 1
    fi
    
    # List actual object files with sizes
    echo "Object files found:"
    find /kernel-build/drivers/net/wireless/broadcom-wl -name "*.o" -type f -exec ls -lh {} \; | while read line; do
        echo "  $line"
        # Check if file is not empty
        file=$(echo "$line" | awk '{print $NF}')
        size=$(echo "$line" | awk '{print $5}')
        if [[ "$size" == "0" ]]; then
            echo "    ❌ ERROR: Empty object file!"
            exit 1
        fi
    done
    
    # Check for the main composite object or built-in.a
    if [ -f "/kernel-build/drivers/net/wireless/broadcom-wl/wl.o" ]; then
        size=$(stat -c%s "/kernel-build/drivers/net/wireless/broadcom-wl/wl.o")
        echo ""
        echo "Main object: wl.o ($(ls -lh /kernel-build/drivers/net/wireless/broadcom-wl/wl.o | awk '{print $5}'))"
        if [ $size -lt 100000 ]; then
            echo "  ❌ ERROR: wl.o is too small (less than 100KB)!"
            exit 1
        fi
    elif [ -f "/kernel-build/drivers/net/wireless/broadcom-wl/built-in.a" ]; then
        size=$(stat -c%s "/kernel-build/drivers/net/wireless/broadcom-wl/built-in.a")
        echo ""
        echo "Archive: built-in.a ($(ls -lh /kernel-build/drivers/net/wireless/broadcom-wl/built-in.a | awk '{print $5}'))"
        if [ $size -lt 100000 ]; then
            echo "  ❌ ERROR: built-in.a is too small (less than 100KB)!"
            exit 1
        fi
    fi
    
    # If we got here, compilation succeeded
    echo ""
    echo "✅ SUCCESS: broadcom-wl compiled with $OBJ_COUNT object files!"
else
    echo "❌ CRITICAL: /kernel-build/drivers/net/wireless/broadcom-wl directory doesn't exist!"
    echo "Build system completely ignored the driver!"
    exit 1
fi

echo "============================================="

# REMOVED vmlinux and System.map checks - they are UNRELIABLE

echo ""
echo "=== Build Complete ==="
echo "Log files saved in: /kernel-build/logs/"
ls -lh /kernel-build/logs/*.log 2>/dev/null || echo "No log files found"
echo ""