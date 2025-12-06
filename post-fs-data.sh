#!/system/bin/sh
# Early initialization runs right after system boot (post-fs-data)
MODDIR=${0%/*}
LOG_FILE="/data/adb/deepdoze_boot.log"

mkdir -p /data/adb/deepdoze 2>/dev/null
echo "[$(date '+%Y-%m-%d %H:%M:%S')] DeepDoze Enforcer initialization..." > "$LOG_FILE" 2>/dev/null

# Disable tracing early if available
if command -v setprop >/dev/null 2>&1; then
    setprop persist.traced.enable 0 2>/dev/null || echo "setprop persist.traced.enable failed" >> "$LOG_FILE"
    setprop debug.atrace.tags.enableflags 0 2>/dev/null || true
fi

# Set aggressive Doze settings - best-effort; settings may require the settings binary
if command -v settings >/dev/null 2>&1; then
    # keep values quoted to avoid shell parsing issues
    settings put global device_idle_constants "inactive_to=30000,light_after_inactive_to=30000,light_idle_to=600000" 2>/dev/null || echo "settings put failed" >> "$LOG_FILE"
else
    echo "settings binary not found; skipping device_idle_constants" >> "$LOG_FILE"
fi

# Enable Doze if possible
if command -v dumpsys >/dev/null 2>&1; then
    dumpsys deviceidle enable all 2>/dev/null || echo "dumpsys deviceidle enable failed" >> "$LOG_FILE"
else
    echo "dumpsys not available; cannot enable deviceidle" >> "$LOG_FILE"
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] ✅ Initialization complete" >> "$LOG_FILE"
