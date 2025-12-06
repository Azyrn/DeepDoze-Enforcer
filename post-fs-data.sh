#!/system/bin/sh
# Early initialization runs right after system boot

MODDIR=${0%/*}
LOG_FILE="/data/adb/deepdoze_boot.log"

echo "[$(date)] DeepDoze Enforcer initialization..." > $LOG_FILE

# Create data directory
mkdir -p /data/adb/deepdoze

# Disable tracing early (before apps load)
setprop persist.traced.enable 0
setprop debug.atrace.tags.enableflags 0

# Set aggressive Doze settings
settings put global device_idle_constants \
    "inactive_to=30000,light_after_inactive_to=30000,light_idle_to=600000"

# Enable Doze for all
dumpsys deviceidle enable all

echo "[$(date)] ✅ Initialization complete" >> $LOG_FILE
