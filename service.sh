#!/system/bin/sh

LOG_DIR="${DEEPDOZE_LOG_DIR:-/data/adb/deepdoze}"
LOG_FILE="$LOG_DIR/service.log"
PIDFILE="$LOG_DIR/service.pid"
LOCKDIR="$LOG_DIR/service.lock"
CONFIG_FILE="$LOG_DIR/config"
WHITELIST_FILE="$LOG_DIR/whitelist"
RESTRICTED_FILE="$LOG_DIR/restricted_pkgs"
RESTORE_FLAG="$LOG_DIR/needs_restore"
APP_STATE_FILE="$LOG_DIR/app_state"
PROTECTED_FILE="$LOG_DIR/protected_last"
REASONS_FILE="$LOG_DIR/protected_reasons"
KEEP_FILE="$LOG_DIR/appops_keep"
SEED_MARKER="$LOG_DIR/seeded"
DOZE_FLAG="$LOG_DIR/doze_forced"
FEED_PIDFILE="$LOG_DIR/feed.pid"
CPU_BASE="${DEEPDOZE_CPU_BASE:-/sys/devices/system/cpu}"
CPU_STATE_DIR="$LOG_DIR/cpu_state"
DRAW_FILE="$LOG_DIR/draw_off"
EVENT_PIPE="$LOG_DIR/screen.fifo"
BATT_DIR="${DEEPDOZE_BATT_DIR:-/sys/class/power_supply/battery}"
BOOT_WAIT_TIMEOUT="${DEEPDOZE_BOOT_WAIT_TIMEOUT:-180}"
MAX_LOOPS="${DEEPDOZE_MAX_LOOPS:-0}"

mode=gentle
enable_cpu_throttle=false
enable_force_doze=true
screen_off_governor=powersave
screen_off_max_freq_khz=0
screen_poll=10
screen_off_poll=60

ESSENTIALS="com.google.android.deskclock com.android.deskclock com.sec.android.app.clockpackage com.oneplus.deskclock com.coloros.alarmclock com.miui.clock com.android.alarmclock com.oppo.alarmclock com.transsion.deskclock com.topjohnwu.magisk me.weishu.kernelsu me.bmax.apatch"

cpu_lowered=0
apps_restricted=0
doze_forced=0
event_fd=0
feed_pid=""
feed_ok=0
feed_fails=0
kg_src=activity
screen_is_awake=1

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
    mode=gentle
    enable_cpu_throttle=false
    enable_force_doze=true
    screen_off_governor=powersave
    screen_off_max_freq_khz=0
    screen_poll=10
    screen_off_poll=60
    if [ -f "$CONFIG_FILE" ]; then
        while IFS='=' read -r key value; do
            case "$key" in
                mode) mode=$value ;;
                enable_cpu_throttle) enable_cpu_throttle=$value ;;
                enable_force_doze) enable_force_doze=$value ;;
                screen_off_governor) screen_off_governor=$value ;;
                screen_off_max_freq_khz) screen_off_max_freq_khz=$value ;;
                screen_poll) screen_poll=$value ;;
                screen_off_poll) screen_off_poll=$value ;;
            esac
        done <"$CONFIG_FILE"
    fi
    screen_poll=$(pos_num "$screen_poll" 10)
    screen_off_poll=$(pos_num "$screen_off_poll" 60)
    case "$mode" in gentle|balanced|aggressive|off) ;; *) mode=gentle ;; esac
    case "$enable_cpu_throttle" in true|false) ;; *) enable_cpu_throttle=false ;; esac
    case "$enable_force_doze" in true|false) ;; *) enable_force_doze=true ;; esac
    case "$screen_off_governor" in
        *[!a-zA-Z0-9_-]*|"") screen_off_governor=powersave ;;
    esac
    case "$screen_off_max_freq_khz" in
        ''|*[!0-9]*) screen_off_max_freq_khz=0 ;;
    esac
}

load_config

service_pid_valid() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ -r "/proc/$1/cmdline" ] || return 1
    tr '\000' ' ' <"/proc/$1/cmdline" 2>/dev/null | grep -Fq "$0"
}

if ! mkdir "$LOCKDIR" 2>/dev/null; then
    oldpid=$(cat "$PIDFILE" 2>/dev/null)
    service_pid_valid "$oldpid" && kill -0 "$oldpid" 2>/dev/null && exit 0
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

        if [ -r "$gov_f" ] && [ ! -f "$CPU_STATE_DIR/$name.gov" ]; then
            cur_gov=$(cat "$gov_f" 2>/dev/null)
            [ -n "$cur_gov" ] && echo "$cur_gov" >"$CPU_STATE_DIR/$name.gov"
        fi
        if [ -r "$max_f" ] && [ ! -f "$CPU_STATE_DIR/$name.max" ]; then
            cur_max=$(cat "$max_f" 2>/dev/null)
            [ -n "$cur_max" ] && echo "$cur_max" >"$CPU_STATE_DIR/$name.max"
        fi

        if [ -w "$gov_f" ]; then
            avail=$(cat "$d/scaling_available_governors" 2>/dev/null)
            for g in "$screen_off_governor" powersave conservative; do
                case " $avail " in
                    *" $g "*)
                        if echo "$g" >"$gov_f" 2>/dev/null; then
                            current=$(cat "$gov_f" 2>/dev/null)
                            [ -z "$current" ] && current=$g
                            echo "$current" >"$CPU_STATE_DIR/$name.applied_gov"
                            applied=1
                        fi
                        break
                        ;;
                esac
            done
        fi
        if [ -w "$max_f" ]; then
            cap="$screen_off_max_freq_khz"
            if [ -z "$cap" ] || [ "$cap" = 0 ]; then
                cap=$(cat "$d/scaling_min_freq" 2>/dev/null)
                [ -z "$cap" ] && cap=$(cat "$d/cpuinfo_min_freq" 2>/dev/null)
            fi
            min=$(cat "$d/cpuinfo_min_freq" 2>/dev/null)
            [ -z "$min" ] && min=$(cat "$d/scaling_min_freq" 2>/dev/null)
            max=$(cat "$d/cpuinfo_max_freq" 2>/dev/null)
            case "$min:$cap" in
                *[!0-9:]*|:*) ;;
                *) [ "$cap" -lt "$min" ] && cap=$min ;;
            esac
            case "$max:$cap" in
                *[!0-9:]*|:*) ;;
                *) [ "$cap" -gt "$max" ] && cap=$max ;;
            esac
            if [ -n "$cap" ] && echo "$cap" >"$max_f" 2>/dev/null; then
                current=$(cat "$max_f" 2>/dev/null)
                [ -z "$current" ] && current=$cap
                echo "$current" >"$CPU_STATE_DIR/$name.applied_max"
                applied=1
            fi
        fi
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
            applied=$(cat "$CPU_STATE_DIR/$name.applied_max" 2>/dev/null)
            current=$(cat "$max_f" 2>/dev/null)
            if [ -n "$saved" ] && { [ -z "$applied" ] || [ "$current" = "$applied" ]; }; then
                echo "$saved" >"$max_f" 2>/dev/null
            fi
        fi
        if [ -w "$gov_f" ]; then
            saved=$(cat "$CPU_STATE_DIR/$name.gov" 2>/dev/null)
            applied=$(cat "$CPU_STATE_DIR/$name.applied_gov" 2>/dev/null)
            current=$(cat "$gov_f" 2>/dev/null)
            if [ -n "$saved" ] && { [ -z "$applied" ] || [ "$current" = "$applied" ]; }; then
                echo "$saved" >"$gov_f" 2>/dev/null
            fi
        fi
    done
    rm -f "$CPU_STATE_DIR"/*.max "$CPU_STATE_DIR"/*.gov \
        "$CPU_STATE_DIR"/*.applied_max "$CPU_STATE_DIR"/*.applied_gov 2>/dev/null
    cpu_lowered=0
    log "unlocked: cpu restored"
}

foreground_pkg() {
    dumpsys activity activities 2>/dev/null \
        | grep -m1 -E 'mResumedActivity|topResumedActivity' \
        | sed -nE 's#.*[[:space:]]([a-zA-Z][a-zA-Z0-9_.]*)/[^[:space:]]*.*#\1#p'
}

valid_pkg() {
    case "$1" in
        [a-zA-Z]*)
            case "$1" in *[!a-zA-Z0-9_.]*) return 1 ;; esac
            ;;
        *) return 1 ;;
    esac
}

get_bucket() {
    output=$(am get-standby-bucket "$1" 2>/dev/null) || { echo "-"; return; }
    value=$(printf '%s\n' "$output" | tail -n 1 | awk '{ print $NF }')
    case "$value" in
        active) echo 10 ;;
        working_set) echo 20 ;;
        frequent) echo 30 ;;
        rare) echo 40 ;;
        restricted) echo 45 ;;
        never) echo 50 ;;
        [0-9]|[0-9][0-9]|[0-9][0-9][0-9]) echo "$value" ;;
        *) echo "-" ;;
    esac
}

get_appop() {
    output=$(cmd appops get "$1" RUN_ANY_IN_BACKGROUND 2>/dev/null) || { echo "-"; return; }
    value=$(printf '%s\n' "$output" \
        | sed -n 's/^[[:space:]]*RUN_ANY_IN_BACKGROUND:[[:space:]]*\([a-z_]*\).*/\1/p' \
        | head -n 1)
    case "$value" in
        allow|ignore|deny|default|foreground) echo "$value" ;;
        "") echo default ;;
        *) echo "-" ;;
    esac
}

build_protected() {
    {
        [ -f "$WHITELIST_FILE" ] && grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$WHITELIST_FILE"
        dumpsys deviceidle whitelist 2>/dev/null \
            | sed -n 's/^[^,]*,\([a-zA-Z][a-zA-Z0-9_.]*\)$/\1/p'
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
        touch "$SEED_MARKER"
    else
        log "default-app detection unavailable; will retry next start"
    fi
}

restrict_apps() {
    [ "$mode" = off ] && return
    [ "$apps_restricted" = 1 ] && return
    has pm || return
    build_protected >"$PROTECTED_FILE" 2>/dev/null
    pm list packages -3 2>/dev/null | sed 's/^package://' \
        | grep -vxF -f "$PROTECTED_FILE" >"$RESTRICTED_FILE.tmp" 2>/dev/null
    mv "$RESTRICTED_FILE.tmp" "$RESTRICTED_FILE" 2>/dev/null || return
    if [ ! -s "$RESTRICTED_FILE" ]; then
        apps_restricted=1
        return
    fi
    fg=$(foreground_pkg)
    bucket=40
    if [ "$mode" != gentle ]; then
        sdk=$(getprop ro.build.version.sdk 2>/dev/null)
        case "$sdk" in
            ''|*[!0-9]*) sdk=26 ;;
        esac
        [ "$sdk" -ge 31 ] && bucket=45
    fi
    : >"$APP_STATE_FILE.tmp" || return
    while read -r pkg; do
        valid_pkg "$pkg" || continue
        old_bucket=$(get_bucket "$pkg")
        old_op="-"
        new_op="-"
        if [ "$mode" != gentle ]; then
            old_op=$(get_appop "$pkg")
            [ "$old_op" != "-" ] && new_op=ignore
        fi
        printf '%s\t%s\t%s\t%s\t%s\n' "$pkg" "$old_bucket" "$old_op" "$bucket" "$new_op" \
            >>"$APP_STATE_FILE.tmp"
    done <"$RESTRICTED_FILE"
    mv "$APP_STATE_FILE.tmp" "$APP_STATE_FILE" || return
    touch "$RESTORE_FLAG" 2>/dev/null || return
    tab=$(printf '\t')
    while IFS="$tab" read -r pkg old_bucket old_op new_bucket new_op; do
        valid_pkg "$pkg" || continue
        [ "$old_bucket" != "-" ] && am set-standby-bucket "$pkg" "$new_bucket" >/dev/null 2>&1
        [ "$new_op" != "-" ] && cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND "$new_op" >/dev/null 2>&1
        [ "$mode" = aggressive ] && [ "$pkg" != "$fg" ] && am force-stop "$pkg" >/dev/null 2>&1
    done <"$APP_STATE_FILE"
    apps_restricted=1
    n=$(grep -c . "$RESTRICTED_FILE" 2>/dev/null || echo 0)
    log "locked: restricted $n apps (mode=$mode)"
}

restore_apps() {
    if [ ! -f "$RESTORE_FLAG" ]; then
        apps_restricted=0
        return
    fi
    if [ -s "$APP_STATE_FILE" ]; then
        tab=$(printf '\t')
        while IFS="$tab" read -r pkg old_bucket old_op new_bucket new_op; do
            valid_pkg "$pkg" || continue
            if [ "$old_bucket" != "-" ]; then
                current=$(get_bucket "$pkg")
                [ "$current" = "$new_bucket" ] \
                    && am set-standby-bucket "$pkg" "$old_bucket" >/dev/null 2>&1
            fi
            if [ "$old_op" != "-" ] && [ "$new_op" != "-" ]; then
                current=$(get_appop "$pkg")
                [ "$current" = "$new_op" ] \
                    && cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND "$old_op" >/dev/null 2>&1
            fi
        done <"$APP_STATE_FILE"
    else
        # One-time recovery for state written by versions before 3.5.2.
        while read -r pkg; do
            valid_pkg "$pkg" || continue
            am set-standby-bucket "$pkg" active >/dev/null 2>&1
            grep -qxF "$pkg" "$KEEP_FILE" 2>/dev/null \
                || cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND default >/dev/null 2>&1
        done <"$RESTRICTED_FILE"
    fi
    rm -f "$RESTORE_FLAG" "$APP_STATE_FILE" "$KEEP_FILE" 2>/dev/null
    apps_restricted=0
    log "unlocked: restored apps"
}

is_call_active() {
    states=$(dumpsys telephony.registry 2>/dev/null \
        | sed -n 's/.*mCallState=\([0-9][0-9]*\).*/\1/p')
    [ -n "$states" ] && printf '%s\n' "$states" | grep -qv '^0$'
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
    [ -f "$DOZE_FLAG" ] && { doze_forced=1; return; }
    has dumpsys || return
    if dumpsys deviceidle force-idle deep >/dev/null 2>&1; then
        doze_forced=1
        touch "$DOZE_FLAG" 2>/dev/null
    fi
}

unforce_doze() {
    [ "$doze_forced" = 1 ] || [ -f "$DOZE_FLAG" ] || return
    if has dumpsys && dumpsys deviceidle unforce >/dev/null 2>&1; then
        rm -f "$DOZE_FLAG" 2>/dev/null
        doze_forced=0
    fi
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
    power_state=$(dumpsys power 2>/dev/null) || return 0
    state=$(printf '%s\n' "$power_state" | grep -m1 'mWakefulness=' \
        | sed 's/.*mWakefulness=//;s/[^A-Za-z].*//')
    case "$state" in
        Awake|Dreaming) return 0 ;;
        Asleep|Dozing) return 1 ;;
    esac
    if printf '%s\n' "$power_state" | grep -qE 'mInteractive=true|mScreenOn=true'; then
        return 0
    fi
    if printf '%s\n' "$power_state" | grep -qE 'mInteractive=false|mScreenOn=false'; then
        return 1
    fi
    return 0
}

device_active() {
    screen_is_awake=0
    if screen_awake; then
        screen_is_awake=1
        ! is_locked
        return
    fi
    return 1
}

is_charging() {
    st=$(cat "$BATT_DIR/status" 2>/dev/null)
    case "$st" in
        Discharging|Not\ charging) return 1 ;;
        *) return 0 ;;
    esac
}

init_event_pipe() {
    event_fd=0
    has mkfifo || return
    has logcat || return
    rm -f "$EVENT_PIPE" 2>/dev/null
    mkfifo "$EVENT_PIPE" 2>/dev/null || return
    exec 3<>"$EVENT_PIPE" 2>/dev/null || { rm -f "$EVENT_PIPE"; return; }
    event_fd=1
}

feed_is_ours() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ -r "/proc/$1/cmdline" ] || return 1
    tr '\000' ' ' <"/proc/$1/cmdline" 2>/dev/null \
        | grep -q 'logcat .*screen_toggled'
}

cleanup_stale_feed() {
    stale=$(cat "$FEED_PIDFILE" 2>/dev/null)
    feed_is_ours "$stale" && kill "$stale" 2>/dev/null
    rm -f "$FEED_PIDFILE" 2>/dev/null
}

start_feed() {
    [ "$event_fd" = 1 ] || return
    [ -n "$feed_pid" ] && kill -0 "$feed_pid" 2>/dev/null && return
    logcat -b events -T 1 -s screen_toggled >&3 2>/dev/null &
    feed_pid=$!
    echo "$feed_pid" >"$FEED_PIDFILE" 2>/dev/null
}

stop_feed() {
    feed_is_ours "$feed_pid" && kill "$feed_pid" 2>/dev/null
    feed_pid=""
    rm -f "$FEED_PIDFILE" 2>/dev/null
}

wait_screen_on() {
    if screen_awake; then
        sleep "$screen_poll"
        return 0
    fi
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

cleanup() {
    trap - INT TERM EXIT
    stop_feed
    cpu_restore
    restore_apps
    unforce_doze
    rm -f "$PIDFILE" "$EVENT_PIPE" 2>/dev/null
    rmdir "$LOCKDIR" 2>/dev/null
}

trap 'cleanup; exit 0' INT TERM
trap 'cleanup' EXIT

elapsed=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != 1 ] && [ "$elapsed" -lt "$BOOT_WAIT_TIMEOUT" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
done

if ls "$CPU_STATE_DIR"/*.max "$CPU_STATE_DIR"/*.gov >/dev/null 2>&1; then
    cpu_lowered=1
    cpu_restore
fi
if [ -f "$RESTORE_FLAG" ]; then
    restore_apps
fi
if [ -f "$DOZE_FLAG" ]; then
    doze_forced=1
    unforce_doze
fi

find_batt
detect_kg
cleanup_stale_feed
init_event_pipe
seed_whitelist

log "service started (mode=$mode kg=$kg_src events=$event_fd)"

prev=on
off_sum=0
off_count=0
off_max=0
off_min=0
off_skip=0
loop_count=0
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
        loop_count=$((loop_count + 1))
        [ "$MAX_LOOPS" -gt 0 ] && [ "$loop_count" -ge "$MAX_LOOPS" ] && exit 0
        continue
    fi
    if [ "$prev" != off ]; then
        prev=off
        load_config
        off_sum=0
        off_count=0
        off_max=0
        off_min=0
        off_skip=1
        rm -f "$DRAW_FILE" 2>/dev/null
        start_feed
    fi
    if [ "$screen_is_awake" = 1 ]; then
        cpu_restore
        unforce_doze
    fi
    if is_call_active || is_charging; then
        cpu_restore
        restore_apps
        unforce_doze
    else
        if [ "$screen_is_awake" = 0 ]; then
            force_doze
            cpu_lower
        fi
        restrict_apps
        if [ "$screen_is_awake" = 1 ]; then
            :
        elif [ "$off_skip" = 1 ]; then
            off_skip=0
        else
            sample_draw
        fi
    fi
    wait_screen_on
    loop_count=$((loop_count + 1))
    [ "$MAX_LOOPS" -gt 0 ] && [ "$loop_count" -ge "$MAX_LOOPS" ] && exit 0
done
