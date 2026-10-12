#!/usr/bin/env bash
#
# integrate-mali.sh - integrate a Mali Kbase DDK source archive into a Linux kernel tree.
#
# Follows the "Integrating Mali into the Linux Kernel" recipe from the Arm GPU bug
# bounty virtual-platform how-to guide:
#
#   cp -a "$MALI_DIR"/driver/product/kernel/* "$KDIR/"
#   echo 'obj-$(CONFIG_MALI_MIDGARD) += arm/' >> "$KDIR"/drivers/gpu/Makefile
#   sed -i '$i source "drivers/gpu/arm/Kconfig"' "$KDIR"/drivers/video/Kconfig
#
# The x86_"Simulated Platform Device" patches are only applied for x86_64 targets
# (the Device Tree / Arm path needs none). Patch 0006 fixes 'make clean' when the
# arbitration code is absent and applies to both Arm and x86; use --patches 6 to
# apply just that one on an Arm tree.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DRIVER_DIR="$REPO_ROOT/driver"
OUT_DIR="$REPO_ROOT/out"
PATCH_ZIP="$REPO_ROOT/patches_for_virtual_device.zip"

DRIVER=""
KDIR=""
ARCH="arm64"
PATCHES="auto"
DRY_RUN=0

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '[integrate-mali] %s\n' "$*"; }

usage() {
	cat <<'EOF'
Usage: integrate-mali.sh --driver <r41|r56> --kdir <kernel-tree> [options]

Integrate a Mali Kbase DDK archive into a Linux kernel tree (in-tree build).

Required:
  --driver <r41|r56>    Mali DDK release to integrate (r31 is not supported).
  --kdir <dir>          Root of the Linux kernel tree to integrate into.

Options:
  --arch <arm64|x86_64> Guest/target architecture (default: arm64).
  --patches <mode>      auto | none | all | 6   (default: auto)
                          auto : all on x86_64, none on arm64
                          all  : patches 0001..0006 in order
                          6    : only 0006 (fixes 'make clean' on any arch)
                          none : apply no patches
  --dry-run             Print the actions without changing anything.
  -h, --help            Show this help.

Notes:
  * The kernel tree is modified in place. Use a throwaway clone.
  * Config fragments for the dummy model live in kernel/configs/.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--driver)  DRIVER="${2:-}";  shift 2 ;;
		--kdir)    KDIR="${2:-}";    shift 2 ;;
		--arch)    ARCH="${2:-}";    shift 2 ;;
		--patches) PATCHES="${2:-}"; shift 2 ;;
		--dry-run) DRY_RUN=1; shift ;;
		-h|--help) usage; exit 0 ;;
		*) die "unknown argument: $1 (try --help)" ;;
	esac
done

[ -n "$DRIVER" ] || die "--driver is required (try --help)"
[ -n "$KDIR" ]   || die "--kdir is required (try --help)"

case "$DRIVER" in
	r41)
		ARCHIVE="$DRIVER_DIR/AX504X08X-SW-99002-r41p0-01eac0.tar.gz"
		RELEASE="r41p0-01eac0"
		;;
	r56)
		ARCHIVE="$DRIVER_DIR/VX504X08X-SW-99002-r56p0-19eac0.tar"
		RELEASE="r56p0-19eac0"
		;;
	r31)
		die "r31p0 is not supported: its archive is missing backend/gpu/mali_kbase_model_dummy.c and backend/gpu/mali_kbase_model_linux.c, so CONFIG_MALI_NO_MALI=y cannot build. Use --driver r41 or r56."
		;;
	*)
		die "unknown driver '$DRIVER' (supported: r41, r56)"
		;;
esac

case "$ARCH" in arm64|x86_64) ;; *) die "unknown --arch '$ARCH' (arm64|x86_64)" ;; esac
case "$PATCHES" in auto|none|all|6) ;; *) die "unknown --patches '$PATCHES' (auto|none|all|6)" ;; esac

[ -f "$ARCHIVE" ] || die "driver archive not found: $ARCHIVE"

KDIR="$(cd "$KDIR" 2>/dev/null && pwd)" || die "kernel tree not found: $KDIR"
[ -f "$KDIR/Makefile" ]       || die "'$KDIR' does not look like a Linux kernel tree (no Makefile)"
[ -d "$KDIR/drivers/gpu" ]    || die "'$KDIR' has no drivers/gpu directory"
[ -f "$KDIR/drivers/video/Kconfig" ] || die "'$KDIR' has no drivers/video/Kconfig"

run() {
	if [ "$DRY_RUN" -eq 1 ]; then
		printf '  (dry-run) %s\n' "$*"
	else
		"$@"
	fi
}

# Resolve the effective patch mode.
if [ "$PATCHES" = "auto" ]; then
	if [ "$ARCH" = "x86_64" ]; then PATCHES="all"; else PATCHES="none"; fi
fi

info "driver   : $DRIVER ($RELEASE)"
info "archive  : $ARCHIVE"
info "kernel   : $KDIR"
info "arch     : $ARCH"
info "patches  : $PATCHES"
[ "$DRY_RUN" -eq 1 ] && info "mode     : DRY RUN"

SRC_ROOT="$OUT_DIR/mali-src/$DRIVER"
MALI_DIR="$SRC_ROOT/driver"

# 1. Extract the archive into a scratch dir.
if [ ! -d "$MALI_DIR/product/kernel" ]; then
	info "extracting archive -> $SRC_ROOT"
	run mkdir -p "$SRC_ROOT"
	run tar -xf "$ARCHIVE" -C "$SRC_ROOT"
else
	info "reusing extracted source at $SRC_ROOT"
fi
[ "$DRY_RUN" -eq 1 ] || [ -d "$MALI_DIR/product/kernel" ] || die "extracted source missing $MALI_DIR/product/kernel"

# 2. Copy the Kbase source into the kernel tree.
info "copying $MALI_DIR/product/kernel/* -> $KDIR/"
run cp -a "$MALI_DIR"/product/kernel/. "$KDIR/"

# 3. Wire the driver into the kernel build (idempotent).
MAKEFILE_LINE='obj-$(CONFIG_MALI_MIDGARD) += arm/'
if grep -qF "$MAKEFILE_LINE" "$KDIR/drivers/gpu/Makefile" 2>/dev/null; then
	info "drivers/gpu/Makefile already wired"
else
	info "adding '$MAKEFILE_LINE' to drivers/gpu/Makefile"
	if [ "$DRY_RUN" -eq 1 ]; then
		echo "  (dry-run) append to drivers/gpu/Makefile"
	else
		echo "$MAKEFILE_LINE" >> "$KDIR/drivers/gpu/Makefile"
	fi
fi

KCONFIG_LINE='source "drivers/gpu/arm/Kconfig"'
if grep -qF "$KCONFIG_LINE" "$KDIR/drivers/video/Kconfig" 2>/dev/null; then
	info "drivers/video/Kconfig already sources arm/Kconfig"
else
	info "inserting '$KCONFIG_LINE' into drivers/video/Kconfig"
	if [ "$DRY_RUN" -eq 1 ]; then
		echo "  (dry-run) sed -i '\$i $KCONFIG_LINE' drivers/video/Kconfig"
	elif [ -s "$KDIR/drivers/video/Kconfig" ]; then
		sed -i "\$i $KCONFIG_LINE" "$KDIR/drivers/video/Kconfig"
	else
		printf '%s\n' "$KCONFIG_LINE" >> "$KDIR/drivers/video/Kconfig"
	fi
fi

# 4. Optionally apply the x86 virtual-device patches.
apply_patches() {
	local patch_dir="$OUT_DIR/patches"
	info "extracting patches -> $patch_dir"
	run mkdir -p "$patch_dir"
	run unzip -o -q "$PATCH_ZIP" -d "$patch_dir"

	local list=()
	if [ "$DRY_RUN" -eq 1 ]; then
		# Nothing was extracted; list patch names straight from the zip.
		while IFS= read -r name; do
			case "$PATCHES:$name" in
				all:*.patch)  list+=("$patch_dir/$name") ;;
				6:0006-*.patch) list+=("$patch_dir/$name") ;;
			esac
		done < <(unzip -Z1 "$PATCH_ZIP" | sort)
	elif [ "$PATCHES" = "all" ]; then
		while IFS= read -r p; do list+=("$p"); done < <(find "$patch_dir" -maxdepth 1 -name '*.patch' | sort)
	elif [ "$PATCHES" = "6" ]; then
		while IFS= read -r p; do list+=("$p"); done < <(find "$patch_dir" -maxdepth 1 -name '0006-*.patch' | sort)
	fi

	[ "${#list[@]}" -gt 0 ] || die "no patch files selected"
	for p in "${list[@]}"; do
		info "applying $(basename "$p")"
		run patch -p3 -d "$KDIR" -i "$p"
	done
	# Fail loudly if anything rejected.
	if [ "$DRY_RUN" -eq 0 ] && find "$KDIR" -name '*.rej' -print -quit | grep -q .; then
		die "patch rejects present (*.rej) under $KDIR"
	fi
}

if [ "$PATCHES" = "none" ]; then
	info "skipping patches ($ARCH path)"
else
	apply_patches
fi

info "done."
echo
echo "Next steps:"
echo "  1. Merge the config fragment for this release:"
echo "       $REPO_ROOT/kernel/configs/kbase-$DRIVER.config"
echo "     e.g.  cd $KDIR && make ARCH=$ARCH defconfig \\"
echo "             && scripts/kconfig/merge_config.sh -m -O . .config $REPO_ROOT/kernel/configs/kbase-$DRIVER.config \\"
echo "             && make ARCH=$ARCH olddefconfig"
echo "  2. Build the module:  make ARCH=$ARCH M=drivers/gpu/arm modules"
echo "  3. Boot the platform and 'insmod mali_kbase.ko' (see scripts/check-mali.sh)."
