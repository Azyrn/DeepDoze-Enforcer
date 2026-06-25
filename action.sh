#!/system/bin/sh

LOG_DIR="/data/adb/deepdoze"
mkdir -p "$LOG_DIR" 2>/dev/null

echo "DeepDoze Enforcer"
echo "Forcing deep sleep now..."

dumpsys deviceidle enable 2>/dev/null
dumpsys deviceidle force-idle deep 2>/dev/null
sync 2>/dev/null
date +%s >"$LOG_DIR/last_enforce" 2>/dev/null

state=$(dumpsys deviceidle get deep 2>/dev/null)
echo "Done. Doze state: ${state:-unknown}"
