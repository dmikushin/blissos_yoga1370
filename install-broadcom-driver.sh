#!/bin/bash
set -e

echo "=== Installing Broadcom BCM4352 driver ==="

# Clone kernel source if not exists
if [ ! -f /kernel-source/Makefile ]; then
    echo "=== Downloading Linux kernel 6.9.9 ==="
    cd /tmp
    git clone --depth 1 --branch 6.9_xanmod https://github.com/android-generic/kernel-zenith.git kernel-tmp
    cp -r kernel-tmp/* /kernel-source/ 2>/dev/null || {
        echo "Cannot write to /kernel-source. Creating it on host..."
        exit 1
    }
    echo "=== Kernel source downloaded ==="
else
    echo "=== Using existing kernel source ==="
fi

# Copy broadcom-wl driver to kernel source
echo "=== Installing Broadcom BCM4352 driver ==="
mkdir -p /kernel-source/drivers/net/wireless/

if [ ! -d /drivers/broadcom-wl ]; then
    echo "ERROR: /drivers/broadcom-wl not found!"
    ls -la /drivers/
    exit 1
fi

echo "Copying driver to kernel source..."
cp -r /drivers/broadcom-wl /kernel-source/drivers/net/wireless/

# Verify copy worked
if [ ! -d /kernel-source/drivers/net/wireless/broadcom-wl ]; then
    echo "ERROR: Failed to copy driver!"
    exit 1
fi

# Fix the precompiled object file
echo "Preparing precompiled object..."
cp /kernel-source/drivers/net/wireless/broadcom-wl/lib/wlc_hybrid.o_shipped \
   /kernel-source/drivers/net/wireless/broadcom-wl/lib/wlc_hybrid.o

# Create simplified Makefile with correct include paths
echo "Creating fixed Makefile..."
cat > /kernel-source/drivers/net/wireless/broadcom-wl/Makefile << 'EOF'
# Simplified Makefile for in-kernel build
# Include paths MUST be first
ccflags-y := -I$(src)/src/include
ccflags-y += -I$(src)/src/common/include
ccflags-y += -I$(src)/src/wl/sys
ccflags-y += -I$(src)/src/wl/phy
ccflags-y += -I$(src)/src/wl/ppr/include
ccflags-y += -I$(src)/src/shared/bcmwifi/include
ccflags-y += -Wno-date-time

# API selection
ifneq ($(CONFIG_CFG80211),)
  ccflags-y += -DUSE_CFG80211
else
  ccflags-y += -DUSE_IW
endif

# Main target
obj-$(CONFIG_WLAN_VENDOR_BROADCOM_WL) += wl.o

# Define object files for both built-in and module
wl-y := src/shared/linux_osl.o
wl-y += src/wl/sys/wl_linux.o
wl-y += src/wl/sys/wl_iw.o
wl-y += src/wl/sys/wl_cfg80211_hybrid.o
wl-y += lib/wlc_hybrid.o

# Also define for module build
wl-objs := $(wl-y)

# Force compilation even if nothing depends on it
always-y := wl.o
EOF

echo "=== Integrating driver into kernel build system ==="

# Add to Kconfig if needed
if ! grep -q 'source "drivers/net/wireless/broadcom-wl/Kconfig"' /kernel-source/drivers/net/wireless/Kconfig 2>/dev/null; then
    echo "Adding broadcom-wl to Kconfig..."
    echo 'source "drivers/net/wireless/broadcom-wl/Kconfig"' >> /kernel-source/drivers/net/wireless/Kconfig
fi

# Clean and add to Makefile
echo "Cleaning old entries from Makefile..."
sed -i '/broadcom-wl/d' /kernel-source/drivers/net/wireless/Makefile

echo "Adding broadcom-wl to Makefile..."
echo 'obj-$(CONFIG_WLAN_VENDOR_BROADCOM_WL) += broadcom-wl/' >> /kernel-source/drivers/net/wireless/Makefile

# Verify
echo "=== Verification ==="
echo "Makefile contains:"
grep 'broadcom-wl' /kernel-source/drivers/net/wireless/Makefile || echo "ERROR: Not in Makefile!"
echo "Kconfig contains:"
grep 'broadcom-wl' /kernel-source/drivers/net/wireless/Kconfig || echo "ERROR: Not in Kconfig!"

echo "=== Driver installation complete ==="