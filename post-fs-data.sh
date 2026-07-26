#!/system/bin/sh

MODDIR=${0%/*}
LOG_DIR="/data/adb/deepdoze"
LOG_FILE="$LOG_DIR/boot.log"

mkdir -p "$LOG_DIR" 2>/dev/null

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >>"$LOG_FILE" 2>/dev/null
}

log "post-fs-data: no global properties changed"
