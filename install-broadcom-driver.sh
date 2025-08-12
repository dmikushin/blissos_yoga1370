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

# DEBUG: Check that headers exist
echo "Checking header files..."
ls -la /kernel-source/drivers/net/wireless/broadcom-wl/src/include/typedefs.h || echo "WARNING: typedefs.h not found!"

# NUCLEAR OPTION: Copy all headers to the same directories as .c files
echo "Copying headers to source directories..."

# Copy headers to shared directory where linux_osl.c is
cp /kernel-source/drivers/net/wireless/broadcom-wl/src/include/*.h \
   /kernel-source/drivers/net/wireless/broadcom-wl/src/shared/ 2>/dev/null || true

# Copy headers to wl/sys directory where other .c files are
cp /kernel-source/drivers/net/wireless/broadcom-wl/src/include/*.h \
   /kernel-source/drivers/net/wireless/broadcom-wl/src/wl/sys/ 2>/dev/null || true

# Also copy common includes if they exist
if [ -d /kernel-source/drivers/net/wireless/broadcom-wl/src/common/include ]; then
    cp /kernel-source/drivers/net/wireless/broadcom-wl/src/common/include/*.h \
       /kernel-source/drivers/net/wireless/broadcom-wl/src/shared/ 2>/dev/null || true
    cp /kernel-source/drivers/net/wireless/broadcom-wl/src/common/include/*.h \
       /kernel-source/drivers/net/wireless/broadcom-wl/src/wl/sys/ 2>/dev/null || true
fi

echo "Headers copied to source directories"

# Also fix include statements to use quotes instead of angle brackets
echo "Fixing include statements..."
find /kernel-source/drivers/net/wireless/broadcom-wl/src -name "*.c" -exec sed -i 's/#include <\([^>]*\)>/#include "\1"/g' {} \;
echo "Include statements fixed"

# Create simplified Makefile - headers are now in same dirs as sources
echo "Creating simplified Makefile..."
cat > /kernel-source/drivers/net/wireless/broadcom-wl/Makefile << 'EOF'
# Simplified Makefile for in-kernel build

# Debug: Show build variables
$(info === Building broadcom-wl driver ===)
$(info src = $(src))
$(info obj = $(obj)) 
$(info srctree = $(srctree))
$(info M = $(M))
$(info KBUILD_SRC = $(KBUILD_SRC))

# Handle both in-tree and out-of-tree builds
# For in-tree builds, src is relative to kernel root
# For out-of-tree builds, src might be empty or point to module dir
ifeq ($(src),)
  # If src is empty, we're likely in module build mode
  BCM_SRC := .
else
  # Normal kernel build
  BCM_SRC := $(src)
endif

# Include paths - use both relative and absolute
ccflags-y := -I$(BCM_SRC)/src/include
ccflags-y += -I$(BCM_SRC)/src/shared
ccflags-y += -I$(BCM_SRC)/src/wl/sys  
ccflags-y += -I$(BCM_SRC)/src/common/include
ccflags-y += -I$(BCM_SRC)/src/shared/bcmwifi/include
# Absolute paths as fallback
ccflags-y += -I$(srctree)/drivers/net/wireless/broadcom-wl/src/include
ccflags-y += -I$(srctree)/drivers/net/wireless/broadcom-wl/src/shared
ccflags-y += -I$(srctree)/drivers/net/wireless/broadcom-wl/src/wl/sys
# Last resort - hardcoded paths
ccflags-y += -I/kernel-source/drivers/net/wireless/broadcom-wl/src/include
ccflags-y += -I/kernel-source/drivers/net/wireless/broadcom-wl/src/shared
ccflags-y += -I/kernel-source/drivers/net/wireless/broadcom-wl/src/wl/sys
ccflags-y += -Wno-date-time
ccflags-y += -D__KERNEL__
ccflags-y += -DLINUX

# API selection
ifneq ($(CONFIG_CFG80211),)
  ccflags-y += -DUSE_CFG80211
  $(info Using CFG80211 API)
else
  ccflags-y += -DUSE_IW
  $(info Using Wireless Extension API)
endif

# Main target - use CONFIG_WLAN_VENDOR_BROADCOM_WL
obj-$(CONFIG_WLAN_VENDOR_BROADCOM_WL) += wl.o

# Define object files for built-in compilation
wl-y := src/shared/linux_osl.o
wl-y += src/wl/sys/wl_linux.o
wl-y += src/wl/sys/wl_iw.o
wl-y += src/wl/sys/wl_cfg80211_hybrid.o
wl-y += lib/wlc_hybrid.o

# Also define wl-objs for module build compatibility
wl-objs := $(wl-y)

# Debug: Show what we're building
$(info CONFIG_WLAN_VENDOR_BROADCOM_WL = $(CONFIG_WLAN_VENDOR_BROADCOM_WL))
$(info wl-y = $(wl-y))
$(info obj-y = $(obj-y))
$(info obj-m = $(obj-m))
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