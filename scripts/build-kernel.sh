#!/usr/bin/env bash
#
# build-kernel.sh - build Linux 5.15 LTS (arm64) with the Mali Kbase "dummy
# model" driver integrated, for the Arm FVP guest.
#
# Produces, under out/<driver>/:
#   Image              bootable arm64 kernel image (loaded at 0x80080000)
#   fvp-base-revc.dtb  stock FVP device-tree blob (pre-Mali splice)
#   dummy_mali.dtb     fvp DT with the Mali node + /chosen bootargs
#   mali_kbase.ko      the Mali driver module
#   modules/           full module staging tree (for rootfs images)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$REPO_ROOT/out"

DRIVER="r56"
JOBS="$(nproc)"
KCOV=0
REFETCH=0
INCREMENTAL=0

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '[build-kernel] %s\n' "$*"; }

usage() {
	cat <<'EOF'
Usage: build-kernel.sh [options]

Options:
  --driver <r41|r56>  Mali DDK release to integrate (default: r56).
  --jobs N            make -j N (default: number of CPUs).
  --kcov              Enable KCOV coverage instrumentation + DEBUG_FS
                      (fuzzing lab; do NOT ship in repro configs).
  --refetch           Re-download / re-untar the kernel source.
  --incremental       Keep the existing O= build dir (default: clean build).
  -h, --help          Show this help.

Environment: expects gcc-aarch64-linux-gnu etc. See README.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--driver)      DRIVER="${2:-}"; shift 2 ;;
		--jobs)        JOBS="${2:-}";    shift 2 ;;
		--kcov)        KCOV=1; shift ;;
		--refetch)     REFETCH=1; shift ;;
		--incremental) INCREMENTAL=1; shift ;;
		-h|--help)     usage; exit 0 ;;
		*) die "unknown argument: $1 (try --help)" ;;
	esac
done

case "$DRIVER" in r41|r56) ;; *) die "unknown --driver '$DRIVER' (r41|r56)" ;; esac

for tool in aarch64-linux-gnu-gcc make curl tar; do
	command -v "$tool" >/dev/null || die "missing tool: $tool"
done
command -v bison >/dev/null || die "missing bison (sudo apt-get install bison)"
command -v flex  >/dev/null || die "missing flex (sudo apt-get install flex)"
command -v bc    >/dev/null || die "missing bc (sudo apt-get install bc)"

export ARCH=arm64
export CROSS_COMPILE=aarch64-linux-gnu-

SRC_ROOT="$OUT_DIR/kernel-src"
SRC_TREE="$SRC_ROOT/linux-5.15-$DRIVER"
BUILD="$OUT_DIR/build-$DRIVER"
TARGET="$OUT_DIR/$DRIVER"

# ---- 1. Kernel source -----------------------------------------------------
if [ "$REFETCH" -eq 1 ] && [ -e "$SRC_TREE" ]; then
	info "--refetch: removing existing source tree $SRC_TREE"
	rm -rf "$SRC_TREE"
fi
if [ ! -d "$SRC_TREE/.git" ] && [ ! -f "$SRC_TREE/Makefile" ]; then
	info "fetching latest Linux 5.15.x tarball"
	RELEASE_PAGE="$(curl -fsSL https://cdn.kernel.org/pub/linux/kernel/v5.x/)" \
		|| die "cannot contact cdn.kernel.org"
	KVER="$(printf '%s' "$RELEASE_PAGE" | grep -oP 'linux-5\.15\.\d+\.tar\.xz' | sort -Vu | tail -1)"
	[ -n "$KVER" ] || die "could not find a 5.15.x tarball on cdn.kernel.org"

	TARBALL="$SRC_ROOT/$KVER"
	mkdir -p "$SRC_ROOT"
	if [ ! -f "$TARBALL" ] || [ "$REFETCH" -eq 1 ]; then
		info "downloading $KVER"
		curl -fL --retry 3 -o "$TARBALL" "https://cdn.kernel.org/pub/linux/kernel/v5.x/$KVER"
	fi
	DST="$SRC_ROOT/linux-5.15-$DRIVER"
	info "unpacking $KVER -> $SRC_TREE"
	mkdir -p "$DST"
	tar -xJf "$TARBALL" -C "$DST" --strip-components=1
else
	info "reusing kernel source tree $SRC_TREE"
fi

# ---- 2. Mali driver integration (guide recipe, idempotent) ----------------
"$SCRIPT_DIR/integrate-mali.sh" --driver "$DRIVER" --kdir "$SRC_TREE" --arch arm64 --patches none

# ---- 3. Kernel configuration ----------------------------------------------
if [ -d "$BUILD" ] && [ "$INCREMENTAL" -ne 1 ]; then
	info "cleaning previous build dir $BUILD"
	rm -rf "$BUILD"
fi
mkdir -p "$BUILD" "$TARGET"

info "generating arm64 defconfig"
make -C "$SRC_TREE" O="$BUILD" defconfig >/dev/null

info "merging Mali dummy-model fragment (kernel/configs/kbase-$DRIVER.config)"
"$SRC_TREE/scripts/kconfig/merge_config.sh" -m -O "$BUILD" "$BUILD/.config" "$REPO_ROOT/kernel/configs/kbase-$DRIVER.config" >/dev/null

if [ "$KCOV" -eq 1 ]; then
	info "enabling KCOV coverage instrumentation (lab only)"
	KCOV_FRAG="$BUILD/.kbase-lab-kcov.config"
	cat > "$KCOV_FRAG" <<'EOF'
CONFIG_KCOV=y
CONFIG_KCOV_INSTRUMENT_ALL=y
CONFIG_KCOV_ENABLE_COMPARISONS=y
CONFIG_DEBUG_FS=y
EOF
	"$SRC_TREE/scripts/kconfig/merge_config.sh" -m -O "$BUILD" "$BUILD/.config" "$KCOV_FRAG" >/dev/null
fi

make -C "$SRC_TREE" O="$BUILD" olddefconfig >/dev/null
info "config summary:"
grep -E '^CONFIG_MALI_(MIDGARD|NO_MALI|CSF_SUPPORT|PLATFORM_NAME|NO_MALI_DEFAULT_GPU)=' "$BUILD/.config" || true

# ---- 4. Build --------------------------------------------------------------
info "building Image + dtbs + modules (-j$JOBS)"
make -C "$SRC_TREE" O="$BUILD" -j"$JOBS" Image dtbs modules

info "staging module tree"
make -C "$SRC_TREE" O="$BUILD" -j"$JOBS" INSTALL_MOD_PATH="$TARGET/modules" modules_install >/dev/null

info "collecting artifacts"
cp "$BUILD/arch/arm64/boot/Image"                                   "$TARGET/Image"
cp "$BUILD/arch/arm64/boot/dts/arm/fvp-base-revc.dtb"               "$TARGET/fvp-base-revc.dtb"
cp "$BUILD/drivers/gpu/arm/mali_kbase.ko"                            "$TARGET/mali_kbase.ko"

# ---- 5. Baseline dummy-mali DTB (initrd props are added at boot time) ------
"$SCRIPT_DIR/build-dtb.sh" --force \
	--input  "$TARGET/fvp-base-revc.dtb" \
	--output "$TARGET/dummy_mali.dtb"

echo
echo "Artifacts under $TARGET/:"
ls -la "$TARGET"
echo
info "mali_kbase.ko: $(stat -c%s "$TARGET/mali_kbase.ko" 2>/dev/null || echo '?') bytes"