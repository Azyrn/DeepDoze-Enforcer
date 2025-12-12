#!/system/bin/sh
# DeepDoze Enforcer - Advanced Battery Optimizer #skeler

LOG_DIR="/data/adb/deepdoze"
LOG_FILE="$LOG_DIR/service.log"
PIDFILE="$LOG_DIR/service.pid"
CONFIG_FILE="$LOG_DIR/config"
LAST_MAINTENANCE="$LOG_DIR/last_maintenance"
LAST_POWER_HOG_CHECK="$LOG_DIR/last_power_hog"
MAINTENANCE_INTERVAL=3600
POWER_HOG_CHECK_INTERVAL=3600
BOOT_WAIT_TIMEOUT=180
SCREEN_CHECK_INTERVAL=60

mkdir -p "$LOG_DIR" 2>/dev/null

log() {
    if [ -f "$LOG_FILE" ]; then
        size=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt 102400 ]; then
            mv "$LOG_FILE" "$LOG_FILE".1 2>/dev/null
        fi
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

has() { command -v "$1" >/dev/null 2>&1; }

for cmd in dumpsys pm appops settings setprop getprop; do
    if ! has "$cmd"; then
        log "Warning: $cmd not found - functionality may be limited"
    fi
done

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

elapsed=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ] && [ "$elapsed" -lt "$BOOT_WAIT_TIMEOUT" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
done

log "✅ Service started (boot_wait ${elapsed}s)"

# Load or create default configuration
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat > "$CONFIG_FILE" <<EOF
# DeepDoze Enforcer Configuration
# Edit this file to customize behavior

# Whitelist: Apps that should NOT be restricted (space-separated)
whitelist="com.whatsapp org.telegram.messenger com.android.mms com.android.contacts com.android.vending com.google.android.gsf com.android.deskclock"

# Enable/disable specific optimization modules
enable_gms_optimization=true
enable_app_restrictions=true
enable_bluetooth_optimization=true
enable_power_hog_detection=true

# Intervals (in seconds)
maintenance_interval=3600
power_hog_check_interval=3600
screen_check_interval=60
EOF
        log "Created default configuration file"
    fi
    
    . "$CONFIG_FILE" 2>/dev/null || {
        whitelist="com.whatsapp org.telegram.messenger com.android.mms com.android.contacts com.android.vending com.google.android.gsf com.android.deskclock"
        enable_gms_optimization=true
        enable_app_restrictions=true
        enable_bluetooth_optimization=true
        enable_power_hog_detection=true
        maintenance_interval=3600
        power_hog_check_interval=3600
        screen_check_interval=60
    }
    
    MAINTENANCE_INTERVAL=${maintenance_interval:-3600}
    POWER_HOG_CHECK_INTERVAL=${power_hog_check_interval:-3600}
    SCREEN_CHECK_INTERVAL=${screen_check_interval:-60}
}

load_config

if [ ! -f "$LAST_MAINTENANCE" ]; then
    date +%s > "$LAST_MAINTENANCE" 2>/dev/null || touch "$LAST_MAINTENANCE"
fi

if [ ! -f "$LAST_POWER_HOG_CHECK" ]; then
    date +%s > "$LAST_POWER_HOG_CHECK" 2>/dev/null || touch "$LAST_POWER_HOG_CHECK"
fi

read_timestamp() {
    if [ -f "$1" ]; then
        cat "$1" 2>/dev/null || echo 0
    else
        echo 0
    fi
}

update_timestamp() {
    date +%s > "$1" 2>/dev/null || touch "$1"
}

restrict_all_apps() {
    [ "$enable_app_restrictions" != "true" ] && return
    
    for pkg in $(pm list packages -e 2>/dev/null | cut -d: -f2); do
        case "$pkg" in
            com.android.systemui|com.android.phone|com.android.settings|com.android.shell|android|com.android.providers.*)
                continue ;;
        esac
        
        case " $whitelist " in
            *" $pkg "*) continue ;;
        esac
        
        appops set "$pkg" RUN_IN_BACKGROUND deny 2>/dev/null &
        appops set "$pkg" WAKE_LOCK deny 2>/dev/null &
    done
    wait
}

optimize_gms() {
    [ "$enable_gms_optimization" != "true" ] && return
    
    local gms="com.google.android.gms"
    
    dumpsys deviceidle whitelist -"$gms" 2>/dev/null || true
    dumpsys deviceidle sys-whitelist -"$gms" 2>/dev/null || true
    cmd appops set "$gms" RUN_ANY_IN_BACKGROUND ignore 2>/dev/null || true
    cmd appops set "$gms" RUN_IN_BACKGROUND ignore 2>/dev/null || true
    cmd appops set "$gms" START_FOREGROUND ignore 2>/dev/null || true
    cmd app_hibernation set-state "$gms" true 2>/dev/null || true
    cmd activity send-trim-memory "$(pidof $gms 2>/dev/null)" COMPLETE 2>/dev/null || true
    cmd activity make-uid-idle --user 0 "$gms" 2>/dev/null || true
    cmd activity freeze --sticky "$(pidof $gms 2>/dev/null)" 2>/dev/null || true
    am clear-exit-info all "$gms" 2>/dev/null || true
    am set-inactive --user 0 "$gms" true 2>/dev/null || true
    am set-standby-bucket --user 0 "$gms" restricted 2>/dev/null || true
    am service-restart-backoff disable "$gms" 2>/dev/null || true
    am set-bg-restriction-level --user 0 "$gms" hibernation 2>/dev/null || true
    am set-foreground-service-delegate --user 0 "$gms" stop 2>/dev/null || true
}

optimize_bluetooth() {
    [ "$enable_bluetooth_optimization" != "true" ] && return
    
    local bt_state=$(settings get global bluetooth_on 2>/dev/null)
    if [ "$bt_state" = "0" ]; then
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
    fi
}

detect_power_hogs() {
    [ "$enable_power_hog_detection" != "true" ] && return
    
    last_check=$(read_timestamp "$LAST_POWER_HOG_CHECK")
    current_time=$(date +%s)
    time_diff=$((current_time - last_check))
    
    if [ "$time_diff" -lt "$POWER_HOG_CHECK_INTERVAL" ]; then
        return
    fi
    
    if has dumpsys; then
        power_hogs=$(dumpsys batterystats 2>/dev/null | grep -E "Uid u0a[0-9]+:" | head -5 | sed 's/.*Uid //' | sed 's/:.*//')
        
        for uid_entry in $power_hogs; do
            pkg=$(cmd package list packages --uid "$uid_entry" 2>/dev/null | head -1 | cut -d: -f2)
            
            [ -z "$pkg" ] && continue
            
            case "$pkg" in
                android|com.android.*|com.google.android.gms)
                    continue ;;
            esac
            
            case " $whitelist " in
                *" $pkg "*) continue ;;
            esac
            
            log "⚠️ Power hog detected: $pkg - restricting"
            appops set "$pkg" RUN_IN_BACKGROUND ignore 2>/dev/null || true
            appops set "$pkg" WAKE_LOCK deny 2>/dev/null || true
        done
    fi
    
    update_timestamp "$LAST_POWER_HOG_CHECK"
}

execute_heavy_optimizations() {
    log "📱 Screen OFF - executing heavy optimizations"

    if has dumpsys; then
        dumpsys deviceidle force-idle deep 2>/dev/null || true
    fi

    restrict_all_apps
    optimize_gms
    optimize_bluetooth
    detect_power_hogs

    sync 2>/dev/null
}

run_periodic_maintenance() {
    last_time=$(read_timestamp "$LAST_MAINTENANCE")
    current_time=$(date +%s)
    time_diff=$((current_time - last_time))
    
    if [ "$time_diff" -ge "$MAINTENANCE_INTERVAL" ]; then
        log "🔄 Periodic maintenance (${time_diff}s since last)"
        if has dumpsys; then
            dumpsys deviceidle force-idle deep 2>/dev/null || true
        fi
        update_timestamp "$LAST_MAINTENANCE"
    fi
}

get_screen_state() {
    local state=""
    if has dumpsys; then
        state=$(dumpsys power 2>/dev/null | grep -m1 'mWakefulness=' | sed 's/.*mWakefulness=//' | sed 's/[^a-zA-Z].*//')
    fi

    case "$state" in
        Asleep|Dozing)
            echo "OFF" ;;
        *)
            echo "ON" ;;
    esac
}

previous_screen_state=""

while true; do
    screen_state=$(get_screen_state)

    screen_turned_off=false
    if [ "$screen_state" = "OFF" ] && [ "$previous_screen_state" != "OFF" ]; then
        screen_turned_off=true
    fi

    if [ "$screen_state" = "OFF" ]; then
        if [ "$screen_turned_off" = "true" ]; then
            execute_heavy_optimizations
            update_timestamp "$LAST_MAINTENANCE"
        else
            run_periodic_maintenance
        fi
        
        sleep "$SCREEN_CHECK_INTERVAL"
    else
        sleep "$SCREEN_CHECK_INTERVAL"
    fi

    previous_screen_state="$screen_state"
done