#!/system/bin/sh
# DeepDoze Enforcer v1.1 - Main Service
# Re-enforce Doze every 20 minutes when screen is off

LOG_FILE="/data/adb/deepdoze/service.log"
LAST_ENFORCE="/data/adb/deepdoze/last_enforce"
REFRESH_INTERVAL=1200  # 20 minutes in seconds

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> $LOG_FILE
}

# Initialize files
mkdir -p /data/adb/deepdoze
touch "$LOG_FILE"

# Wait for system to stabilize
sleep 60
log "Service started"

# Main monitoring loop
while true; do
    SCREEN_STATE=$(dumpsys power | grep -m1 'Display Power' | grep -o 'state=\w*' | cut -d= -f2 2>/dev/null)
    
    if [ "$SCREEN_STATE" = "OFF" ]; then
        log "Screen OFF detected - Applying optimizations"
        
        # Force deep sleep
        dumpsys deviceidle force-idle deep 2>/dev/null
        
        # Disable tracing
        setprop persist.traced.enable 0 2>/dev/null
        stop traced 2>/dev/null
        
        # Restrict background apps (except essential)
        WHITELIST="com.whatsapp com.telegram com.android.mms com.android.contacts"
        for pkg in $(pm list packages -3 | cut -d: -f2); do
            case " $WHITELIST " in
                *" $pkg "*) continue ;;
            esac
            appops set "$pkg" RUN_IN_BACKGROUND ignore 2>/dev/null
        done
        
        # Clean memory
        sync
        echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
        
        # Check if we need to re-enforce Doze (every 20 minutes)
        if [ -f "$LAST_ENFORCE" ]; then
            LAST_TIME=$(stat -c %Y "$LAST_ENFORCE")
            CURRENT_TIME=$(date +%s)
            TIME_DIFF=$((CURRENT_TIME - LAST_TIME))
            
            if [ $TIME_DIFF -ge $REFRESH_INTERVAL ]; then
                log "20 minutes passed - Re-enforcing Doze"
                dumpsys deviceidle force-idle deep 2>/dev/null
                touch "$LAST_ENFORCE"
            fi
        else
            touch "$LAST_ENFORCE"
        fi
        
        log "Optimizations applied - Sleeping 5 minutes"
        sleep 300
    else
        # Screen is ON - quick check interval
        sleep 30
    fi
done
