#!/system/bin/sh

LOG_DIR="/data/adb/deepdoze"
LOG_FILE="$LOG_DIR/service.log"
PIDFILE="$LOG_DIR/service.pid"
LOCKDIR="$LOG_DIR/service.lock"
CONFIG_FILE="$LOG_DIR/config"
WHITELIST_FILE="$LOG_DIR/whitelist"
RESTRICTED_FILE="$LOG_DIR/restricted_pkgs"
RESTORE_FLAG="$LOG_DIR/needs_restore"
PROTECTED_FILE="$LOG_DIR/protected_last"
REASONS_FILE="$LOG_DIR/protected_reasons"
KEEP_FILE="$LOG_DIR/appops_keep"
SEED_MARKER="$LOG_DIR/seeded"
CPU_BASE="/sys/devices/system/cpu"
CPU_STATE_DIR="$LOG_DIR/cpu_state"
DRAW_FILE="$LOG_DIR/draw_off"
EVENT_PIPE="$LOG_DIR/screen.fifo"
BATT_DIR="/sys/class/power_supply/battery"
BOOT_WAIT_TIMEOUT=180

mode=balanced
enable_cpu_throttle=true
enable_force_doze=true
screen_off_governor=powersave
screen_off_max_freq_khz=0
screen_poll=2
screen_off_poll=20
doze_refire_cycles=6

ESSENTIALS="com.google.android.deskclock com.android.deskclock com.sec.android.app.clockpackage com.oneplus.deskclock com.coloros.alarmclock com.miui.clock com.android.alarmclock com.oppo.alarmclock com.transsion.deskclock com.topjohnwu.magisk me.weishu.kernelsu me.bmax.apatch"

cpu_lowered=0
apps_restricted=0
doze_forced=0
event_fd=0
feed_pid=""
feed_ok=0
feed_fails=0
kg_src=activity

mkdir -p "$LOG_DIR" 2>/dev/null

log() {
    if [ -f "$LOG_FILE" ]; then
        size=$(wc -c <"$LOG_FILE" 2>/dev/null || echo 0)
        [ "$size" -gt 102400 ] && mv "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >>"$LOG_FILE"
}

has() { command -v "$1" >/dev/null 2>&1; }

pos_num() {
    case "$1" in
        ''|*[!0-9]*|0) echo "$2" ;;
        *) echo "$1" ;;
    esac
}

load_config() {
    [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE" 2>/dev/null
    screen_poll=$(pos_num "$screen_poll" 2)
    screen_off_poll=$(pos_num "$screen_off_poll" 20)
    doze_refire_cycles=$(pos_num "$doze_refire_cycles" 6)
    case "$mode" in gentle|balanced|aggressive|off) ;; *) mode=balanced ;; esac
}

load_config

if ! mkdir "$LOCKDIR" 2>/dev/null; then
    oldpid=$(cat "$PIDFILE" 2>/dev/null)
    [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null && exit 0
    rmdir "$LOCKDIR" 2>/dev/null
    mkdir "$LOCKDIR" 2>/dev/null || exit 0
fi
echo $$ >"$PIDFILE"

find_batt() {
    for d in "$BATT_DIR" /sys/class/power_supply/Battery; do
        [ -f "$d/status" ] && { BATT_DIR=$d; return; }
    done
    for d in /sys/class/power_supply/*; do
        [ "$(cat "$d/type" 2>/dev/null)" = "Battery" ] && [ -f "$d/status" ] && { BATT_DIR=$d; return; }
    done
}

cpu_freq_dirs() {
    found=0
    for p in "$CPU_BASE"/cpufreq/policy*; do
        if [ -d "$p" ]; then echo "$p"; found=1; fi
    done
    [ "$found" = 1 ] && return
    for c in "$CPU_BASE"/cpu[0-9]*/cpufreq; do
        [ -d "$c" ] && echo "$c"
    done
}

cpu_name() {
    case "$1" in
        */cpufreq) basename "${1%/cpufreq}" ;;
        *) basename "$1" ;;
    esac
}

cpu_lower() {
    [ "$enable_cpu_throttle" != true ] && return
    [ "$cpu_lowered" = 1 ] && return
    mkdir -p "$CPU_STATE_DIR" 2>/dev/null
    applied=0
    for d in $(cpu_freq_dirs); do
        name=$(cpu_name "$d")
        gov_f="$d/scaling_governor"
        max_f="$d/scaling_max_freq"

        if [ -r "$gov_f" ]; then
            cur_gov=$(cat "$gov_f" 2>/dev/null)
            case "$cur_gov" in
                powersave|conservative|"") : ;;
                *) [ ! -f "$CPU_STATE_DIR/$name.gov" ] && echo "$cur_gov" >"$CPU_STATE_DIR/$name.gov" ;;
            esac
        fi
        if [ -r "$max_f" ] && [ ! -f "$CPU_STATE_DIR/$name.max" ]; then
            cur_max=$(cat "$max_f" 2>/dev/null)
            [ -n "$cur_max" ] && echo "$cur_max" >"$CPU_STATE_DIR/$name.max"
        fi

        if [ -w "$gov_f" ]; then
            avail=$(cat "$d/scaling_available_governors" 2>/dev/null)
            for g in "$screen_off_governor" powersave conservative; do
                case " $avail " in *" $g "*) echo "$g" >"$gov_f" 2>/dev/null; break ;; esac
            done
        fi
        if [ -w "$max_f" ]; then
            cap="$screen_off_max_freq_khz"
            if [ -z "$cap" ] || [ "$cap" = 0 ]; then
                cap=$(cat "$d/scaling_min_freq" 2>/dev/null)
                [ -z "$cap" ] && cap=$(cat "$d/cpuinfo_min_freq" 2>/dev/null)
            fi
            [ -n "$cap" ] && echo "$cap" >"$max_f" 2>/dev/null
        fi
        applied=1
    done
    [ "$applied" = 1 ] && { cpu_lowered=1; log "locked: cpu throttled"; }
}

cpu_restore() {
    [ "$cpu_lowered" != 1 ] && return
    for d in $(cpu_freq_dirs); do
        name=$(cpu_name "$d")
        max_f="$d/scaling_max_freq"
        gov_f="$d/scaling_governor"
        if [ -w "$max_f" ]; then
            saved=$(cat "$CPU_STATE_DIR/$name.max" 2>/dev/null)
            [ -z "$saved" ] && saved=$(cat "$d/cpuinfo_max_freq" 2>/dev/null)
            [ -n "$saved" ] && echo "$saved" >"$max_f" 2>/dev/null
        fi
        if [ -w "$gov_f" ]; then
            saved=$(cat "$CPU_STATE_DIR/$name.gov" 2>/dev/null)
            [ -n "$saved" ] && echo "$saved" >"$gov_f" 2>/dev/null
        fi
    done
    rm -f "$CPU_STATE_DIR"/*.max "$CPU_STATE_DIR"/*.gov 2>/dev/null
    cpu_lowered=0
    log "unlocked: cpu restored"
}

foreground_pkg() {
    dumpsys activity activities 2>/dev/null \
        | grep -m1 -E 'mResumedActivity|topResumedActivity' \
        | sed -nE 's#.*[[:space:]]([a-zA-Z][a-zA-Z0-9_.]*)/[^[:space:]]*.*#\1#p'
}

build_protected() {
    {
        [ -f "$WHITELIST_FILE" ] && grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$WHITELIST_FILE"
        for p in $ESSENTIALS; do echo "$p"; done
    } | awk '{ gsub(/[[:space:]]/,"") } $0 != "" { if (!seen[$0]++) print }'
}

detect_defaults() {
    dialer=$(cmd telecom get-default-dialer 2>/dev/null)
    [ -n "$dialer" ] && [ "$dialer" != null ] && echo "$dialer"
    sms=$(settings get secure sms_default_application 2>/dev/null)
    [ -n "$sms" ] && [ "$sms" != null ] && echo "$sms"
    ime=$(settings get secure default_input_method 2>/dev/null | sed 's#/.*##')
    [ -n "$ime" ] && [ "$ime" != null ] && echo "$ime"
    home=$(cmd package resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME 2>/dev/null | grep / | tail -1 | sed 's#/.*##')
    [ -n "$home" ] && echo "$home"
}

seed_whitelist() {
    [ -f "$SEED_MARKER" ] && return
    seeds=$(detect_defaults)
    if [ -f "$REASONS_FILE" ]; then
        old=$(awk -F'\t' '$2 != "Alarms & system" && $2 != "Your whitelist" && $1 ~ /^[a-zA-Z][a-zA-Z0-9_.]+$/ { print $1 }' "$REASONS_FILE" 2>/dev/null)
        seeds=$(printf '%s\n%s\n' "$seeds" "$old")
        rm -f "$REASONS_FILE" 2>/dev/null
    fi
    if [ -n "$(printf '%s' "$seeds" | tr -d '[:space:]')" ]; then
        touch "$WHITELIST_FILE"
        { cat "$WHITELIST_FILE"; printf '%s\n' "$seeds"; } \
            | awk '{ gsub(/[[:space:]]/,"") } $0 ~ /^[a-zA-Z][a-zA-Z0-9_.]+$/ { if (!seen[$0]++) print }' >"$WHITELIST_FILE.tmp" 2>/dev/null \
            && mv "$WHITELIST_FILE.tmp" "$WHITELIST_FILE"
        log "seeded whitelist with default apps"
    fi
    touch "$SEED_MARKER"
}

restrict_apps() {
    [ "$mode" = off ] && return
    [ "$apps_restricted" = 1 ] && return
    has pm || return
    build_protected >"$PROTECTED_FILE" 2>/dev/null
    pm list packages -3 2>/dev/null | sed 's/^package://' \
        | grep -vxF -f "$PROTECTED_FILE" >"$RESTRICTED_FILE.tmp" 2>/dev/null
    mv "$RESTRICTED_FILE.tmp" "$RESTRICTED_FILE" 2>/dev/null
    if [ ! -s "$RESTRICTED_FILE" ]; then
        apps_restricted=1
        return
    fi
    cmd appops query-op RUN_ANY_IN_BACKGROUND ignore 2>/dev/null >"$KEEP_FILE"
    touch "$RESTORE_FLAG" 2>/dev/null
    fg=$(foreground_pkg)
    bucket=restricted
    [ "$mode" = gentle ] && bucket=rare
    while read -r pkg; do
        [ -z "$pkg" ] && continue
        am set-standby-bucket "$pkg" "$bucket" >/dev/null 2>&1
        if [ "$mode" != gentle ]; then
            cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND ignore >/dev/null 2>&1
            [ "$mode" = aggressive ] && [ "$pkg" != "$fg" ] && am force-stop "$pkg" >/dev/null 2>&1
        fi
    done <"$RESTRICTED_FILE"
    apps_restricted=1
    n=$(grep -c . "$RESTRICTED_FILE" 2>/dev/null || echo 0)
    log "locked: restricted $n apps (mode=$mode)"
}

restore_apps() {
    if [ ! -f "$RESTORE_FLAG" ]; then
        apps_restricted=0
        return
    fi
    while read -r pkg; do
        [ -z "$pkg" ] && continue
        am set-standby-bucket "$pkg" active >/dev/null 2>&1
        grep -qxF "$pkg" "$KEEP_FILE" 2>/dev/null \
            || cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND default >/dev/null 2>&1
    done <"$RESTRICTED_FILE"
    rm -f "$RESTORE_FLAG" 2>/dev/null
    apps_restricted=0
    log "unlocked: restored apps"
}

is_call_active() {
    cs=$(dumpsys telephony.registry 2>/dev/null | grep -m1 mCallState= | grep -oE '[0-9]+' | head -1)
    [ -n "$cs" ] && [ "$cs" != 0 ]
}

read_ma() {
    raw=$(cat "$BATT_DIR/current_now" 2>/dev/null)
    raw=${raw#-}
    case "$raw" in ''|*[!0-9]*) return 1 ;; esac
    ma=$((raw / 1000))
    if [ "$ma" -ge 1 ] && [ "$ma" -le 3000 ]; then
        echo "$ma"
    elif [ "$raw" -ge 1 ] && [ "$raw" -le 3000 ]; then
        echo "$raw"
    else
        echo "$ma"
    fi
}

sample_draw() {
    ma=$(read_ma) || return
    [ -z "$ma" ] && return
    off_sum=$((off_sum + ma))
    off_count=$((off_count + 1))
    [ "$ma" -gt "$off_max" ] && off_max=$ma
    { [ "$off_min" -eq 0 ] || [ "$ma" -lt "$off_min" ]; } && off_min=$ma
    echo "$((off_sum / off_count)) $off_max $off_min" >"$DRAW_FILE" 2>/dev/null
}

force_doze() {
    [ "$enable_force_doze" != true ] && return
    has dumpsys || return
    dumpsys deviceidle force-idle deep >/dev/null 2>&1 && doze_forced=1
}

unforce_doze() {
    [ "$doze_forced" = 1 ] || return
    has dumpsys && dumpsys deviceidle unforce >/dev/null 2>&1
    doze_forced=0
}

detect_kg() {
    if dumpsys activity activities 2>/dev/null | grep -q 'mKeyguardShowing='; then
        kg_src=activity
    elif dumpsys window policy 2>/dev/null | grep -qE '(^|[[:space:]])showing='; then
        kg_src=policy
    else
        kg_src=activity
    fi
}

is_locked() {
    if [ "$kg_src" = policy ]; then
        kline=$(dumpsys window policy 2>/dev/null | grep -m1 -E '(^|[[:space:]])showing=')
        case "$kline" in
            *showing=true*) return 0 ;;
            *showing=false*) return 1 ;;
        esac
        kg_src=activity
    fi
    dumpsys activity activities 2>/dev/null | grep -q 'mKeyguardShowing=true'
}

screen_awake() {
    state=$(dumpsys power 2>/dev/null | grep -m1 'mWakefulness=' | sed 's/.*mWakefulness=//;s/[^A-Za-z].*//')
    [ "$state" = Awake ]
}

device_active() {
    screen_awake && ! is_locked
}

is_charging() {
    st=$(cat "$BATT_DIR/status" 2>/dev/null)
    case "$st" in
        Charging|Full) return 0 ;;
        *) return 1 ;;
    esac
}

init_event_pipe() {
    event_fd=0
    has mkfifo || return
    has logcat || return
    rm -f "$EVENT_PIPE" 2>/dev/null
    mkfifo "$EVENT_PIPE" 2>/dev/null || return
    ( exec 3<>"$EVENT_PIPE" ) 2>/dev/null || { rm -f "$EVENT_PIPE"; return; }
    exec 3<>"$EVENT_PIPE"
    event_fd=1
}

start_feed() {
    [ "$event_fd" = 1 ] || return
    [ -n "$feed_pid" ] && kill -0 "$feed_pid" 2>/dev/null && return
    logcat -b events -T 1 -s screen_toggled >&3 2>/dev/null &
    feed_pid=$!
}

stop_feed() {
    [ -n "$feed_pid" ] && kill "$feed_pid" 2>/dev/null
    feed_pid=""
}

wait_screen_on() {
    if [ -n "$feed_pid" ]; then
        remain=$screen_off_poll
        while [ "$remain" -gt 0 ]; do
            chunk=$screen_off_poll
            [ "$feed_ok" != 1 ] && chunk=$screen_poll
            [ "$chunk" -gt "$remain" ] && chunk=$remain
            line=""
            if read -r -t "$chunk" line <&3; then
                case "$line" in
                    *screen_toggled*)
                        if [ "$feed_ok" != 1 ]; then
                            feed_ok=1
                            log "screen event feed confirmed"
                        fi
                        val=${line##*:}
                        val=$(echo $val)
                        [ "$val" != 0 ] && return 0
                        ;;
                esac
                remain=$((remain - 1))
            else
                remain=$((remain - chunk))
                if [ "$feed_ok" != 1 ]; then
                    screen_awake && return 0
                fi
            fi
        done
        if ! kill -0 "$feed_pid" 2>/dev/null; then
            feed_fails=$((feed_fails + 1))
            stop_feed
            [ "$feed_fails" -le 3 ] && start_feed
        fi
        return 1
    fi
    slept=0
    while [ "$slept" -lt "$screen_off_poll" ]; do
        sleep "$screen_poll"
        slept=$((slept + screen_poll))
        screen_awake && return 0
    done
    return 1
}

trap 'stop_feed; cpu_restore; restore_apps; unforce_doze; rm -f "$PIDFILE" "$EVENT_PIPE"; rmdir "$LOCKDIR" 2>/dev/null; exit 0' INT TERM EXIT

elapsed=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != 1 ] && [ "$elapsed" -lt "$BOOT_WAIT_TIMEOUT" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
done

if ls "$CPU_STATE_DIR"/*.max >/dev/null 2>&1; then
    cpu_lowered=1
    cpu_restore
fi
if [ -f "$RESTORE_FLAG" ]; then
    has dumpsys && dumpsys deviceidle unforce >/dev/null 2>&1
    restore_apps
fi

find_batt
detect_kg
pkill -f "logcat -b events -T 1 -s screen_toggled" 2>/dev/null
init_event_pipe
seed_whitelist

log "service started (mode=$mode kg=$kg_src events=$event_fd)"

prev=on
off_sum=0
off_count=0
off_max=0
off_min=0
off_cycles=0
off_skip=0
while true; do
    if device_active; then
        if [ "$prev" = off ]; then
            stop_feed
            cpu_restore
            unforce_doze
            restore_apps
        fi
        prev=on
        sleep "$screen_poll"
        continue
    fi
    if [ "$prev" != off ]; then
        prev=off
        load_config
        off_sum=0
        off_count=0
        off_max=0
        off_min=0
        off_cycles=0
        off_skip=1
        rm -f "$DRAW_FILE" 2>/dev/null
        start_feed
    fi
    if is_call_active || is_charging; then
        cpu_restore
        restore_apps
        unforce_doze
        off_cycles=0
    else
        [ "$off_cycles" = 0 ] && force_doze
        off_cycles=$((off_cycles + 1))
        [ "$off_cycles" -ge "$doze_refire_cycles" ] && off_cycles=0
        cpu_lower
        restrict_apps
        if [ "$off_skip" = 1 ]; then
            off_skip=0
        else
            sample_draw
        fi
    fi
    wait_screen_on
done
