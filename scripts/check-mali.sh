#!/usr/bin/env bash
#
# check-mali.sh - boot the FVP lab VM and verify mali_kbase comes up against the
# "dummy model" (No Mali) configuration.
#
# The guest init script prints markers on UART0:
#   === MALI_LAB_BOOTED ===            kernel + initramfs up
#   === MALI_MODULE_INSMOD_DONE rc=0   insmod result
#   === MALI_DEVICE_OK ...             /dev/mali0 present (driver probed)
#   === MALI_LAB_INIT_DONE ===
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
OUT_DIR="$REPO_ROOT/out"

DRIVER="r56"
LOG=""
BOOT_TIMEOUT="240"
MAX_WAIT="180"
RUN_ARGS=()

die() { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '[check-mali] %s\n' "$*"; }

usage() {
	cat <<'EOF'
Usage: check-mali.sh [options] [extra FVP args...]

Options:
  --driver <r41|r56>  Driver artifacts to test (default: r56).
  --log FILE          Check an existing UART0 log instead of booting.
  --boot-timeout SEC  FVP runtime cap for the boot (default: 240).
  --wait SEC          Max time to wait for markers (default: 180).
  All other options are forwarded to run-fvp.sh.
EOF
}

while [ $# -gt 0 ]; do
	case "$1" in
		--driver)        DRIVER="${2:-}"; shift 2 ;;
		--log)           LOG="${2:-}";    shift 2 ;;
		--boot-timeout)  BOOT_TIMEOUT="${2:-}"; shift 2 ;;
		--wait)          MAX_WAIT="${2:-}"; shift 2 ;;
		-h|--help)       usage; exit 0 ;;
		*)               RUN_ARGS+=("$1"); shift ;;
	esac
done

case "$DRIVER" in r41|r56) ;; *) die "unknown --driver '$DRIVER' (r41|r56)" ;; esac

LOG_DIR="$OUT_DIR/logs"
mkdir -p "$LOG_DIR"

if [ -z "$LOG" ]; then
	LOG="$LOG_DIR/uart0-check-$DRIVER.log"
	rm -f "$LOG"
	info "booting FVP (timeout ${BOOT_TIMEOUT}s) -> $LOG"
	set +e
	"$SCRIPT_DIR/run-fvp.sh" --driver "$DRIVER" --timeout "$BOOT_TIMEOUT" \
		--uart0 "$LOG" "${RUN_ARGS[@]}" >/dev/null 2>&1
	RC=$?
	set -e
	case "$RC" in
		0)   info "FVP exited cleanly (exit_on_shutdown)" ;;
		124) info "FVP killed after --boot-timeout (expected)" ;;
		*)   info "FVP exited with rc=$RC; checking log anyway" ;;
	esac
fi
[ -f "$LOG" ] || die "no UART0 log at $LOG"

info "waiting for Mali boot markers in $LOG"
BOOTED=0; INSMOD=0; DEVOK=0; DEVFAIL=0; DONE=0
for _ in $(seq 1 "$MAX_WAIT"); do
	grep -q "=== MALI_LAB_BOOTED ===" "$LOG"           && BOOTED=1
	grep -q "=== MALI_MODULE_INSMOD_DONE" "$LOG"        && INSMOD=1
	grep -q "=== MALI_DEVICE_OK" "$LOG"                 && DEVOK=1
	grep -q "=== MALI_DEVICE_MISSING" "$LOG"            && DEVFAIL=1
	grep -q "=== MALI_LAB_INIT_DONE ===" "$LOG"         && DONE=1
	if [ "$DEVOK" -eq 1 ] || [ "$DEVFAIL" -eq 1 ]; then break; fi
	sleep 1
done

echo
echo "================ MALI CHECK SUMMARY ($DRIVER) ================"
echo "  kernel booted (MALI_LAB_BOOTED)      : $([ "$BOOTED" -eq 1 ] && echo YES || echo no)"
echo "  mali_kbase insmod rc                : $(grep -o 'MALI_MODULE_INSMOD_DONE rc=[0-9-]*' "$LOG" | head -1)"
echo "  /dev/mali0 probed (MALI_DEVICE_OK)  : $([ "$DEVOK" -eq 1 ] && echo YES || ([ "$DEVFAIL" -eq 1 ] && echo 'NO (missing)' || echo 'no marker yet'))"
echo "  init done (MALI_LAB_INIT_DONE)      : $([ "$DONE" -eq 1 ] && echo YES || echo no)"
echo "================================================================="

if [ "$DEVOK" -eq 1 ]; then
	info "PASS: mali_kbase probed the dummy model and created /dev/mali0"
	grep -iE 'kbase|mali' "$LOG" | grep -ivE 'mali_kbase.ko|MALI_LAB|MALI_MODULE|MALI_DEVICE|MALI_LAB_INIT' | tail -12 || true
	exit 0
fi

info "FAIL: /dev/mali0 not present"
echo
echo "=== tail of UART0 log ==="
tail -60 "$LOG"
exit 1