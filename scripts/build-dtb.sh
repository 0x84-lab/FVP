#!/usr/bin/env bash
#
# build-dtb.sh - splice the Mali "dummy model" node into the FVP device tree.
#
# Mirrors the device-tree steps from the Arm GPU bug bounty virtual-platform
# how-to guide exactly:
#
#   dtc -I dtb -O dts original.dtb -o original.dts
#   <insert the Mali node before the final "};">
#   dtc -I dts -O dtb dummy_mali.dts -o dummy_mali.dtb
#
# Lab extras (do not alter the Mali node itself):
#   * populates /chosen with bootargs (the guide requires "acpi=off"), and
#   * optionally sets linux,initrd-start/end for the initramfs rootfs.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_NODE="$REPO_ROOT/fvp/dtb/mali-node.dts"
DEFAULT_BOOTARGS="console=ttyAMA0,115200n8 root=/dev/ram0 rw rdinit=/init acpi=off panic=-1"

INPUT=""
OUTPUT=""
NODE_FILE="$DEFAULT_NODE"
BOOTARGS=""
INITRD_BASE=""
INITRD_SIZE=""
DUMP_DTS=""
FORCE=0

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '[build-dtb] %s\n' "$*"; }

usage() {
	cat <<'EOF'
Usage: build-dtb.sh --input <original.dtb|original.dts> --output <dummy_mali.dtb> [options]

Required:
  --input FILE      Original FVP device tree blob (or .dts source).
  --output FILE     Replacement DTB to write.

Options:
  --node FILE      Mali DT fragment to insert (default: fvp/dtb/mali-node.dts).
  --bootargs "S"   Kernel command line written into /chosen.
                   Default: console=ttyAMA0,115200n8 root=/dev/ram0 rw
                            rdinit=/init acpi=off panic=-1
  --initrd-base H  Hex load address of the initramfs; with --initrd-size adds
                   linux,initrd-start/end to /chosen.
  --initrd-size N  Size in bytes of the initramfs (with --initrd-base).
  --dump-dts FILE  Also save the intermediate edited .dts (debugging).
  --force          Overwrite existing --output.
  -h, --help       Show this help.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--input)       INPUT="${2:-}";       shift 2 ;;
		--output)      OUTPUT="${2:-}";      shift 2 ;;
		--node)        NODE_FILE="${2:-}";   shift 2 ;;
		--bootargs)    BOOTARGS="${2:-}";    shift 2 ;;
		--initrd-base) INITRD_BASE="${2:-}"; shift 2 ;;
		--initrd-size) INITRD_SIZE="${2:-}"; shift 2 ;;
		--dump-dts)    DUMP_DTS="${2:-}";    shift 2 ;;
		--force)       FORCE=1; shift ;;
		-h|--help)     usage; exit 0 ;;
		*) die "unknown argument: $1 (try --help)" ;;
	esac
done

[ -n "$INPUT" ]  || die "--input is required (try --help)"
[ -n "$OUTPUT" ] || die "--output is required (try --help)"
[ -f "$INPUT" ]  || die "--input not found: $INPUT"
[ -f "$NODE_FILE" ] || die "--node not found: $NODE_FILE"
if [ -e "$OUTPUT" ] && [ "$FORCE" -ne 1 ]; then
	die "--output already exists: $OUTPUT (pass --force to overwrite)"
fi
[ -n "$BOOTARGS" ] || BOOTARGS="$DEFAULT_BOOTARGS"
if [ -n "$INITRD_BASE" ] || [ -n "$INITRD_SIZE" ]; then
	[ -n "$INITRD_BASE" ] && [ -n "$INITRD_SIZE" ] || die "--initrd-base and --initrd-size must be used together"
	[ "$INITRD_BASE" = "$(printf '%s' "$INITRD_BASE" | tr -cd '0-9a-fA-Fx')" ] || die "--initrd-base must be hex like 0x84000000"
	fmt_v="$(printf '%s' "$INITRD_SIZE" | tr -cd '0-9')"
	[ -n "$fmt_v" ] || die "--initrd-size must be a number of bytes"
fi

command -v dtc >/dev/null || die "dtc (device-tree-compiler) is required: sudo apt-get install device-tree-compiler"
command -v python3 >/dev/null || die "python3 is required"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# 1. Normalize the input to a .dts text file.
if [ "$(xxd -p -l 4 "$INPUT" 2>/dev/null || true)" = "d00dfeed" ]; then
	info "decompiling DTB $INPUT"
	dtc -I dtb -O dts "$INPUT" -o "$TMP/source.dts"
else
	info "input treated as .dts source"
	cp "$INPUT" "$TMP/source.dts"
fi

# 2. Insert the Mali node and populate /chosen.
python3 - "$TMP/source.dts" "$TMP/edited.dts" "$NODE_FILE" "$BOOTARGS" "$INITRD_BASE" "$INITRD_SIZE" <<'PY'
import re
import sys

src, dst, node_file, bootargs, initrd_base, initrd_size = sys.argv[1:7]

text = open(src).read()
node = open(node_file).read().rstrip('\n') + '\n'

# Mali node: insert immediately before the last root-level '};'.
pos = text.rfind('};')
if pos < 0:
    sys.exit('error: no root closing "};" found in the source dts')
text = text[:pos] + node + text[pos:]

def chosen_props(indent):
    out = indent + 'bootargs = "%s";\n' % bootargs
    if initrd_base:
        base = int(initrd_base, 16)
        end = base + int(initrd_size)
        out += indent + 'linux,initrd-start = <0x0 0x%x>;\n' % base
        out += indent + 'linux,initrd-end   = <0x0 0x%x>;\n' % end
    return out

# /chosen in the 5.15 kernel fvp dtb is 'chosen { };' (single line) or a
# two-line 'chosen {\n};' block. Rewrite those forms with our bootargs.
m = re.search(r'(?m)^(\s*)chosen\s*\{\s*\}\s*;\s*\r?\n?', text)
if not m:
    m = re.search(r'(?m)^(\s*)chosen\s*\{\s*\r?\n\s*\};\s*\r?\n?', text)
if m:
    repl = (m.group(1) + 'chosen {\n'
            + chosen_props(m.group(1) + '\t')
            + m.group(1) + '};\n')
    text = text[:m.start()] + repl + text[m.end():]
else:
    sys.exit('error: no plain /chosen node found (single-line or "chosen { };" two-line form); edit the dts manually')

open(dst, 'w').write(text)
PY

# 3. Recompile the replacement DTB.
info "compiling $OUTPUT"
dtc -I dts -O dtb "$TMP/edited.dts" -o "$OUTPUT"

# 4. Verify the Mali node survived the round-trip.
if ! dtc -I dtb -O dts "$OUTPUT" | grep -q 'gpu@6e000000'; then
	die "Mali node (gpu@6e000000) missing from compiled $OUTPUT"
fi
if ! dtc -I dtb -O dts "$OUTPUT" | grep -q 'mali-midgard'; then
	die "compatible 'arm,mali-midgard' missing from compiled $OUTPUT"
fi
if ! dtc -I dtb -O dts "$OUTPUT" | grep -q 'bootargs'; then
	die "/chosen/bootargs missing from compiled $OUTPUT"
fi

if [ -n "$DUMP_DTS" ]; then
	info "saving intermediate dts -> $DUMP_DTS"
	cp "$TMP/edited.dts" "$DUMP_DTS"
fi

info "done: $OUTPUT"