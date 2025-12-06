#!/system/bin/sh
# DeepDoze Enforcer v1.1 - Improved Main Service
# Re-enforce Doze every REFRESH_INTERVAL seconds when screen is off

LOG_DIR="/data/adb/deepdoze"
LOG_FILE="$LOG_DIR/service.log"
PIDFILE="$LOG_DIR/service.pid"
LAST_ENFORCE="$LOG_DIR/last_enforce"
REFRESH_INTERVAL=1200  # 20 minutes in seconds
BOOT_WAIT_TIMEOUT=180   # seconds to wait for boot_complete

# Ensure data dir exists
mkdir -p "$LOG_DIR" 2>/dev/null

log() {
    # Rotate if log > 200KB (simple)
    if [ -f "$LOG_FILE" ]; then
        size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt 204800 ]; then
            mv "$LOG_FILE" "$LOG_FILE".1 2>/dev/null
        fi
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

# Check binaries
has() { command -v "$1" >/dev/null 2>&1; }

for cmd in dumpsys pm appops settings setprop getprop; do
    if ! has "$cmd"; then
        log "Warning: $cmd not found in PATH; functionality may be limited"
    fi
done

# Avoid duplicates
if [ -f "$PIDFILE" ]; then
    oldpid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
        log "Service already running (pid $oldpid) - exiting"
        exit 0
    else
        rm -f "$PIDFILE"
    fi
fi

echo $$ > "$PIDFILE"
trap 'rm -f "$PIDFILE"; log "Service stopping"; exit 0' INT TERM EXIT

# Wait for boot complete (better than fixed sleep)
elapsed=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ] && [ "$elapsed" -lt "$BOOT_WAIT_TIMEOUT" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
done

log "Service started (boot_wait ${elapsed}s)"

# Initialize last_enforce file if missing
if [ ! -f "$LAST_ENFORCE" ]; then
    echo "$(date +%s)" > "$LAST_ENFORCE" 2>/dev/null || touch "$LAST_ENFORCE"
fi

# Helper: read last enforce timestamp (seconds)
read_last_enforce() {
    if [ -f "$LAST_ENFORCE" ]; then
        cat "$LAST_ENFORCE" 2>/dev/null || stat -c %Y "$LAST_ENFORCE" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

# Helper: update last enforce timestamp
update_last_enforce() {
    echo "$(date +%s)" > "$LAST_ENFORCE" 2>/dev/null || touch "$LAST_ENFORCE"
}

# Default whitelist (update according to real package names)
WHITELIST="com.whatsapp org.telegram.messenger com.android.mms com.android.contacts"

# Main loop
while true; do
    # Get screen state - try a couple of parsers for compatibility
    SCREEN_STATE=""
    if has dumpsys; then
        SCREEN_STATE=$(dumpsys power 2>/dev/null | grep -m1 -E 'Display|mWakefulness|mHoldingDisplaySuspendBlocker' | grep -o -E 'state=[[:alnum:]_]*|mWakefulness=[[:alnum:]_]*' 2>/dev/null | head -n1 | sed -E 's/.*(state|mWakefulness)=//; s/^\s+//')
        # Fallback: check 'mWakefulness=' specifically
        if [ -z "$SCREEN_STATE" ]; then
            SCREEN_STATE=$(dumpsys power 2>/dev/null | grep -m1 -E 'mWakefulness=' | sed -E 's/.*mWakefulness=//; s/\s.*//')
        fi
    fi

    # Normalize SCREEN_STATE to uppercase or OFF
    case "$SCREEN_STATE" in
        OFF|off|Asleep|Doze)
            SCREEN_STATE="OFF"
            ;;
        *)
            SCREEN_STATE="ON"
            ;;
    esac

    if [ "$SCREEN_STATE" = "OFF" ]; then
        log "Screen OFF detected - applying optimizations"

        # Force deep sleep (if available)
        if has dumpsys; then
            dumpsys deviceidle force-idle deep 2>/dev/null || log "dumpsys force-idle failed or unsupported"
        fi

        # Disable tracing if possible
        if has setprop; then
            setprop persist.traced.enable 0 2>/dev/null || log "setprop persist.traced.enable failed"
        fi
        if has stop; then
            stop traced 2>/dev/null || true
        fi

        # Restrict background apps (whitelist applied)
        if has pm && has appops; then
            # iterate safely
            pm list packages -3 2>/dev/null | sed 's/^package://g' | while IFS= read -r pkg; do
                skip=0
                for w in $WHITELIST; do
                    [ "$pkg" = "$w" ] && skip=1 && break
                done
                if [ "$skip" -eq 1 ]; then
                    continue
                fi
                appops set "$pkg" RUN_IN_BACKGROUND ignore 2>/dev/null || true
            done
        fi

        # Memory cleanup (best-effort)
        sync 2>/dev/null
        if [ -w /proc/sys/vm/drop_caches ]; then
            echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || log "drop_caches write failed"
        fi

        # Re-enforce periodically
        LAST_TIME=$(read_last_enforce)
        CURRENT_TIME=$(date +%s)
        TIME_DIFF=$((CURRENT_TIME - LAST_TIME))
        if [ "$TIME_DIFF" -ge "$REFRESH_INTERVAL" ]; then
            log "Refresh interval passed ($TIME_DIFF s) - re-enforcing Doze"
            if has dumpsys; then
                dumpsys deviceidle force-idle deep 2>/dev/null || log "dumpsys force-idle failed on refresh"
            fi
            update_last_enforce
        fi

        log "Optimizations applied - sleeping 300s"
        sleep 300
    else
        # Screen ON - quick check
        sleep 30
    fi
done
