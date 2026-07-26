#!/system/bin/sh

MODDIR=${0%/*}
LOG_DIR="${DEEPDOZE_LOG_DIR:-/data/adb/deepdoze}"
PIDFILE="$LOG_DIR/service.pid"
RESTRICTED_FILE="$LOG_DIR/restricted_pkgs"
APP_STATE_FILE="$LOG_DIR/app_state"
KEEP_FILE="$LOG_DIR/appops_keep"
RESTORE_FLAG="$LOG_DIR/needs_restore"
DOZE_FLAG="$LOG_DIR/doze_forced"
FEED_PIDFILE="$LOG_DIR/feed.pid"
CPU_BASE="${DEEPDOZE_CPU_BASE:-/sys/devices/system/cpu}"
CPU_STATE_DIR="$LOG_DIR/cpu_state"

pid_matches() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ -r "/proc/$1/cmdline" ] || return 1
    tr '\000' ' ' <"/proc/$1/cmdline" 2>/dev/null | grep -q "$2"
}

service_pid_matches() {
    case "$1" in ''|*[!0-9]*) return 1 ;; esac
    [ -r "/proc/$1/cmdline" ] || return 1
    tr '\000' ' ' <"/proc/$1/cmdline" 2>/dev/null | grep -Fq "$MODDIR/service.sh"
}

valid_pkg() {
    case "$1" in
        [a-zA-Z]*) case "$1" in *[!a-zA-Z0-9_.]*) return 1 ;; esac ;;
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
    case "$value" in allow|ignore|deny|default|foreground) echo "$value" ;; "") echo default ;; *) echo "-" ;; esac
}

pid=$(cat "$PIDFILE" 2>/dev/null)
if service_pid_matches "$pid" && kill -0 "$pid" 2>/dev/null; then
    kill "$pid" 2>/dev/null
    i=0
    while [ "$i" -lt 5 ] && kill -0 "$pid" 2>/dev/null; do
        sleep 1
        i=$((i + 1))
    done
    kill -0 "$pid" 2>/dev/null && kill -9 "$pid" 2>/dev/null
fi
feed_pid=$(cat "$FEED_PIDFILE" 2>/dev/null)
pid_matches "$feed_pid" "logcat .*screen_toggled" && kill "$feed_pid" 2>/dev/null

[ -f "$DOZE_FLAG" ] && dumpsys deviceidle unforce >/dev/null 2>&1

if [ -f "$RESTORE_FLAG" ] && [ -s "$APP_STATE_FILE" ]; then
    tab=$(printf '\t')
    while IFS="$tab" read -r pkg old_bucket old_op new_bucket new_op; do
        valid_pkg "$pkg" || continue
        if [ "$old_bucket" != "-" ] && [ "$(get_bucket "$pkg")" = "$new_bucket" ]; then
            am set-standby-bucket "$pkg" "$old_bucket" >/dev/null 2>&1
        fi
        if [ "$old_op" != "-" ] && [ "$new_op" != "-" ] \
            && [ "$(get_appop "$pkg")" = "$new_op" ]; then
            cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND "$old_op" >/dev/null 2>&1
        fi
    done <"$APP_STATE_FILE"
elif [ -f "$RESTORE_FLAG" ] && [ -f "$RESTRICTED_FILE" ]; then
    # One-time recovery for state written by versions before 3.5.2.
    while read -r pkg; do
        valid_pkg "$pkg" || continue
        am set-standby-bucket "$pkg" active >/dev/null 2>&1
        grep -qxF "$pkg" "$KEEP_FILE" 2>/dev/null \
            || cmd appops set "$pkg" RUN_ANY_IN_BACKGROUND default >/dev/null 2>&1
    done <"$RESTRICTED_FILE"
fi

if [ -d "$CPU_STATE_DIR" ]; then
    for d in "$CPU_BASE"/cpufreq/policy* "$CPU_BASE"/cpu[0-9]*/cpufreq; do
        [ -d "$d" ] || continue
        case "$d" in
            */cpufreq) name=$(basename "${d%/cpufreq}") ;;
            *) name=$(basename "$d") ;;
        esac
        if [ -f "$CPU_STATE_DIR/$name.max" ]; then
            saved=$(cat "$CPU_STATE_DIR/$name.max" 2>/dev/null)
            applied=$(cat "$CPU_STATE_DIR/$name.applied_max" 2>/dev/null)
            current=$(cat "$d/scaling_max_freq" 2>/dev/null)
            [ -n "$saved" ] && { [ -z "$applied" ] || [ "$current" = "$applied" ]; } \
                && echo "$saved" >"$d/scaling_max_freq" 2>/dev/null
        fi
        if [ -f "$CPU_STATE_DIR/$name.gov" ]; then
            saved=$(cat "$CPU_STATE_DIR/$name.gov" 2>/dev/null)
            applied=$(cat "$CPU_STATE_DIR/$name.applied_gov" 2>/dev/null)
            current=$(cat "$d/scaling_governor" 2>/dev/null)
            [ -n "$saved" ] && { [ -z "$applied" ] || [ "$current" = "$applied" ]; } \
                && echo "$saved" >"$d/scaling_governor" 2>/dev/null
        fi
    done
fi

rm -rf "$LOG_DIR" 2>/dev/null
