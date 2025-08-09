# BCM4352 Kernel Builder for BlissOS

Custom Linux kernel 6.9.9 build with integrated Broadcom BCM4352 wireless driver for BlissOS/Android-x86.

## Features

- Linux kernel 6.9.9 with BlissOS configuration
- Integrated Broadcom BCM4352 (802.11ac) wireless driver
- Clang/LLVM toolchain (Android r498229b)
- Docker-based reproducible builds
- Automatic kernel source download

## Project Structure

```
bcm4352-kernel-builder/
├── .gitignore
├── README.md
├── Dockerfile                    # Build container with Clang toolchain
├── docker-compose.yml            # Build orchestration
├── build-kernel.sh               # Kernel build script
├── kernel.config                 # BlissOS kernel configuration
└── drivers/
    └── broadcom-wl/              # BCM4352 driver with fixes
        ├── Makefile              # Fixed to handle .cmd files
        ├── Kconfig               # Driver configuration
        ├── src/                  # Driver source code
        └── lib/
            └── wlc_hybrid.o_shipped  # Proprietary binary blob
```

## Prerequisites

- Docker and Docker Compose
- ~15GB free disk space
- 8GB+ RAM recommended

## Building

1. Clone this repository:
```bash
git clone https://github.com/yourusername/bcm4352-kernel-builder.git
cd bcm4352-kernel-builder
```

2. Build the kernel:
```bash
docker-compose up kernel-builder
```

The build process will:
- Download Linux kernel 6.9.9 source (if not present)
- Apply BlissOS kernel configuration
- Install Broadcom BCM4352 driver with fixes
- Build kernel with integrated wireless support

## Build Output

After successful build, you'll find:
- **Kernel image**: `kernel-build-xanmod/arch/x86/boot/bzImage`
- **Kernel copy**: `kernel-build-xanmod/kernel`
- **Modules**: `kernel-build-xanmod/drivers/net/wireless/broadcom-wl/wl.ko`

## Build Information

- **Kernel Version**: 6.9.9-zenith
- **Compiler**: Android clang version 17.0.4 (r498229b)
- **Build flags**: +pgo, +bolt, +lto, +mlgo
- **Original config**: BlissOS kernel configuration

## Configuration

### Environment Variables (docker-compose.yml)
- `KERNEL_VERSION`: Kernel version (default: 6.9.9)
- `KERNEL_LOCALVERSION`: Local version string (default: -zenith)
- `KBUILD_BUILD_USER`: Build user name (default: jack)
- `KBUILD_BUILD_HOST`: Build host name (default: orion)
- `JOBS`: Parallel build jobs (default: 8)

### Wireless Driver Configuration
The Broadcom driver is automatically configured with:
```
CONFIG_WLAN_VENDOR_BROADCOM=y
CONFIG_WL=m
CONFIG_CFG80211=y
CONFIG_MAC80211=y
```

## Troubleshooting

### Build fails with ".cmd file not found"
This has been fixed in our Makefile. The fix automatically creates `.cmd` files for precompiled objects.

### Out of disk space
The build requires ~15GB:
- Kernel source: ~2GB
- Build artifacts: ~10GB
- Docker image: ~3GB

Clean build artifacts:
```bash
rm -rf kernel-build-xanmod/*
docker-compose down
docker volume prune
```

### Kernel source download fails
If automatic download fails, manually clone:
```bash
git clone --depth 1 --branch v6.9.9 https://github.com/torvalds/linux.git kernel-source-xanmod
```

## Testing

To test the built kernel in QEMU:
```bash
qemu-system-x86_64 \
  -kernel kernel-build-xanmod/arch/x86/boot/bzImage \
  -initrd /path/to/initrd.img \
  -drive file=/path/to/system.img,format=raw,if=virtio \
  -m 2G \
  -append "console=ttyS0,115200 root=/dev/vda" \
  -serial mon:stdio \
  -nographic
```

## Clean Rebuild

For a complete clean rebuild:
```bash
# Remove build artifacts
rm -rf kernel-build-xanmod/*

# Remove kernel source (will be re-downloaded)
rm -rf kernel-source-xanmod/*

# Rebuild
docker-compose up kernel-builder
```

## License

- Linux kernel: GPLv2
- Broadcom driver: Proprietary (see `drivers/broadcom-wl/lib/LICENSE.txt`)
- Build scripts: MIT

## Credits

- BlissOS team for kernel configuration
- Broadcom for wireless driver
- Linux kernel developers
- Android Clang/LLVM team