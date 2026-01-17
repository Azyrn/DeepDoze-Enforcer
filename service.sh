#!/system/bin/sh
# DeepDoze Enforcer v3.0 - Ultimate Battery Saver
# Author: skeler
# No kernel modifications - Framework-level only

LOG_DIR="/data/adb/deepdoze"
LOG_FILE="$LOG_DIR/service.log"
PIDFILE="$LOG_DIR/service.pid"
CONFIG_FILE="$LOG_DIR/config"
LAST_MAINTENANCE="$LOG_DIR/last_maintenance"
LAST_POWER_HOG_CHECK="$LOG_DIR/last_power_hog"
WAKELOCK_CACHE="$LOG_DIR/wakelock_cache"
MAINTENANCE_INTERVAL=1800
POWER_HOG_CHECK_INTERVAL=1800
BOOT_WAIT_TIMEOUT=180
SCREEN_CHECK_INTERVAL=30

mkdir -p "$LOG_DIR" 2>/dev/null

log() {
    if [ -f "$LOG_FILE" ]; then
        size=$(wc -c <"$LOG_FILE" 2>/dev/null || echo 0)
        if [ "$size" -gt 204800 ]; then
            mv "$LOG_FILE" "$LOG_FILE".1 2>/dev/null
        fi
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >>"$LOG_FILE"
}

has() { command -v "$1" >/dev/null 2>&1; }

for cmd in dumpsys pm appops settings setprop getprop cmd am; do
    if ! has "$cmd"; then
        log "⚠️ Warning: $cmd not found"
    fi
done

# PID management
if [ -f "$PIDFILE" ]; then
    oldpid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
        log "Service already running (pid $oldpid) - exiting"
        exit 0
    else
        rm -f "$PIDFILE"
    fi
fi

echo $$ >"$PIDFILE"
trap 'rm -f "$PIDFILE"; log "Service stopping"; exit 0' INT TERM EXIT

# Wait for boot
elapsed=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ] && [ "$elapsed" -lt "$BOOT_WAIT_TIMEOUT" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
done

log "✅ DeepDoze v3.0 started (boot_wait ${elapsed}s)"

# ============================================================================
# CONFIGURATION
# ============================================================================

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat >"$CONFIG_FILE" <<'EOF'
# DeepDoze Enforcer v3.0 Configuration
# =====================================

# Whitelist: Apps that should NOT be restricted (space-separated)
# Add your critical notification apps here
whitelist="com.whatsapp org.telegram.messenger com.android.mms com.android.phone com.android.contacts com.android.vending com.google.android.gsf com.android.deskclock com.android.systemui com.android.settings"

# Aggression level: mild | moderate | nuclear
aggression_level="nuclear"

# Feature toggles (true/false)
enable_gms_optimization=true
enable_app_restrictions=true
enable_bluetooth_optimization=true
enable_power_hog_detection=true
enable_wakelock_killer=true
enable_network_lockdown=true
enable_job_crusher=true
enable_alarm_nuker=true
enable_location_control=true
enable_sensor_freeze=true

# Intervals (in seconds)
maintenance_interval=1800
power_hog_check_interval=1800
screen_check_interval=30
EOF
        log "Created v3.0 configuration file"
    fi

    . "$CONFIG_FILE" 2>/dev/null || {
        whitelist="com.whatsapp org.telegram.messenger com.android.mms com.android.phone com.android.contacts com.android.vending com.google.android.gsf com.android.deskclock com.android.systemui com.android.settings"
        aggression_level="nuclear"
        enable_gms_optimization=true
        enable_app_restrictions=true
        enable_bluetooth_optimization=true
        enable_power_hog_detection=true
        enable_wakelock_killer=true
        enable_network_lockdown=true
        enable_job_crusher=true
        enable_alarm_nuker=true
        enable_location_control=true
        enable_sensor_freeze=true
        maintenance_interval=1800
        power_hog_check_interval=1800
        screen_check_interval=30
    }

    MAINTENANCE_INTERVAL=${maintenance_interval:-1800}
    POWER_HOG_CHECK_INTERVAL=${power_hog_check_interval:-1800}
    SCREEN_CHECK_INTERVAL=${screen_check_interval:-30}
}

load_config

# Initialize timestamps
for ts_file in "$LAST_MAINTENANCE" "$LAST_POWER_HOG_CHECK"; do
    [ ! -f "$ts_file" ] && date +%s >"$ts_file" 2>/dev/null
done

read_timestamp() {
    [ -f "$1" ] && cat "$1" 2>/dev/null || echo 0
}

update_timestamp() {
    date +%s >"$1" 2>/dev/null
}

is_whitelisted() {
    case " $whitelist " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

is_system_critical() {
    case "$1" in
        android|com.android.systemui|com.android.phone|com.android.settings|com.android.shell|com.android.providers.*|com.android.inputmethod.*|com.google.android.inputmethod.*)
            return 0 ;;
        *)
            return 1 ;;
    esac
}

# ============================================================================
# MODULE 1: WAKELOCK KILLER
# ============================================================================

kill_wakelocks() {
    [ "$enable_wakelock_killer" != "true" ] && return

    log "🔪 Wakelock Killer executing..."
    local killed=0

    # Parse active wakelocks from power service
    if has dumpsys; then
        dumpsys power 2>/dev/null | grep -E "PARTIAL_WAKE_LOCK|FULL_WAKE_LOCK" | while read -r line; do
            pkg=$(echo "$line" | grep -oE "packageName=[^ ]+" | cut -d= -f2 | tr -d ',')
            [ -z "$pkg" ] && continue
            is_system_critical "$pkg" && continue
            is_whitelisted "$pkg" && continue

            # Force stop the wakelock holder
            am force-stop "$pkg" 2>/dev/null && {
                log "  ✓ Killed wakelock: $pkg"
                killed=$((killed + 1))
            }
        done

        # Also check for partial wakelocks via batterystats
        dumpsys batterystats 2>/dev/null | grep -E "Wake lock.*held" | grep -oE "\"[^\"]+\"" | tr -d '"' | sort -u | while read -r tag; do
            # Extract package from wakelock tag if possible
            pkg=$(echo "$tag" | grep -oE "^[a-z]+\.[a-z0-9._]+" | head -1)
            [ -z "$pkg" ] && continue
            is_system_critical "$pkg" && continue
            is_whitelisted "$pkg" && continue

            am force-stop "$pkg" 2>/dev/null
        done
    fi

    [ "$killed" -gt 0 ] && log "  Total wakelocks killed: $killed"
}

# ============================================================================
# MODULE 2: NETWORK LOCKDOWN
# ============================================================================

network_lockdown() {
    [ "$enable_network_lockdown" != "true" ] && return

    log "🌐 Network Lockdown executing..."

    # Disable global sync
    settings put global sync_enabled 0 2>/dev/null

    # Enable restrict background data
    cmd netpolicy set restrict-background true 2>/dev/null

    # Disable WiFi scanning
    settings put global wifi_scan_always_enabled 0 2>/dev/null
    settings put global wifi_wakeup_enabled 0 2>/dev/null

    # Disable BLE scanning
    settings put global ble_scan_always_enabled 0 2>/dev/null

    # Disable network recommendations
    settings put global network_recommendations_enabled 0 2>/dev/null
    settings put global network_scoring_ui_enabled 0 2>/dev/null

    # Restrict per-app background data for non-whitelisted apps
    if [ "$aggression_level" = "nuclear" ]; then
        for pkg in $(pm list packages -3 2>/dev/null | cut -d: -f2); do
            is_whitelisted "$pkg" && continue
            is_system_critical "$pkg" && continue

            uid=$(dumpsys package "$pkg" 2>/dev/null | grep "userId=" | head -1 | grep -oE "[0-9]+")
            [ -n "$uid" ] && cmd netpolicy set metered-network-blacklist "$uid" true 2>/dev/null
        done
    fi

    log "  ✓ Network lockdown complete"
}

network_restore() {
    # Restore network when screen on (optional)
    settings put global sync_enabled 1 2>/dev/null
}

# ============================================================================
# MODULE 3: JOB SCHEDULER CRUSHER
# ============================================================================

crush_jobs() {
    [ "$enable_job_crusher" != "true" ] && return

    log "💥 Job Scheduler Crusher executing..."

    for pkg in $(pm list packages -3 2>/dev/null | cut -d: -f2); do
        is_whitelisted "$pkg" && continue
        is_system_critical "$pkg" && continue

        # Cancel all pending jobs
        cmd jobscheduler cancel "$pkg" 2>/dev/null

        # Set to restricted standby bucket (most aggressive)
        am set-standby-bucket "$pkg" restricted 2>/dev/null

        # Disable expedited jobs
        cmd jobscheduler set-job-quota "$pkg" 0 2>/dev/null
    done

    # Force idle all apps
    cmd activity make-package-idle --user 0 2>/dev/null

    log "  ✓ Jobs crushed, apps set to restricted bucket"
}

# ============================================================================
# MODULE 4: ALARM NUKER
# ============================================================================

nuke_alarms() {
    [ "$enable_alarm_nuker" != "true" ] && return

    log "⏰ Alarm Nuker executing..."

    # Get pending alarms and cancel for non-whitelisted apps
    if has dumpsys; then
        dumpsys alarm 2>/dev/null | grep -E "type=[0-3].*when=" | while read -r line; do
            pkg=$(echo "$line" | grep -oE "pkg=[^ ]+" | cut -d= -f2)
            [ -z "$pkg" ] && continue
            is_whitelisted "$pkg" && continue
            is_system_critical "$pkg" && continue

            # Force app to stopped state (cancels alarms)
            am set-inactive "$pkg" true 2>/dev/null
        done
    fi

    # Disable alarm wakeups for restricted apps
    for pkg in $(pm list packages -3 2>/dev/null | cut -d: -f2); do
        is_whitelisted "$pkg" && continue
        is_system_critical "$pkg" && continue

        appops set "$pkg" SCHEDULE_EXACT_ALARM deny 2>/dev/null
        appops set "$pkg" USE_EXACT_ALARM deny 2>/dev/null
    done

    log "  ✓ Alarms nuked"
}

# ============================================================================
# MODULE 5: LOCATION ASSASSIN
# ============================================================================

kill_location() {
    [ "$enable_location_control" != "true" ] && return

    log "📍 Location Assassin executing..."

    # Set location mode to battery saving (network only, no GPS)
    settings put secure location_mode 2 2>/dev/null

    # Disable background location for non-whitelisted apps
    for pkg in $(pm list packages -3 2>/dev/null | cut -d: -f2); do
        is_whitelisted "$pkg" && continue
        is_system_critical "$pkg" && continue

        appops set "$pkg" ACCESS_BACKGROUND_LOCATION deny 2>/dev/null
        appops set "$pkg" ACCESS_FINE_LOCATION ignore 2>/dev/null
        appops set "$pkg" ACCESS_COARSE_LOCATION ignore 2>/dev/null
    done

    # Stop location services for GMS
    am force-stop com.google.android.gms.location 2>/dev/null || true

    log "  ✓ Location services killed"
}

# ============================================================================
# MODULE 6: SENSOR FREEZE
# ============================================================================

freeze_sensors() {
    [ "$enable_sensor_freeze" != "true" ] && return

    log "🧊 Sensor Freeze executing..."

    # Restrict sensor permissions for background apps
    for pkg in $(pm list packages -3 2>/dev/null | cut -d: -f2); do
        is_whitelisted "$pkg" && continue
        is_system_critical "$pkg" && continue

        appops set "$pkg" BODY_SENSORS deny 2>/dev/null
        appops set "$pkg" ACTIVITY_RECOGNITION deny 2>/dev/null
        appops set "$pkg" HIGH_SAMPLING_RATE_SENSORS deny 2>/dev/null
    done

    # Disable sensor batching wakeups
    settings put global sensors_suspend_enabled 1 2>/dev/null

    log "  ✓ Sensors frozen"
}

# ============================================================================
# MODULE 7: NUCLEAR GMS OPTIMIZATION
# ============================================================================

optimize_gms() {
    [ "$enable_gms_optimization" != "true" ] && return

    local gms="com.google.android.gms"
    local gsf="com.google.android.gsf"

    log "☢️ Nuclear GMS Optimization executing..."

    # Remove from doze whitelist
    dumpsys deviceidle whitelist -"$gms" 2>/dev/null
    dumpsys deviceidle whitelist -"$gsf" 2>/dev/null
    dumpsys deviceidle sys-whitelist -"$gms" 2>/dev/null
    dumpsys deviceidle sys-whitelist -"$gsf" 2>/dev/null

    # Restrict all background operations
    for op in RUN_ANY_IN_BACKGROUND RUN_IN_BACKGROUND START_FOREGROUND WAKE_LOCK BOOT_COMPLETED; do
        cmd appops set "$gms" "$op" ignore 2>/dev/null
    done

    # Hibernation (Android 12+)
    cmd app_hibernation set-state "$gms" true 2>/dev/null
    cmd app_hibernation set-state "$gsf" true 2>/dev/null

    # Force idle and freeze
    am set-inactive --user 0 "$gms" true 2>/dev/null
    am set-standby-bucket --user 0 "$gms" restricted 2>/dev/null
    am set-bg-restriction-level --user 0 "$gms" hibernation 2>/dev/null

    # Trim memory aggressively
    local gms_pid=$(pidof "$gms" 2>/dev/null)
    [ -n "$gms_pid" ] && {
        cmd activity send-trim-memory "$gms_pid" COMPLETE 2>/dev/null
        cmd activity freeze --sticky "$gms_pid" 2>/dev/null
    }

    # Kill GMS background services
    am force-stop com.google.android.gms.persistent 2>/dev/null
    am force-stop com.google.android.gms.unstable 2>/dev/null

    # Disable GMS checkin (reduces wakeups)
    settings put global gms_checkin_timeout_min 1440 2>/dev/null

    # Cancel all GMS jobs
    cmd jobscheduler cancel "$gms" 2>/dev/null

    log "  ✓ GMS nuked"
}

# ============================================================================
# MODULE 8: APP RESTRICTIONS
# ============================================================================

restrict_all_apps() {
    [ "$enable_app_restrictions" != "true" ] && return

    log "🔒 Restricting background apps..."

    local count=0
    for pkg in $(pm list packages -3 2>/dev/null | cut -d: -f2); do
        is_system_critical "$pkg" && continue
        is_whitelisted "$pkg" && continue

        # Deny background operations
        appops set "$pkg" RUN_IN_BACKGROUND deny 2>/dev/null &
        appops set "$pkg" WAKE_LOCK deny 2>/dev/null &
        appops set "$pkg" BOOT_COMPLETED deny 2>/dev/null &

        # Set to restricted bucket
        am set-standby-bucket "$pkg" restricted 2>/dev/null &

        # Make inactive
        am set-inactive "$pkg" true 2>/dev/null &

        count=$((count + 1))
    done
    wait

    log "  ✓ Restricted $count apps"
}

# ============================================================================
# MODULE 9: BLUETOOTH OPTIMIZATION
# ============================================================================

optimize_bluetooth() {
    [ "$enable_bluetooth_optimization" != "true" ] && return

    local bt_state=$(settings get global bluetooth_on 2>/dev/null)
    if [ "$bt_state" = "0" ]; then
        log "📶 Disabling Bluetooth profiles..."

        for profile in a2dp.source asha.central gatt hfp.ag hid.device hid.host map.server pan.nap pan.panu pbap.server sap.server; do
            setprop "bluetooth.profile.$profile.enabled" false 2>/dev/null
        done
    fi
}

# ============================================================================
# MODULE 10: POWER HOG DETECTION
# ============================================================================

detect_power_hogs() {
    [ "$enable_power_hog_detection" != "true" ] && return

    last_check=$(read_timestamp "$LAST_POWER_HOG_CHECK")
    current_time=$(date +%s)
    time_diff=$((current_time - last_check))

    [ "$time_diff" -lt "$POWER_HOG_CHECK_INTERVAL" ] && return

    log "🔍 Detecting power hogs..."

    if has dumpsys; then
        dumpsys batterystats 2>/dev/null | grep -E "Uid u0a[0-9]+:" | head -10 | while read -r line; do
            uid=$(echo "$line" | grep -oE "u0a[0-9]+" | head -1)
            [ -z "$uid" ] && continue

            pkg=$(cmd package list packages --uid "$uid" 2>/dev/null | head -1 | cut -d: -f2)
            [ -z "$pkg" ] && continue

            is_system_critical "$pkg" && continue
            is_whitelisted "$pkg" && continue

            log "  ⚠️ Power hog: $pkg - force stopping"
            am force-stop "$pkg" 2>/dev/null
            appops set "$pkg" RUN_IN_BACKGROUND deny 2>/dev/null
            appops set "$pkg" WAKE_LOCK deny 2>/dev/null
        done
    fi

    update_timestamp "$LAST_POWER_HOG_CHECK"
}

# ============================================================================
# DOZE ENFORCEMENT
# ============================================================================

force_deep_doze() {
    log "💤 Forcing Deep Doze..."

    if has dumpsys; then
        # Force deep idle immediately
        dumpsys deviceidle force-idle deep 2>/dev/null

        # Enable all doze features
        dumpsys deviceidle enable all 2>/dev/null

        # Unforce from light idle to go deeper
        dumpsys deviceidle unforce 2>/dev/null
        sleep 1
        dumpsys deviceidle force-idle deep 2>/dev/null
    fi

    log "  ✓ Deep Doze forced"
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

execute_screen_off_optimizations() {
    log "📱 ═══════════════════════════════════════"
    log "📱 Screen OFF - Executing ALL optimizations"
    log "📱 ═══════════════════════════════════════"

    # Execute all modules
    force_deep_doze
    kill_wakelocks
    restrict_all_apps
    optimize_gms
    network_lockdown
    crush_jobs
    nuke_alarms
    kill_location
    freeze_sensors
    optimize_bluetooth
    detect_power_hogs

    # Sync filesystem
    sync 2>/dev/null

    log "📱 ✅ All optimizations complete"
}

run_periodic_maintenance() {
    last_time=$(read_timestamp "$LAST_MAINTENANCE")
    current_time=$(date +%s)
    time_diff=$((current_time - last_time))

    if [ "$time_diff" -ge "$MAINTENANCE_INTERVAL" ]; then
        log "🔄 Periodic maintenance (${time_diff}s since last)"

        force_deep_doze
        kill_wakelocks
        optimize_gms
        detect_power_hogs

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

# ============================================================================
# MAIN LOOP
# ============================================================================

previous_screen_state=""

while true; do
    screen_state=$(get_screen_state)

    if [ "$screen_state" = "OFF" ] && [ "$previous_screen_state" != "OFF" ]; then
        # Screen just turned off - full optimization
        execute_screen_off_optimizations
        update_timestamp "$LAST_MAINTENANCE"
    elif [ "$screen_state" = "OFF" ]; then
        # Screen still off - periodic maintenance
        run_periodic_maintenance
    fi

    previous_screen_state="$screen_state"
    sleep "$SCREEN_CHECK_INTERVAL"
done