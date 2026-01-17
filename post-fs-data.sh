#!/system/bin/sh
# DeepDoze Enforcer v3.0 - Boot-Time Initialization
# Author: skeler

MODDIR=${0%/*}
LOG_DIR="/data/adb/deepdoze"
LOG_FILE="$LOG_DIR/boot.log"

mkdir -p "$LOG_DIR" 2>/dev/null

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >>"$LOG_FILE" 2>/dev/null
}

log "🚀 DeepDoze Enforcer v3.0 starting..."

# ============================================================================
# TRACING DISABLE (Reduces CPU overhead)
# ============================================================================

log "⚙️ Disabling system tracing..."

setprop persist.traced.enable 0 2>/dev/null
setprop sys.trace.traced_started 0 2>/dev/null
setprop debug.atrace.tags.enableflags 0 2>/dev/null
setprop persist.sys.trace.default 0 2>/dev/null

# Stop tracing daemons
stop traced 2>/dev/null || true
stop traced_probes 2>/dev/null || true

log "  ✓ Tracing disabled"

# ============================================================================
# AGGRESSIVE DOZE CONFIGURATION
# ============================================================================

log "⚙️ Configuring aggressive Doze..."

# Force enable doze
dumpsys deviceidle enable all 2>/dev/null

# Nuclear Doze constants - instant idle, maximum sleep durations
# light_after_inactive_to=0         -> Enter light doze immediately
# light_pre_idle_to=5000            -> 5 sec before light idle
# light_idle_to=3600000             -> 1 hour light idle
# light_max_idle_to=43200000        -> 12 hour max light idle
# inactive_to=0                     -> No delay before idle
# sensing_to=0                      -> No sensing delay
# idle_after_inactive_to=0          -> Immediate idle after inactive
# idle_to=21600000                  -> 6 hour idle
# max_idle_to=172800000             -> 48 hour max idle
# quick_doze_delay_to=5000          -> 5 sec quick doze
# deep_idle_to=7200000              -> 2 hour deep idle
# deep_max_idle_to=86400000         -> 24 hour max deep idle

settings put global device_idle_constants "light_after_inactive_to=0,light_pre_idle_to=5000,light_idle_to=3600000,light_max_idle_to=43200000,locating_to=5000,location_accuracy=1000,inactive_to=0,sensing_to=0,motion_inactive_to=0,idle_after_inactive_to=0,idle_to=21600000,max_idle_to=172800000,quick_doze_delay_to=5000,min_time_to_alarm=300000,deep_idle_to=7200000,deep_max_idle_to=86400000,deep_idle_maintenance_max_interval=86400000,deep_idle_maintenance_min_interval=43200000,deep_still_threshold=0,deep_idle_prefetch=1,deep_idle_prefetch_delay=300000,deep_idle_delay_factor=2,deep_idle_factor=3" 2>/dev/null

log "  ✓ Doze constants set"

# ============================================================================
# POWER SAVE MODE SETTINGS
# ============================================================================

log "⚙️ Enabling power save features..."

# Enable battery saver features
settings put global low_power 1 2>/dev/null
settings put global low_power_sticky 1 2>/dev/null
settings put global automatic_power_save_mode 1 2>/dev/null

# App standby
settings put global app_standby_enabled 1 2>/dev/null
settings put global forced_app_standby_enabled 1 2>/dev/null
settings put global app_auto_restriction_enabled true 2>/dev/null

# Adaptive features
settings put global adaptive_battery_management_enabled 1 2>/dev/null
settings put secure adaptive_sleep 0 2>/dev/null

log "  ✓ Power save enabled"

# ============================================================================
# NETWORK & CONNECTIVITY SAVINGS
# ============================================================================

log "⚙️ Configuring network savings..."

# Disable background scanning
settings put global wifi_scan_always_enabled 0 2>/dev/null
settings put global wifi_wakeup_enabled 0 2>/dev/null
settings put global ble_scan_always_enabled 0 2>/dev/null
settings put global wifi_networks_available_notification_on 0 2>/dev/null

# Disable network scoring
settings put global network_scoring_ui_enabled 0 2>/dev/null
settings put global network_recommendations_enabled 0 2>/dev/null
settings put global network_avoid_bad_wifi 0 2>/dev/null

# Captive portal - disable (saves battery on WiFi)
settings put global captive_portal_mode 0 2>/dev/null
settings put global captive_portal_detection_enabled 0 2>/dev/null

# Mobile data savings
settings put global mobile_data_always_on 0 2>/dev/null

log "  ✓ Network savings configured"

# ============================================================================
# DISPLAY & ANIMATION SAVINGS
# ============================================================================

log "⚙️ Configuring display savings..."

# Reduce animation overhead
settings put global window_animation_scale 0.5 2>/dev/null
settings put global transition_animation_scale 0.5 2>/dev/null
settings put global animator_duration_scale 0.5 2>/dev/null

# Display optimizations
settings put global stay_on_while_plugged_in 0 2>/dev/null
settings put system screen_off_timeout 30000 2>/dev/null

# Disable always-on display features that drain battery
settings put secure doze_always_on 0 2>/dev/null
settings put secure doze_pick_up_gesture 0 2>/dev/null
settings put secure doze_pulse_on_pick_up 0 2>/dev/null
settings put secure doze_tap_gesture 0 2>/dev/null
settings put secure doze_double_tap_gesture 0 2>/dev/null

log "  ✓ Display savings configured"

# ============================================================================
# LOCATION SAVINGS
# ============================================================================

log "⚙️ Configuring location savings..."

# Battery saving location mode (2 = battery saving, 3 = high accuracy)
settings put secure location_mode 2 2>/dev/null

# Disable background location for accuracy
settings put global location_background_throttle_interval_ms 600000 2>/dev/null
settings put global location_background_throttle_proximity_alert_interval_ms 600000 2>/dev/null

# Disable location history
settings put secure location_history_enabled 0 2>/dev/null

log "  ✓ Location savings configured"

# ============================================================================
# GMS RESTRICTIONS
# ============================================================================

log "⚙️ Restricting Google Play Services..."

# Reduce GMS check-in frequency (1440 min = 24 hours)
settings put global gms_checkin_timeout_min 1440 2>/dev/null

# Disable Google location features
settings put global assisted_gps_enabled 0 2>/dev/null
settings put global wifi_watchdog_on 0 2>/dev/null

# Force GMS into doze immediately
dumpsys deviceidle force-idle 2>/dev/null

log "  ✓ GMS restricted"

# ============================================================================
# SYNC & BACKGROUND DATA
# ============================================================================

log "⚙️ Configuring sync restrictions..."

# Disable auto sync at boot (user can enable if needed)
settings put global sync_enabled 0 2>/dev/null

# Background data restriction
cmd netpolicy set restrict-background true 2>/dev/null

log "  ✓ Sync restrictions set"

# ============================================================================
# SENSOR OPTIMIZATIONS
# ============================================================================

log "⚙️ Configuring sensor optimizations..."

# Enable sensor suspend when screen off
settings put global sensors_suspend_enabled 1 2>/dev/null

# Disable edge gestures that wake device
settings put secure edge_touch_enabled 0 2>/dev/null

log "  ✓ Sensor optimizations set"

# ============================================================================
# OEM SPECIFIC OPTIMIZATIONS
# ============================================================================

log "⚙️ Applying OEM-specific optimizations..."

# Samsung
settings put global sem_enhanced_cpu_responsiveness 0 2>/dev/null
settings put global protect_battery 1 2>/dev/null

# Xiaomi/MIUI
setprop persist.sys.miui_optimization true 2>/dev/null

# OnePlus
settings put global oneplus_optimizer_enabled 1 2>/dev/null

# OPPO/Realme
settings put global coloros_battery_saver_enabled 1 2>/dev/null

log "  ✓ OEM optimizations applied"

# ============================================================================
# START SERVICE DAEMON
# ============================================================================

if [ -f "$MODDIR/service.sh" ]; then
    log "⚙️ Starting service daemon..."
    nohup sh "$MODDIR/service.sh" >/dev/null 2>&1 &
    log "  ✓ Service daemon started (PID: $!)"
fi

# ============================================================================
# COMPLETE
# ============================================================================

log "═══════════════════════════════════════════"
log "✅ DeepDoze Enforcer v3.0 initialization complete"
log "═══════════════════════════════════════════"
log "📊 Settings applied:"
log "   - Doze: NUCLEAR"
log "   - Power Save: ENABLED"
log "   - Network Scanning: DISABLED"
log "   - Location Mode: BATTERY SAVING"
log "   - Sync: DISABLED"
log "   - Animations: REDUCED"
log "═══════════════════════════════════════════"
