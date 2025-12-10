#!/system/bin/sh
# DeepDoze Enforcer v1.5 - Ultimate Battery Optimizer
# Aggressive Doze enforcement with system optimization

LOG_DIR="/data/adb/deepdoze"
LOG_FILE="$LOG_DIR/service.log"
PIDFILE="$LOG_DIR/service.pid"
LAST_ENFORCE="$LOG_DIR/last_enforce"
REFRESH_INTERVAL=1200  # 20 minutes in seconds
BOOT_WAIT_TIMEOUT=180   # seconds to wait for boot_complete

# Ensure data dir exists
mkdir -p "$LOG_DIR" 2>/dev/null

log() {
    # Rotate log if exceeds 300KB
    if [ -f "$LOG_FILE" ]; then
        size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt 307200 ]; then
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

# Avoid duplicates (service should run only once)
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

# Wait for boot complete
elapsed=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ] && [ "$elapsed" -lt "$BOOT_WAIT_TIMEOUT" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
done

log "✅ Service started (boot_wait ${elapsed}s)"

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

# Restrict all apps from background & wakelock (simple version)
restrict_all_apps() {
    for pkg in $(pm list packages | cut -d: -f2); do
        case "$pkg" in
            com.android.systemui|com.android.phone|com.android.settings|com.android.shell|android|com.android.providers.*)
                continue ;;
        esac
        appops set "$pkg" RUN_IN_BACKGROUND deny 2>/dev/null || true
        appops set "$pkg" WAKE_LOCK deny 2>/dev/null || true
    done
}

# Optimize GMS (Google Mobile Services)
optimize_gms() {
    local gms="com.google.android.gms"
    
    dumpsys deviceidle whitelist -"$gms" 2>/dev/null || true
    dumpsys deviceidle sys-whitelist -"$gms" 2>/dev/null || true
    appops set "$gms" RUN_ANY_IN_BACKGROUND ignore 2>/dev/null || true
    appops set "$gms" RUN_IN_BACKGROUND ignore 2>/dev/null || true
    appops set "$gms" START_FOREGROUND ignore 2>/dev/null || true
    appops set "$gms" WAKE_LOCK ignore 2>/dev/null || true
    appops set "$gms" MONITOR_LOCATION ignore 2>/dev/null || true
    appops set "$gms" SCHEDULE_EXACT_ALARM deny 2>/dev/null || true
    appops set "$gms" QUERY_ALL_PACKAGES deny 2>/dev/null || true
    cmd appops write-settings 2>/dev/null || true
}

# Disable Bluetooth profiles
disable_bluetooth() {
    setprop bluetooth.profile.a2dp.source.enabled false 2>/dev/null || true
    setprop bluetooth.profile.asha.central.enabled false 2>/dev/null || true
    setprop bluetooth.profile.gatt.enabled false 2>/dev/null || true
    setprop bluetooth.profile.hfp.ag.enabled false 2>/dev/null || true
    setprop bluetooth.profile.hid.device.enabled false 2>/dev/null || true
    setprop bluetooth.profile.hid.host.enabled false 2>/dev/null || true
    setprop bluetooth.profile.map.server.enabled false 2>/dev/null || true
    setprop bluetooth.profile.pan.nap.enabled false 2>/dev/null || true
    setprop bluetooth.profile.pan.panu.enabled false 2>/dev/null || true
    setprop bluetooth.profile.pbap.server.enabled false 2>/dev/null || true
    setprop bluetooth.profile.sap.server.enabled false 2>/dev/null || true
}

# Disable graphics optimization
disable_graphics_opt() {
    setprop debug.graphics.game_default_frame_rate.disabled false 2>/dev/null || true
    setprop debug.hwui.use_hint_manager false 2>/dev/null || true
    setprop debug.slsi_platform 0 2>/dev/null || true
}

# Disable dex optimization
disable_dex_opt() {
    setprop dalvik.vm.dex2oat-minidebuginfo false 2>/dev/null || true
    setprop dalvik.vm.minidebuginfo false 2>/dev/null || true
    setprop pm.dexopt.ab-ota verify 2>/dev/null || true
    setprop pm.dexopt.bg-dexopt verify 2>/dev/null || true
    setprop pm.dexopt.install verify 2>/dev/null || true
    setprop pm.dexopt.install-bulk verify 2>/dev/null || true
}

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
        log "📱 Screen OFF - enforcing optimizations"

        # Force deep sleep
        if has dumpsys; then
            dumpsys deviceidle force-idle deep 2>/dev/null || true
        fi

        # Execute all optimizations
        restrict_all_apps
        optimize_gms
        disable_bluetooth
        disable_graphics_opt
        disable_dex_opt

        # Memory cleanup
        sync 2>/dev/null
        if [ -w /proc/sys/vm/drop_caches ]; then
            echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true
        fi

        # Re-enforce periodically
        LAST_TIME=$(read_last_enforce)
        CURRENT_TIME=$(date +%s)
        TIME_DIFF=$((CURRENT_TIME - LAST_TIME))
        if [ "$TIME_DIFF" -ge "$REFRESH_INTERVAL" ]; then
            log "🔄 Refresh cycle (${TIME_DIFF}s) - re-enforcing"
            dumpsys deviceidle force-idle deep 2>/dev/null || true
            update_last_enforce
        fi

        sleep 300
    else
        sleep 30
    fi
done
