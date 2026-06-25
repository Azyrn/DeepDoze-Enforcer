#!/system/bin/sh

LOG_DIR="/data/adb/deepdoze"
LOG_FILE="$LOG_DIR/service.log"
PIDFILE="$LOG_DIR/service.pid"
CONFIG_FILE="$LOG_DIR/config"
WHITELIST_FILE="$LOG_DIR/whitelist"
RESTRICTED_FILE="$LOG_DIR/restricted_pkgs"
PROTECTED_FILE="$LOG_DIR/protected_last"
REASONS_FILE="$LOG_DIR/protected_reasons"
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

[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE" 2>/dev/null

if [ -f "$PIDFILE" ]; then
    oldpid=$(cat "$PIDFILE" 2>/dev/null)
    if [ -n "$oldpid" ] && kill -0 "$oldpid" 2>/dev/null; then
        exit 0
    fi
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
    [ "$applied" = 1 ] && { cpu_lowered=1; log "screen off: cpu throttled"; }
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
    log "screen on: cpu restored"
}

foreground_pkg() {
    dumpsys activity activities 2>/dev/null \
        | grep -m1 -E 'topResumedActivity|mResumedActivity|ResumedActivity' \
        | grep -oE '[a-zA-Z0-9_]+\.[a-zA-Z0-9._]+/' | head -1 | tr -d /
}

fgs_pkgs() {
    dumpsys activity services 2>/dev/null | awk '
        /ServiceRecord\{/ {
            pkg=""
            if (match($0, / u[0-9]+ [a-zA-Z0-9_.]+\//)) {
                s=substr($0, RSTART, RLENGTH)
                sub(/ u[0-9]+ /, "", s)
                sub(/\/.*/, "", s)
                pkg=s
            }
        }
        /isForeground=true/ { if (pkg != "") { print pkg; pkg="" } }
    '
}

media_pkgs() {
    dumpsys media_session 2>/dev/null | awk '
        /package=/ { p=$0; sub(/.*package=/, "", p); sub(/[^a-zA-Z0-9_.].*/, "", p); pkg=p }
        /state=3/  { if (pkg != "") { print pkg; pkg="" } }
    '
}

emit_reasons() {
    fp=$(foreground_pkg)
    [ -n "$fp" ] && printf '%s\tIn use on screen\n' "$fp"
    media_pkgs | while read -r p; do
        [ -n "$p" ] && printf '%s\tPlaying media\n' "$p"
    done
    fgs_pkgs | while read -r p; do
        [ -n "$p" ] && printf '%s\tActive background task\n' "$p"
    done
    sms=$(settings get secure sms_default_application 2>/dev/null)
    [ -n "$sms" ] && [ "$sms" != null ] && printf '%s\tDefault SMS app\n' "$sms"
    dialer=$(cmd telecom get-default-dialer 2>/dev/null)
    [ -n "$dialer" ] && printf '%s\tDefault phone app\n' "$dialer"
    ime=$(settings get secure default_input_method 2>/dev/null | sed 's#/.*##')
    [ -n "$ime" ] && [ "$ime" != null ] && printf '%s\tKeyboard\n' "$ime"
    home=$(cmd package resolve-activity --brief -c android.intent.category.HOME 2>/dev/null | grep / | tail -1 | sed 's#/.*##')
    [ -n "$home" ] && printf '%s\tHome launcher\n' "$home"
    if [ -f "$WHITELIST_FILE" ]; then
        grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$WHITELIST_FILE" | while read -r p; do
            printf '%s\tYour whitelist\n' "$p"
        done
    fi
    for p in $ESSENTIALS; do printf '%s\tAlarms & system\n' "$p"; done
}

build_protected() {
    emit_reasons 2>/dev/null \
        | awk -F'\t' '{ gsub(/[[:space:]]/,"",$1) } $1 ~ /^[a-zA-Z][a-zA-Z0-9_.]+$/ && $2 != "" { if (!seen[$1]++) print $1"\t"$2 }' \
        >"$REASONS_FILE.tmp" 2>/dev/null
    mv "$REASONS_FILE.tmp" "$REASONS_FILE" 2>/dev/null
    cut -f1 "$REASONS_FILE" 2>/dev/null | sort -u
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
    apps_restricted=1
    n=$(wc -l <"$RESTRICTED_FILE" 2>/dev/null || echo 0)
    log "screen off: restricted $n apps (mode=$mode)"
}

restore_apps() {
    if [ ! -s "$RESTRICTED_FILE" ]; then
        apps_restricted=0
        return
    fi
    while read -r pkg; do
        [ -z "$pkg" ] && continue
        am set-standby-bucket "$pkg" active >/dev/null 2>&1
        cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND allow >/dev/null 2>&1
    done <"$RESTRICTED_FILE"
    rm -f "$RESTRICTED_FILE" 2>/dev/null
    apps_restricted=0
    log "screen on: restored apps"
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
    [ "$raw" -gt 10000 ] && raw=$((raw / 1000))
    echo "$raw"
}

force_doze() {
    [ "$enable_force_doze" != true ] && return
    has dumpsys && dumpsys deviceidle force-idle deep >/dev/null 2>&1
}

unforce_doze() {
    has dumpsys && dumpsys deviceidle unforce >/dev/null 2>&1
}

screen_is_off() {
    state=$(dumpsys power 2>/dev/null | grep -m1 mWakefulness= | sed 's/.*mWakefulness=//;s/[^A-Za-z].*//')
    case "$state" in
        Asleep|Dozing) return 0 ;;
        *) return 1 ;;
    esac
}

trap 'cpu_restore; restore_apps; unforce_doze; rm -f "$PIDFILE"; exit 0' INT TERM EXIT

elapsed=0
while [ "$(getprop sys.boot_completed 2>/dev/null)" != 1 ] && [ "$elapsed" -lt "$BOOT_WAIT_TIMEOUT" ]; do
    sleep 1
    elapsed=$((elapsed + 1))
done

if ls "$CPU_STATE_DIR"/*.max >/dev/null 2>&1; then
    cpu_lowered=1
    cpu_restore
fi
[ -s "$RESTRICTED_FILE" ] && restore_apps

log "service started (mode=$mode)"

prev=on
off_sum=0
off_count=0
off_max=0
off_min=0
while true; do
    ma=$(read_ma)
    if screen_is_off; then
        if [ "$prev" != off ]; then
            [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE" 2>/dev/null
            off_sum=0
            off_count=0
            off_max=0
            off_min=0
            rm -f "$DRAW_FILE" 2>/dev/null
        fi
        if is_call_active; then
            cpu_restore
            restore_apps
        else
            [ "$prev" != off ] && force_doze
            cpu_lower
            restrict_apps
            if [ -n "$ma" ]; then
                off_sum=$((off_sum + ma))
                off_count=$((off_count + 1))
                [ "$ma" -gt "$off_max" ] && off_max=$ma
                { [ "$off_min" -eq 0 ] || [ "$ma" -lt "$off_min" ]; } && off_min=$ma
                echo "$((off_sum / off_count)) $off_max $off_min" >"$DRAW_FILE" 2>/dev/null
            fi
        fi
        prev=off
    else
        if [ "$prev" = off ]; then
            cpu_restore
            restore_apps
            unforce_doze
        fi
        prev=on
    fi
    sleep "$screen_poll"
done
