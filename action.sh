#!/system/bin/sh

MODDIR=${0%/*}
LOG_DIR="/data/adb/deepdoze"
PIDFILE="$LOG_DIR/service.pid"
mkdir -p "$LOG_DIR" 2>/dev/null

echo "DeepDoze Enforcer"

running=0
if [ -f "$PIDFILE" ]; then
    pid=$(cat "$PIDFILE" 2>/dev/null)
    [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && running=1
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

echo "Forcing deep sleep now..."
dumpsys deviceidle enable 2>/dev/null
dumpsys deviceidle force-idle deep 2>/dev/null
sync 2>/dev/null
date +%s >"$LOG_DIR/last_enforce" 2>/dev/null

state=$(dumpsys deviceidle get deep 2>/dev/null)
echo "Done. Doze state: ${state:-unknown}"
