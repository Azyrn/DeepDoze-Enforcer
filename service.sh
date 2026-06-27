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
SEED_MARKER="$LOG_DIR/seeded"
CPU_BASE="/sys/devices/system/cpu"
CPU_STATE_DIR="$LOG_DIR/cpu_state"
DRAW_FILE="$LOG_DIR/draw_off"
BATT_CURRENT="/sys/class/power_supply/battery/current_now"
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

mkdir -p "$LOG_DIR" 2>/dev/null

log() {
    if [ -f "$LOG_FILE" ]; then
        size=$(wc -c <"$LOG_FILE" 2>/dev/null || echo 0)
        [ "$size" -gt 102400 ] && mv "$LOG_FILE" "$LOG_FILE.1" 2>/dev/null
    fi
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >>"$LOG_FILE"
}

has() { command -v "$1" >/dev/null 2>&1; }

load_config() {
    [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE" 2>/dev/null
    case "$screen_poll" in
        ""|*[!0-9]*) screen_poll=2 ;;
        *) [ "$screen_poll" -lt 1 ] && screen_poll=2 ;;
    esac
    case "$screen_off_poll" in
        ""|*[!0-9]*) screen_off_poll=20 ;;
        *) [ "$screen_off_poll" -lt 1 ] && screen_off_poll=20 ;;
    esac
}

load_config

if ! mkdir "$LOCKDIR" 2>/dev/null; then
    oldpid=$(cat "$PIDFILE" 2>/dev/null)
    [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null && exit 0
    rmdir "$LOCKDIR" 2>/dev/null
    mkdir "$LOCKDIR" 2>/dev/null || exit 0
fi
echo $$ >"$PIDFILE"

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

cpu_lower() {
    [ "$enable_cpu_throttle" != true ] && return
    [ "$cpu_lowered" = 1 ] && return
    mkdir -p "$CPU_STATE_DIR" 2>/dev/null
    applied=0
    for d in $(cpu_freq_dirs); do
        name=$(basename "$d")
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
        name=$(basename "$d")
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
        | grep -m1 -E 'topResumedActivity|mResumedActivity|ResumedActivity' \
        | grep -oE '[a-zA-Z0-9_]+\.[a-zA-Z0-9._]+/' | head -1 | tr -d /
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
    : >"$RESTRICTED_FILE"
    fg=$(foreground_pkg)
    pm list packages -3 2>/dev/null | sed 's/^package://' | while read -r pkg; do
        [ -z "$pkg" ] && continue
        grep -qxF "$pkg" "$PROTECTED_FILE" 2>/dev/null && continue
        case "$mode" in
            gentle)
                am set-standby-bucket "$pkg" rare >/dev/null 2>&1
                ;;
            balanced)
                am set-standby-bucket "$pkg" restricted >/dev/null 2>&1
                cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND ignore >/dev/null 2>&1
                ;;
            aggressive)
                am set-standby-bucket "$pkg" restricted >/dev/null 2>&1
                cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND ignore >/dev/null 2>&1
                [ "$pkg" != "$fg" ] && am force-stop "$pkg" >/dev/null 2>&1
                ;;
        esac
        echo "$pkg" >>"$RESTRICTED_FILE"
    done
    touch "$RESTORE_FLAG" 2>/dev/null
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
        cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1
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
    raw=$(cat "$BATT_CURRENT" 2>/dev/null)
    raw=${raw#-}
    [ -z "$raw" ] && return 1
    case "$raw" in *[!0-9]*) return 1 ;; esac
    div=$((raw / 1000))
    if [ "$div" -ge 1 ] && [ "$div" -le 3000 ]; then
        echo "$div"
    elif [ "$raw" -ge 1 ] && [ "$raw" -le 3000 ]; then
        echo "$raw"
    else
        echo "$div"
    fi
}

force_doze() {
    [ "$enable_force_doze" != true ] && return
    has dumpsys && dumpsys deviceidle force-idle deep >/dev/null 2>&1
}

unforce_doze() {
    has dumpsys && dumpsys deviceidle unforce >/dev/null 2>&1
}

is_locked() {
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
    st=$(cat /sys/class/power_supply/battery/status 2>/dev/null)
    case "$st" in
        Charging|Full) return 0 ;;
        *) return 1 ;;
    esac
}

trap 'cpu_restore; restore_apps; unforce_doze; rm -f "$PIDFILE"; rmdir "$LOCKDIR" 2>/dev/null; exit 0' INT TERM EXIT

elapsed=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != 1 ] && [ "$elapsed" -lt "$BOOT_WAIT_TIMEOUT" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
done

if ls "$CPU_STATE_DIR"/*.max >/dev/null 2>&1; then
    cpu_lowered=1
    cpu_restore
fi
[ -f "$RESTORE_FLAG" ] && restore_apps

seed_whitelist

log "service started (mode=$mode)"

prev=on
off_sum=0
off_count=0
off_max=0
off_min=0
off_cycles=0
while true; do
    if ! device_active; then
        if [ "$prev" != off ]; then
            load_config
            off_sum=0
            off_count=0
            off_max=0
            off_min=0
            off_cycles=0
            rm -f "$DRAW_FILE" 2>/dev/null
        fi
        if is_call_active || is_charging; then
            cpu_restore
            restore_apps
            unforce_doze
        else
            if [ "$prev" != off ]; then
                force_doze
            else
                off_cycles=$((off_cycles + 1))
                if [ "$off_cycles" -ge "$doze_refire_cycles" ]; then
                    force_doze
                    off_cycles=0
                fi
            fi
            cpu_lower
            restrict_apps
            ma=$(read_ma)
            if [ -n "$ma" ]; then
                off_sum=$((off_sum + ma))
                off_count=$((off_count + 1))
                [ "$ma" -gt "$off_max" ] && off_max=$ma
                { [ "$off_min" -eq 0 ] || [ "$ma" -lt "$off_min" ]; } && off_min=$ma
                echo "$((off_sum / off_count)) $off_max $off_min" >"$DRAW_FILE" 2>/dev/null
            fi
        fi
        prev=off
        slept=0
        while [ "$slept" -lt "$screen_off_poll" ]; do
            sleep "$screen_poll"
            slept=$((slept + screen_poll))
            device_active && break
        done
    else
        if [ "$prev" = off ]; then
            cpu_restore
            restore_apps
            unforce_doze
        fi
        prev=on
        sleep "$screen_poll"
    fi
done
