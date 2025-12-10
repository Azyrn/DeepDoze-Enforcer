#!/system/bin/sh
# DeepDoze Enforcer v1.5 - Post-FS-Data Init
MODDIR=${0%/*}
LOG_FILE="/data/adb/deepdoze/boot.log"

mkdir -p /data/adb/deepdoze 2>/dev/null
echo "[$(date '+%Y-%m-%d %H:%M:%S')] 🚀 DeepDoze Enforcer v1.5 starting..." > "$LOG_FILE" 2>/dev/null

# Disable system tracing at boot (aggressive)
setprop persist.traced.enable 0 2>/dev/null
setprop sys.trace.traced_started 0 2>/dev/null
setprop debug.atrace.tags.enableflags 0 2>/dev/null
setprop debug.hwui.skia_tracing_enabled 0 2>/dev/null
setprop debug.renderengine.skia_tracing_enabled 0 2>/dev/null
setprop debug.tracing.ctl.hwui.skia_tracing_enabled 0 2>/dev/null
setprop debug.tracing.ctl.renderengine.skia_tracing_enabled 0 2>/dev/null
setprop vendor.debug.c2.sbwc.enable false 2>/dev/null
setprop graphics.gpu.profiler.support false 2>/dev/null
setprop debug.tracing.battery_status 0 2>/dev/null
setprop debug.egl.hw 0 2>/dev/null
setprop debug.hwc.winupdate 0 2>/dev/null
setprop debug.perfmond.default.perfetto 0 2>/dev/null
setprop debug.sf.disable_backpressure 0 2>/dev/null
setprop debug.sf.hw 0 2>/dev/null
setprop debug.sf.latch_unsignaled 0 2>/dev/null
setprop debug.stagefright.c2-poolmask 0 2>/dev/null
setprop debug.stagefright.ccodec_delayed_params 0 2>/dev/null
setprop sys.boot.debug_history 0 2>/dev/null

# Stop tracing daemons
stop traced 2>/dev/null || true
stop traced_probes 2>/dev/null || true
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Tracing disabled" >> "$LOG_FILE"

# Configure aggressive Doze (minimal inactive timeout)
settings put global device_idle_constants "inactive_to=30000,light_after_inactive_to=30000,light_idle_to=600000" 2>/dev/null
settings put global gms_checkin_timeout_min 120 2>/dev/null

# Enable Doze
dumpsys deviceidle enable all 2>/dev/null
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Doze enabled" >> "$LOG_FILE"

# Start main service daemon
if [ -f "$MODDIR/service.sh" ]; then
    nohup sh "$MODDIR/service.sh" > /dev/null 2>&1 &
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✓ Service daemon started" >> "$LOG_FILE"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Init complete" >> "$LOG_FILE"
