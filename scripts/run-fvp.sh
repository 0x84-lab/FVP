#!/usr/bin/env bash
#
# run-fvp.sh - boot the Mali fuzz lab on the Arm FVP.
#
# Boot chain (modern TF-A, kernel as BL33):
#   bl1.bin/fip.bin (TF-A fvp) -> Image@0x80080000 -> dummy_mali.dtb@0x82000000
#   -> rootfs.cpio.gz@0x84000000
#
# If the kernel DTB or the initramfs change, the DTB is regenerated at boot
# time so /chosen/linux,initrd-* always match the real rootfs size.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$REPO_ROOT/out"

FVP_BIN="${FVP_BIN:-}"
DRIVER="r56"
STACK="$OUT_DIR/fvp-stack"
KERNEL=""
DTB=""
ROOTFS=""
TIMEOUT=""
UART0=""
UART1=""
HEADLESS=1
DUMP_DTB=""
EXTRA=()

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '[run-fvp] %s\n' "$*"; }

usage() {
	cat <<'EOF'
Usage: run-fvp.sh [options] [extra FVP model args...]

Options:
  --driver <r41|r56>  Select out/<driver> artifacts (default: r56).
  --stack DIR         Boot stack dir (default: out/fvp-stack).
  --kernel DIR        Kernel artifacts dir (default: out/<driver>).
  --dtb FILE          Use an explicit DTB instead of regenerating it.
  --rootfs FILE       Root filesystem (default: <stack>/rootfs.cpio.gz).
  --fvp-bin FILE      FVP model binary (default: auto-detect).
  --timeout SEC       Kill the model after SEC seconds (default: run forever).
  --uart0 FILE, --uart1 FILE   UART output logs (default out/logs/uart*.log).
  --dump-dtb FILE     Also ask the FVP to dump its DTB (-dumpdtb=FILE).
  --gui               Allow the FVP GUI (default: headless).
  -h, --help          Show this help.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--driver)    DRIVER="${2:-}"; shift 2 ;;
		--stack)     STACK="${2:-}";  shift 2 ;;
		--kernel)    KERNEL="${2:-}"; shift 2 ;;
		--dtb)       DTB="${2:-}";    shift 2 ;;
		--rootfs)    ROOTFS="${2:-}"; shift 2 ;;
		--fvp-bin)   FVP_BIN="${2:-}"; shift 2 ;;
		--timeout)   TIMEOUT="${2:-}"; shift 2 ;;
		--uart0)     UART0="${2:-}";  shift 2 ;;
		--uart1)     UART1="${2:-}";  shift 2 ;;
		--dump-dtb)  DUMP_DTB="${2:-}"; shift 2 ;;
		--gui)       HEADLESS=0; shift ;;
		-h|--help)   usage; exit 0 ;;
		-*) die "unknown argument: $1 (try --help)" ;;
		*) EXTRA+=("$1"); shift ;;
	esac
done

case "$DRIVER" in r41|r56) ;; *) die "unknown --driver '$DRIVER' (r41|r56)" ;; esac
[ -n "$KERNEL" ] || KERNEL="$OUT_DIR/$DRIVER"
[ -n "$ROOTFS" ] || ROOTFS="$STACK/rootfs.cpio.gz"

# ---- FVP binary detection -------------------------------------------------
detect_fvp() {
	if [ -n "$FVP_BIN" ] && [ -x "$FVP_BIN" ]; then echo "$FVP_BIN"; return 0; fi
	local cand
	for cand in "$HOME"/FVP_Base_RevC_AEMvA_*/bin/FVP_Base_RevC-2xAEMvA \
	            "$REPO_ROOT"/fvp/install/*/bin/FVP_Base_RevC-2xAEMvA; do
		if [ -x "$cand" ]; then echo "$cand"; return 0; fi
	done
	return 1
}
FVP_BIN="$(detect_fvp)" || die "FVP model not found (install the Arm FVP or set --fvp-bin / FVP_BIN)"

# ---- Inputs ---------------------------------------------------------------
[ -f "$STACK/fip.bin" ]  || die "missing $STACK/fip.bin (run scripts/build-stack.sh)"
[ -f "$KERNEL/Image" ]   || die "missing $KERNEL/Image (run scripts/build-kernel.sh)"
[ -f "$KERNEL/fvp-base-revc.dtb" ] || die "missing $KERNEL/fvp-base-revc.dtb"
[ -f "$ROOTFS" ]         || die "missing rootfs $ROOTFS (run scripts/build-stack.sh)"

# ---- DTB: regenerate so initrd props match the current rootfs ---------------
if [ -z "$DTB" ]; then
	RUN_DIR="$OUT_DIR/run"
	mkdir -p "$RUN_DIR"
	DTB="$RUN_DIR/dummy_mali-$DRIVER.dtb"
	if [ "${ROOTFS##*.}" = "gz" ]; then
		INITRD_BYTES="$(stat -c%s "$ROOTFS")"
		info "regenerating $DTB (initramfs=$INITRD_BYTES bytes @0x84000000)"
		"$SCRIPT_DIR/build-dtb.sh" --force \
			--input  "$KERNEL/fvp-base-revc.dtb" \
			--output "$DTB" \
			--initrd-base 0x84000000 \
			--initrd-size "$INITRD_BYTES"
	else
		info "rootfs is a block image; booting with root=/dev/vda"
		"$SCRIPT_DIR/build-dtb.sh" --force \
			--input  "$KERNEL/fvp-base-revc.dtb" \
			--output "$DTB" \
			--bootargs "console=ttyAMA0,115200n8 root=/dev/vda rw acpi=off panic=-1"
	fi
fi
[ -f "$DTB" ] || die "DTB not found: $DTB"

# ---- Logs ------------------------------------------------------------------
LOG_DIR="$OUT_DIR/logs"
mkdir -p "$LOG_DIR"
[ -n "$UART0" ] || UART0="$LOG_DIR/uart0.log"
[ -n "$UART1" ] || UART1="$LOG_DIR/uart1.log"

# ---- Boot ------------------------------------------------------------------
CMD=( "$FVP_BIN" )
CMD+=( -C pctl.startup=0.0.0.0 )
CMD+=( -C bp.secure_memory=0 )
CMD+=( -C cache_state_modelled=0 )
CMD+=( -C bp.ve_sysregs.mmbSiteDefault=0 )
CMD+=( -C bp.ve_sysregs.exit_on_shutdown=1 )
CMD+=( -C cluster0.NUM_CORES=4 )
CMD+=( -C cluster1.NUM_CORES=4 )
CMD+=( -C bp.pl011_uart0.untimed_fifos=1 )
CMD+=( -C bp.pl011_uart0.unbuffered_output=1 )
CMD+=( -C bp.pl011_uart0.out_file="$UART0" )
CMD+=( -C bp.pl011_uart1.untimed_fifos=1 )
CMD+=( -C bp.pl011_uart1.unbuffered_output=1 )
CMD+=( -C bp.pl011_uart1.out_file="$UART1" )
# TF-A fvp with ARM_LINUX_KERNEL_AS_BL33 + RESET_TO_BL31=1 produces fip.bin
# but no bl1.bin; use fip.bin as the secure flashloader (common on modern TF-A)
CMD+=( -C bp.secureflashloader.fname="$STACK/fip.bin" )
CMD+=( -C bp.flashloader0.fname="$STACK/fip.bin" )
CMD+=( --data cluster0.cpu0="$KERNEL/Image@0x80080000" )
CMD+=( --data cluster0.cpu0="$DTB@0x82000000" )
CMD+=( --data cluster0.cpu0="$ROOTFS@0x84000000" )
if [ -n "$DUMP_DTB" ]; then
	CMD+=( -dumpdtb="$DUMP_DTB" )
fi
CMD+=( "${EXTRA[@]}" )

info "FVP      : $FVP_BIN"
info "firmware : $STACK/bl1.bin + $STACK/fip.bin"
info "kernel   : $KERNEL/Image@0x80080000"
info "dtb      : $DTB@0x82000000"
info "rootfs   : $ROOTFS@0x84000000"
info "uart0    : $UART0"

if [ "$HEADLESS" -eq 1 ]; then
	export DISPLAY= TERM=dumb
fi

if [ -n "$TIMEOUT" ]; then
	exec timeout "$TIMEOUT" "${CMD[@]}"
else
	exec "${CMD[@]}"
fi