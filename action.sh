#!/system/bin/sh

MODDIR=${0%/*}
LOG_DIR="${DEEPDOZE_LOG_DIR:-/data/adb/deepdoze}"
PIDFILE="$LOG_DIR/service.pid"
DOZE_FLAG="$LOG_DIR/doze_forced"
BATT_DIR="${DEEPDOZE_BATT_DIR:-/sys/class/power_supply/battery}"
mkdir -p "$LOG_DIR" 2>/dev/null

echo "DeepDoze Enforcer"

service_pid_valid() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ -r "/proc/$1/cmdline" ] || return 1
    tr '\000' ' ' <"/proc/$1/cmdline" 2>/dev/null | grep -Fq "$MODDIR/service.sh"
}

find_batt() {
    for d in "$BATT_DIR" /sys/class/power_supply/Battery; do
        [ -f "$d/status" ] && { BATT_DIR=$d; return 0; }
    done
    for d in /sys/class/power_supply/*; do
        [ "$(cat "$d/type" 2>/dev/null)" = Battery ] && [ -f "$d/status" ] \
            && { BATT_DIR=$d; return 0; }
    done
    return 1
}

running=0
if [ -f "$PIDFILE" ]; then
    pid=$(cat "$PIDFILE" 2>/dev/null)
    service_pid_valid "$pid" && kill -0 "$pid" 2>/dev/null && running=1
fi

if [ "$running" = 1 ]; then
    echo "Service: already running"
elif [ -f "$MODDIR/service.sh" ]; then
    echo "Starting sleep service..."
    if command -v setsid >/dev/null 2>&1; then
        setsid sh "$MODDIR/service.sh" >/dev/null 2>&1 &
    else
        nohup sh "$MODDIR/service.sh" >/dev/null 2>&1 &
    fi
    i=0
    while [ "$i" -lt 5 ]; do
        sleep 1
        if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
            running=1
            break
        fi
        i=$((i + 1))
    done
    [ "$running" = 1 ] && echo "Service: started" || echo "Service: launch attempted"
else
    echo "Service: script not found"
fi

power_state=$(dumpsys power 2>/dev/null | grep -m1 'mWakefulness=' \
    | sed 's/.*mWakefulness=//;s/[^A-Za-z].*//')
case "$power_state" in
    Asleep|Dozing) ;;
    *)
        echo "Ready. Lock the phone and turn the display off; the service will enforce Doze."
        exit 0
        ;;
esac

find_batt
case "$(cat "$BATT_DIR/status" 2>/dev/null)" in
    Discharging|Not\ charging) ;;
    *)
        echo "Paused while charging or when battery status is unavailable."
        exit 0
        ;;
esac

call_states=$(dumpsys telephony.registry 2>/dev/null \
    | sed -n 's/.*mCallState=\([0-9][0-9]*\).*/\1/p')
if [ -n "$call_states" ] && printf '%s\n' "$call_states" | grep -qv '^0$'; then
    echo "Paused during an active call."
    exit 0
fi

echo "Forcing deep sleep now..."
if dumpsys deviceidle force-idle deep >/dev/null 2>&1; then
    touch "$DOZE_FLAG" 2>/dev/null
else
    echo "Could not enter forced Doze on this device."
    exit 1
fi
sync 2>/dev/null
date +%s >"$LOG_DIR/last_enforce" 2>/dev/null

state=$(dumpsys deviceidle get deep 2>/dev/null)
echo "Done. Doze state: ${state:-unknown}"
