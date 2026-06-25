#!/system/bin/sh

LOG_DIR="/data/adb/deepdoze"
LOG_FILE="$LOG_DIR/service.log"
PIDFILE="$LOG_DIR/service.pid"
CONFIG_FILE="$LOG_DIR/config"
LAST_MAINTENANCE="$LOG_DIR/last_maintenance"
LAST_POWER_HOG_CHECK="$LOG_DIR/last_power_hog"
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
    has "$cmd" || log "warning: $cmd not found"
done

if [ -f "$PIDFILE" ]; then
    oldpid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
        log "service already running (pid $oldpid) - exiting"
        exit 0
    else
        rm -f "$PIDFILE"
    fi
fi

echo $$ >"$PIDFILE"
trap 'rm -f "$PIDFILE"; log "service stopping"; exit 0' INT TERM EXIT

elapsed=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != "1" ] && [ "$elapsed" -lt "$BOOT_WAIT_TIMEOUT" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
done

log "DeepDoze v3.2 started (boot_wait ${elapsed}s)"

load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        cat >"$CONFIG_FILE" <<'EOF'
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
EOF
        log "created configuration file"
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

list_user_apps() {
    pm list packages -3 2>/dev/null | cut -d: -f2
}

apply_boot_settings() {
    log "applying one-time framework settings"

    dumpsys deviceidle enable 2>/dev/null

    settings put global device_idle_constants "light_after_inactive_to=0,light_pre_idle_to=5000,light_idle_to=3600000,light_max_idle_to=43200000,locating_to=5000,location_accuracy=1000,inactive_to=0,sensing_to=0,motion_inactive_to=0,idle_after_inactive_to=0,idle_to=21600000,max_idle_to=172800000,quick_doze_delay_to=5000,min_time_to_alarm=300000,idle_pending_to=30000,max_idle_pending_to=120000,idle_pending_factor=2,idle_factor=2" 2>/dev/null

    settings put global automatic_power_save_mode 1 2>/dev/null
    settings put global app_standby_enabled 1 2>/dev/null
    settings put global forced_app_standby_enabled 1 2>/dev/null
    settings put global app_auto_restriction_enabled true 2>/dev/null
    settings put global adaptive_battery_management_enabled 1 2>/dev/null

    settings put global wifi_scan_always_enabled 0 2>/dev/null
    settings put global wifi_wakeup_enabled 0 2>/dev/null
    settings put global ble_scan_always_enabled 0 2>/dev/null
    settings put global wifi_networks_available_notification_on 0 2>/dev/null
    settings put global network_scoring_ui_enabled 0 2>/dev/null
    settings put global network_recommendations_enabled 0 2>/dev/null
    settings put global network_avoid_bad_wifi 0 2>/dev/null
    settings put global mobile_data_always_on 0 2>/dev/null

    settings put global stay_on_while_plugged_in 0 2>/dev/null

    current_location_mode=$(settings get secure location_mode 2>/dev/null)
    if [ "$current_location_mode" = "0" ]; then
        log "  location disabled by user - leaving untouched"
    else
        settings put secure location_mode 2 2>/dev/null
    fi
    settings put global location_background_throttle_interval_ms 600000 2>/dev/null
    settings put global location_background_throttle_proximity_alert_interval_ms 600000 2>/dev/null

    settings put global gms_checkin_timeout_min 1440 2>/dev/null
    settings put global assisted_gps_enabled 0 2>/dev/null
    settings put global wifi_watchdog_on 0 2>/dev/null

    current_sync=$(settings get global sync_enabled 2>/dev/null)
    if [ "$current_sync" = "1" ]; then
        log "  sync enabled by user - preserving"
    else
        settings put global sync_enabled 0 2>/dev/null
    fi

    settings put global sem_enhanced_cpu_responsiveness 0 2>/dev/null
    settings put global protect_battery 1 2>/dev/null
    settings put global oneplus_optimizer_enabled 1 2>/dev/null
    settings put global coloros_battery_saver_enabled 1 2>/dev/null

    log "  one-time settings applied"
}

kill_wakelocks() {
    [ "$enable_wakelock_killer" != "true" ] && return
    has dumpsys || return

    log "wakelock killer executing"
    killed=0

    pkgs=$(dumpsys power 2>/dev/null | grep -E "PARTIAL_WAKE_LOCK|FULL_WAKE_LOCK" | grep -oE "packageName=[^ ,]+" | cut -d= -f2 | sort -u)
    for pkg in $pkgs; do
        [ -z "$pkg" ] && continue
        is_system_critical "$pkg" && continue
        is_whitelisted "$pkg" && continue
        if am force-stop "$pkg" 2>/dev/null; then
            log "  killed wakelock holder: $pkg"
            killed=$((killed + 1))
        fi
    done

    [ "$killed" -gt 0 ] && log "  total wakelock holders stopped: $killed"
}

network_lockdown() {
    [ "$enable_network_lockdown" != "true" ] && return

    log "network lockdown executing"

    cmd netpolicy set restrict-background true 2>/dev/null
    settings put global wifi_scan_always_enabled 0 2>/dev/null
    settings put global wifi_wakeup_enabled 0 2>/dev/null
    settings put global ble_scan_always_enabled 0 2>/dev/null
    settings put global network_recommendations_enabled 0 2>/dev/null
    settings put global network_scoring_ui_enabled 0 2>/dev/null

    if [ "$aggression_level" = "nuclear" ]; then
        for pkg in $(list_user_apps); do
            is_whitelisted "$pkg" && continue
            is_system_critical "$pkg" && continue
            uid=$(dumpsys package "$pkg" 2>/dev/null | grep -m1 "userId=" | grep -oE "[0-9]+" | head -1)
            [ -n "$uid" ] && cmd netpolicy add restrict-background-blacklist "$uid" 2>/dev/null
        done
    fi

    log "  network lockdown complete"
}

crush_jobs() {
    [ "$enable_job_crusher" != "true" ] && return

    log "job scheduler crusher executing"

    for pkg in $(list_user_apps); do
        is_whitelisted "$pkg" && continue
        is_system_critical "$pkg" && continue
        cmd jobscheduler cancel "$pkg" 2>/dev/null
        am set-standby-bucket "$pkg" restricted 2>/dev/null
    done

    log "  jobs crushed, apps set to restricted bucket"
}

nuke_alarms() {
    [ "$enable_alarm_nuker" != "true" ] && return

    log "alarm nuker executing"

    for pkg in $(list_user_apps); do
        is_whitelisted "$pkg" && continue
        is_system_critical "$pkg" && continue
        am set-inactive "$pkg" true 2>/dev/null
        appops set "$pkg" SCHEDULE_EXACT_ALARM deny 2>/dev/null
        appops set "$pkg" USE_EXACT_ALARM deny 2>/dev/null
    done

    log "  alarms nuked"
}

kill_location() {
    [ "$enable_location_control" != "true" ] && return

    log "location control executing"

    current_location_mode=$(settings get secure location_mode 2>/dev/null)
    if [ "$current_location_mode" = "0" ]; then
        log "  location disabled by user - skipping"
        return
    fi

    settings put secure location_mode 2 2>/dev/null

    for pkg in $(list_user_apps); do
        is_whitelisted "$pkg" && continue
        is_system_critical "$pkg" && continue
        appops set "$pkg" ACCESS_BACKGROUND_LOCATION deny 2>/dev/null
    done

    log "  background location restricted"
}

freeze_sensors() {
    [ "$enable_sensor_freeze" != "true" ] && return

    log "sensor freeze executing"

    for pkg in $(list_user_apps); do
        is_whitelisted "$pkg" && continue
        is_system_critical "$pkg" && continue
        appops set "$pkg" BODY_SENSORS deny 2>/dev/null
        appops set "$pkg" ACTIVITY_RECOGNITION deny 2>/dev/null
        appops set "$pkg" HIGH_SAMPLING_RATE_SENSORS deny 2>/dev/null
    done

    log "  sensors frozen for background apps"
}

optimize_gms() {
    [ "$enable_gms_optimization" != "true" ] && return

    gms="com.google.android.gms"
    gsf="com.google.android.gsf"

    log "GMS optimization executing"

    dumpsys deviceidle whitelist -"$gms" 2>/dev/null
    dumpsys deviceidle whitelist -"$gsf" 2>/dev/null

    for op in RUN_ANY_IN_BACKGROUND RUN_IN_BACKGROUND START_FOREGROUND WAKE_LOCK BOOT_COMPLETED; do
        appops set "$gms" "$op" ignore 2>/dev/null
    done

    cmd app_hibernation set-state "$gms" true 2>/dev/null
    cmd app_hibernation set-state "$gsf" true 2>/dev/null

    am set-inactive --user 0 "$gms" true 2>/dev/null
    am set-standby-bucket --user 0 "$gms" restricted 2>/dev/null
    am send-trim-memory "$gms" COMPLETE 2>/dev/null

    am force-stop com.google.android.gms.persistent 2>/dev/null
    am force-stop com.google.android.gms.unstable 2>/dev/null

    settings put global gms_checkin_timeout_min 1440 2>/dev/null
    cmd jobscheduler cancel "$gms" 2>/dev/null

    log "  GMS restricted"
}

restrict_all_apps() {
    [ "$enable_app_restrictions" != "true" ] && return

    log "restricting background apps"

    count=0
    for pkg in $(list_user_apps); do
        is_system_critical "$pkg" && continue
        is_whitelisted "$pkg" && continue
        appops set "$pkg" RUN_IN_BACKGROUND deny 2>/dev/null
        appops set "$pkg" WAKE_LOCK deny 2>/dev/null
        appops set "$pkg" BOOT_COMPLETED deny 2>/dev/null
        am set-standby-bucket "$pkg" restricted 2>/dev/null
        am set-inactive "$pkg" true 2>/dev/null
        count=$((count + 1))
    done

    log "  restricted $count apps"
}

optimize_bluetooth() {
    [ "$enable_bluetooth_optimization" != "true" ] && return

    bt_state=$(settings get global bluetooth_on 2>/dev/null)
    if [ "$bt_state" = "0" ]; then
        log "bluetooth off - disabling profiles"
        for profile in a2dp.source asha.central hfp.ag hid.device hid.host map.server pan.nap pan.panu pbap.server sap.server; do
            setprop "bluetooth.profile.$profile.enabled" false 2>/dev/null
        done
    fi
}

detect_power_hogs() {
    [ "$enable_power_hog_detection" != "true" ] && return
    has dumpsys || return

    last_check=$(read_timestamp "$LAST_POWER_HOG_CHECK")
    current_time=$(date +%s)
    time_diff=$((current_time - last_check))
    [ "$time_diff" -lt "$POWER_HOG_CHECK_INTERVAL" ] && return

    log "detecting power hogs"

    uids=$(dumpsys batterystats 2>/dev/null | grep -oE "Uid u0a[0-9]+:" | grep -oE "u0a[0-9]+" | sort -u | head -10)
    for uid in $uids; do
        [ -z "$uid" ] && continue
        pkg=$(cmd package list packages --uid "$uid" 2>/dev/null | head -1 | cut -d: -f2)
        [ -z "$pkg" ] && continue
        is_system_critical "$pkg" && continue
        is_whitelisted "$pkg" && continue
        log "  power hog: $pkg - force stopping"
        am force-stop "$pkg" 2>/dev/null
        appops set "$pkg" RUN_IN_BACKGROUND deny 2>/dev/null
        appops set "$pkg" WAKE_LOCK deny 2>/dev/null
    done

    update_timestamp "$LAST_POWER_HOG_CHECK"
}

force_deep_doze() {
    has dumpsys || return
    log "forcing deep doze"
    dumpsys deviceidle enable 2>/dev/null
    dumpsys deviceidle force-idle deep 2>/dev/null
    log "  deep doze forced"
}

execute_screen_off_optimizations() {
    log "screen OFF - executing all optimizations"

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

    sync 2>/dev/null

    log "all optimizations complete"
}

run_periodic_maintenance() {
    last_time=$(read_timestamp "$LAST_MAINTENANCE")
    current_time=$(date +%s)
    time_diff=$((current_time - last_time))

    if [ "$time_diff" -ge "$MAINTENANCE_INTERVAL" ]; then
        log "periodic maintenance (${time_diff}s since last)"
        force_deep_doze
        kill_wakelocks
        optimize_gms
        detect_power_hogs
        update_timestamp "$LAST_MAINTENANCE"
    fi
}

get_screen_state() {
    state=""
    if has dumpsys; then
        state=$(dumpsys power 2>/dev/null | grep -m1 'mWakefulness=' | sed 's/.*mWakefulness=//' | sed 's/[^a-zA-Z].*//')
    fi
    case "$state" in
        Asleep|Dozing) echo "OFF" ;;
        *) echo "ON" ;;
    esac
}

apply_boot_settings

previous_screen_state=""
user_sync_enabled=$(settings get global sync_enabled 2>/dev/null)

while true; do
    screen_state=$(get_screen_state)

    if [ "$screen_state" = "OFF" ] && [ "$previous_screen_state" != "OFF" ]; then
        execute_screen_off_optimizations
        update_timestamp "$LAST_MAINTENANCE"
    elif [ "$screen_state" = "OFF" ]; then
        run_periodic_maintenance
    elif [ "$screen_state" = "ON" ] && [ "$previous_screen_state" = "OFF" ]; then
        log "screen ON - restoring user settings"
        if [ "$user_sync_enabled" = "1" ]; then
            settings put global sync_enabled 1 2>/dev/null
        fi
    fi

    previous_screen_state="$screen_state"
    sleep "$SCREEN_CHECK_INTERVAL"
done
