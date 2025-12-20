#!/system/bin/sh
# DeepDoze Enforcer - Post-FS-Data Init
MODDIR=${0%/*}
LOG_FILE="/data/adb/deepdoze/boot.log"

mkdir -p /data/adb/deepdoze 2>/dev/null
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🚀 DeepDoze Enforcer starting..." > "$LOG_FILE" 2>/dev/null

# Disable system tracing at boot (aggressive)
setprop persist.traced.enable 0 2>/dev/null
setprop sys.trace.traced_started 0 2>/dev/null
setprop debug.atrace.tags.enableflags 0 2>/dev/null
<<<<<<< HEAD
setprop debug.hwui.skia_tracing_enabled 0 2>/dev/null
setprop debug.renderengine.skia_tracing_enabled 0 2>/dev/null
setprop debug.tracing.ctl.hwui.skia_tracing_enabled 0 2>/dev/null
setprop debug.tracing.ctl.renderengine.skia_tracing_enabled 0 2>/dev/null
setprop graphics.gpu.profiler.support false 2>/dev/null
setprop debug.hwc.winupdate 0 2>/dev/null
setprop debug.perfmond.default.perfetto 0 2>/dev/null
setprop debug.sf.hw 0 2>/dev/null
setprop debug.sf.latch_unsignaled 0 2>/dev/null
setprop debug.stagefright.c2-poolmask 0 2>/dev/null
setprop debug.stagefright.ccodec_delayed_params 0 2>/dev/null
setprop sys.boot.debug_history 0 2>/dev/null
=======
# setprop debug.hwui.skia_tracing_enabled 0 2>/dev/null
# setprop debug.renderengine.skia_tracing_enabled 0 2>/dev/null
# setprop debug.tracing.ctl.hwui.skia_tracing_enabled 0 2>/dev/null
# setprop debug.tracing.ctl.renderengine.skia_tracing_enabled 0 2>/dev/null
# setprop graphics.gpu.profiler.support false 2>/dev/null
# setprop debug.hwc.winupdate 0 2>/dev/null
# setprop debug.perfmond.default.perfetto 0 2>/dev/null
# setprop debug.sf.hw 0 2>/dev/null
# setprop debug.sf.latch_unsignaled 0 2>/dev/null
# setprop debug.stagefright.c2-poolmask 0 2>/dev/null
# setprop debug.stagefright.ccodec_delayed_params 0 2>/dev/null
# setprop sys.boot.debug_history 0 2>/dev/null
>>>>>>> 550706d (fix black screen)

# Stop tracing daemons
stop traced 2>/dev/null || true
stop traced_probes 2>/dev/null || true
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Tracing disabled" >> "$LOG_FILE"

# Configure aggressive Doze with advanced optimization
dumpsys deviceidle force-idle 2>/dev/null
dumpsys deviceidle enable all 2>/dev/null
settings put global device_idle_constants "light_after_inactive_to=0,light_pre_idle_to=5000,light_idle_to=3600000,light_max_idle_to=43200000,locating_to=5000,location_accuracy=1000,inactive_to=0,sensing_to=0,motion_inactive_to=0,idle_after_inactive_to=0,idle_to=21600000,max_idle_to=172800000,quick_doze_delay_to=5000,min_time_to_alarm=300000,deep_idle_to=7200000,deep_max_idle_to=86400000,deep_idle_maintenance_max_interval=86400000,deep_idle_maintenance_min_interval=43200000,deep_still_threshold=0,deep_idle_prefetch=1,deep_idle_prefetch_delay=300000,deep_idle_delay_factor=2,deep_idle_factor=3" 2>/dev/null
settings put global gms_checkin_timeout_min 120 2>/dev/null
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Advanced Doze configured" >> "$LOG_FILE"

# Start main service daemon
if [ -f "$MODDIR/service.sh" ]; then
    nohup sh "$MODDIR/service.sh" > /dev/null 2>&1 &
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Service daemon started" >> "$LOG_FILE"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Init complete" >> "$LOG_FILE"
