#!/system/bin/sh

LOG_DIR="/data/adb/deepdoze"
PIDFILE="$LOG_DIR/service.pid"
RESTRICTED_FILE="$LOG_DIR/restricted_pkgs"
KEEP_FILE="$LOG_DIR/appops_keep"
CPU_BASE="/sys/devices/system/cpu"
CPU_STATE_DIR="$LOG_DIR/cpu_state"

pid=$(cat "$PIDFILE" 2>/dev/null)
if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    i=0
    while [ "$i" -lt 5 ] && kill -0 "$pid" 2>/dev/null; do
        sleep 1
        i=$((i + 1))
    done
fi
pkill -f "logcat -b events -T 1 -s screen_toggled" 2>/dev/null

dumpsys deviceidle unforce >/dev/null 2>&1

if [ -f "$RESTRICTED_FILE" ]; then
    while read -r pkg; do
        [ -z "$pkg" ] && continue
        am set-standby-bucket "$pkg" active >/dev/null 2>&1
        grep -qxF "$pkg" "$KEEP_FILE" 2>/dev/null \
            || cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND default >/dev/null 2>&1
    done <"$RESTRICTED_FILE"
fi

if [ -d "$CPU_STATE_DIR" ]; then
    for d in "$CPU_BASE"/cpufreq/policy* "$CPU_BASE"/cpu[0-9]*/cpufreq; do
        [ -d "$d" ] || continue
        case "$d" in
            */cpufreq) name=$(basename "${d%/cpufreq}") ;;
            *) name=$(basename "$d") ;;
        esac
        [ -f "$CPU_STATE_DIR/$name.max" ] && cat "$CPU_STATE_DIR/$name.max" >"$d/scaling_max_freq" 2>/dev/null
        [ -f "$CPU_STATE_DIR/$name.gov" ] && cat "$CPU_STATE_DIR/$name.gov" >"$d/scaling_governor" 2>/dev/null
    done
fi

setprop persist.traced.enable 1 2>/dev/null
setprop persist.sys.trace.default 1 2>/dev/null

rm -rf "$LOG_DIR" 2>/dev/null
