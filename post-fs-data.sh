#!/system/bin/sh

MODDIR=${0%/*}
LOG_DIR="/data/adb/deepdoze"
LOG_FILE="$LOG_DIR/boot.log"

mkdir -p "$LOG_DIR" 2>/dev/null

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >>"$LOG_FILE" 2>/dev/null
}

log "post-fs-data: applying early property tweaks"

setprop persist.traced.enable 0 2>/dev/null
setprop sys.trace.traced_started 0 2>/dev/null
setprop debug.atrace.tags.enableflags 0 2>/dev/null
setprop persist.sys.trace.default 0 2>/dev/null

setprop persist.sys.miui_optimization true 2>/dev/null

log "post-fs-data: complete (framework settings deferred to service.sh)"
