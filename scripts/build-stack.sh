#!/usr/bin/env bash
#
# build-stack.sh - build the FVP boot stack for the Mali fuzzing lab.
#
# Reference decision (2026): upstream TF-A/U-Boot dropped the 'aemfvp-a' board,
# so the stack is the modern TF-A 'fvp' platform with the kernel as BL33:
#
#   BL1/BL2/BL31 (TF-A fvp) -> Linux kernel Image (BL33) -> BusyBox initramfs
#
#   FVP flash:  bl1.bin via bp.secureflashloader, fip.bin via bp.flashloader0
#   RAM layout: Image@0x80080000, DT@0x82000000, initramfs@0x84000000
#
# Produces, under --out (default out/fvp-stack/):
#   bl1.bin, fip.bin       TF-A fvp, ARM_LINUX_KERNEL_AS_BL33=1
#   rootfs/                busybox root filesystem staging dir
#   rootfs.cpio.gz         initramfs with mali_kbase.ko bundled
#   stack.json             build summary (for run-fvp.sh)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$REPO_ROOT/out"

OUT="$OUT_DIR/fvp-stack"
DRIVER="r56"
JOBS="$(nproc)"
SKIP_TFA=0
SKIP_BUSYBOX=0
SKIP_ROOTFS=0

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '[build-stack] %s\n' "$*"; }

usage() {
	cat <<'EOF'
Usage: build-stack.sh [options]

Options:
  --driver <r41|r56>   Which driver artifacts to bundle (default: r56).
  --out DIR            Output dir (default: out/fvp-stack).
  --jobs N             make -j N.
  --image FILE         Kernel Image for TF-A BL33 (default: out/<driver>/Image).
  --mali-ko FILE       mali_kbase.ko to bundle (default: out/<driver>/mali_kbase.ko).
  --skip-tf-a          Skip the TF-A build (firmware must already be present).
  --skip-busybox       Skip the busybox build.
  --skip-rootfs        Skip initramfs packaging.
  -h, --help           Show this help.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--driver)      DRIVER="${2:-}"; shift 2 ;;
		--out)         OUT="${2:-}";    shift 2 ;;
		--jobs)        JOBS="${2:-}";   shift 2 ;;
		--image)       KIMAGE="${2:-}"; shift 2 ;;
		--mali-ko)     MALI_KO="${2:-}"; shift 2 ;;
		--skip-tf-a)   SKIP_TFA=1; shift ;;
		--skip-busybox) SKIP_BUSYBOX=1; shift ;;
		--skip-rootfs) SKIP_ROOTFS=1; shift ;;
		-h|--help)     usage; exit 0 ;;
		*) die "unknown argument: $1 (try --help)" ;;
	esac
done

case "$DRIVER" in r41|r56) ;; *) die "unknown --driver '$DRIVER' (r41|r56)" ;; esac

KIMAGE="${KIMAGE:-$OUT_DIR/$DRIVER/Image}"
MALI_KO="${MALI_KO:-$OUT_DIR/$DRIVER/mali_kbase.ko}"
[ -f "$KIMAGE" ] || die "kernel Image not found: $KIMAGE (run build-kernel.sh --driver $DRIVER first)"
[ -f "$MALI_KO" ] || die "mali_kbase.ko not found: $MALI_KO (run build-kernel.sh --driver $DRIVER first)"

export CROSS_COMPILE=aarch64-linux-gnu-
command -v aarch64-linux-gnu-gcc >/dev/null || die "missing aarch64-linux-gnu-gcc"
command -v cpio >/dev/null || die "missing cpio"

REFSRC="$OUT_DIR/fvp-stack-src"
mkdir -p "$REFSRC" "$OUT"

# ---- 1. TF-A (fvp platform, kernel as BL33) --------------------------------
if [ "$SKIP_TFA" -eq 1 ]; then
	info "skipping TF-A build"
elif [ -f "$OUT/bl1.bin" ] && [ -f "$OUT/fip.bin" ]; then
	info "reusing existing firmware in $OUT"
else
	TFASRC="$REFSRC/tf-a"
	if [ ! -f "$TFASRC/Makefile" ]; then
		info "cloning Trusted Firmware-A (mainline mirror)"
		git clone --depth 1 -q https://github.com/TrustedFirmware-A/trusted-firmware-a.git "$TFASRC"
	fi
	info "building TF-A fvp (ARM_LINUX_KERNEL_AS_BL33=1, BL33=kernel)"
	make -C "$TFASRC" CROSS_COMPILE="$CROSS_COMPILE" PLAT=fvp \
		ARM_LINUX_KERNEL_AS_BL33=1 BL33="$(realpath "$KIMAGE")" \
		-j"$JOBS" fip
	cp "$TFASRC/build/fvp/release/bl1.bin" "$OUT/bl1.bin"
	cp "$TFASRC/build/fvp/release/fip.bin" "$OUT/fip.bin"
	info "firmware: bl1.bin, fip.bin -> $OUT"
fi

# ---- 2. BusyBox ------------------------------------------------------------
BBSRC="$REFSRC/busybox"
if [ "$SKIP_BUSYBOX" -eq 1 ]; then
	info "skipping busybox build"
elif [ -x "$OUT/rootfs/bin/busybox" ]; then
	info "reusing existing rootfs staging at $OUT/rootfs"
else
	if [ ! -f "$BBSRC/Makefile" ]; then
		info "cloning busybox (mirror)"
		git clone --depth 1 -q https://github.com/mirror/busybox.git "$BBSRC"
	fi
	info "building static busybox"
	make -C "$BBSRC" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" defconfig >/dev/null
	if [ -x "$BBSRC/scripts/config" ]; then
		"$BBSRC/scripts/config" -f "$BBSRC/.config" -e STATIC
	else
		sed -i 's/^# CONFIG_STATIC is not set$/CONFIG_STATIC=y/' "$BBSRC/.config"
		grep -q '^CONFIG_STATIC=y' "$BBSRC/.config" || echo 'CONFIG_STATIC=y' >> "$BBSRC/.config"
	fi
	make -C "$BBSRC" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" oldconfig >/dev/null || true
	make -C "$BBSRC" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS"
	rm -rf "$OUT/rootfs"
	make -C "$BBSRC" ARCH=arm64 CROSS_COMPILE="$CROSS_COMPILE" \
		install CONFIG_PREFIX="$(realpath "$OUT/rootfs")" >/dev/null
fi

# ---- 3. Rootfs / initramfs -------------------------------------------------
if [ "$SKIP_ROOTFS" -eq 1 ]; then
	info "skipping initramfs packaging"
	exit 0
fi

ROOTFS="$OUT/rootfs"
[ -x "$ROOTFS/bin/busybox" ] || die "rootfs staging missing $ROOTFS/bin/busybox"

mkdir -p "$ROOTFS/lib/modules"
cp "$MALI_KO" "$ROOTFS/lib/modules/mali_kbase.ko"

cat > "$ROOTFS/init" <<'EOF'
#!/bin/sh
export PATH=/bin:/sbin:/usr/bin:/usr/sbin
mount -t proc  proc  /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
echo "=== MALI_LAB_BOOTED ==="
if [ -e /lib/modules/mali_kbase.ko ]; then
	insmod /lib/modules/mali_kbase.ko
	echo "=== MALI_MODULE_INSMOD_DONE rc=$? ==="
fi
sleep 1
if [ -e /dev/mali0 ]; then
	echo "=== MALI_DEVICE_OK /dev/mali0 present ==="
else
	echo "=== MALI_DEVICE_MISSING ==="
	cat /proc/interrupts 2>/dev/null | sed -n '1,6p'
	dmesg | grep -iE 'mali|kbase' | tail -20
fi
echo "=== MALI_LAB_INIT_DONE ==="
exec /bin/sh
EOF
chmod +x "$ROOTFS/init"

info "packaging initramfs rootfs.cpio.gz"
( cd "$ROOTFS" && find . | cpio -o -H newc 2>/dev/null | gzip -1 > "$OUT/rootfs.cpio.gz" )

cat > "$OUT/stack.json" <<EOF
{
  "stack": "modern TF-A fvp, kernel as BL33",
  "driver": "$DRIVER",
  "bl1": "bl1.bin",
  "fip": "fip.bin",
  "kernel_image": "$KIMAGE",
  "kernel_addr": "0x80080000",
  "dtb_addr": "0x82000000",
  "initramfs": "rootfs.cpio.gz",
  "initramfs_addr": "0x84000000",
  "initramfs_bytes": "$(stat -c%s "$OUT/rootfs.cpio.gz")",
  "mali_kbase": "$MALI_KO"
}
EOF

echo
echo "Boot stack under $OUT/:"
ls -la "$OUT"/bl1.bin "$OUT"/fip.bin "$OUT"/rootfs.cpio.gz
info "use scripts/run-fvp.sh --driver $DRIVER to boot"