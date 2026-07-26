#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "${0%/*}/.." && pwd)
TMP_ROOT=$(mktemp -d)
trap 'rm -rf "$TMP_ROOT"' EXIT INT TERM

pass=0

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

assert_eq() {
    actual=$1
    expected=$2
    label=$3
    [ "$actual" = "$expected" ] || fail "$label (expected '$expected', got '$actual')"
}

assert_count() {
    pattern=$1
    expected=$2
    file=$3
    label=$4
    actual=$(grep -c "$pattern" "$file" 2>/dev/null || true)
    assert_eq "$actual" "$expected" "$label"
}

new_fixture() {
    fixture=$TMP_ROOT/case_$pass
    mock_bin=$fixture/bin
    mock_state=$fixture/state
    log_dir=$fixture/deepdoze
    batt_dir=$fixture/battery
    cpu_base=$fixture/cpu
    cpu_policy=$cpu_base/cpufreq/policy0
    mkdir -p "$mock_bin" "$mock_state" "$log_dir" "$batt_dir" "$cpu_policy"

    for command in getprop dumpsys pm am cmd settings sleep; do
        ln -s "$ROOT/tests/android-command" "$mock_bin/$command"
    done

    : >"$mock_state/operations"
    echo Asleep >"$mock_state/wakefulness"
    echo true >"$mock_state/keyguard"
    echo 0 >"$mock_state/call_state"
    echo 34 >"$mock_state/sdk"
    echo ACTIVE >"$mock_state/doze"
    echo 20 >"$mock_state/bucket_com.example.app"
    echo allow >"$mock_state/appop_com.example.app"
    echo Discharging >"$batt_dir/status"
    echo 75 >"$batt_dir/capacity"
    echo -42000 >"$batt_dir/current_now"

    echo schedutil >"$cpu_policy/scaling_governor"
    echo "schedutil powersave conservative performance" >"$cpu_policy/scaling_available_governors"
    echo 300000 >"$cpu_policy/scaling_min_freq"
    echo 300000 >"$cpu_policy/cpuinfo_min_freq"
    echo 2000000 >"$cpu_policy/cpuinfo_max_freq"
    echo 2000000 >"$cpu_policy/scaling_max_freq"

    export PATH="$mock_bin:/usr/bin:/bin"
    export MOCK_STATE="$mock_state"
    export MOCK_CPU_POLICY="$cpu_policy"
    export DEEPDOZE_LOG_DIR="$log_dir"
    export DEEPDOZE_BATT_DIR="$batt_dir"
    export DEEPDOZE_CPU_BASE="$cpu_base"
    export DEEPDOZE_BOOT_WAIT_TIMEOUT=1
    export DEEPDOZE_MAX_LOOPS=1
    unset MOCK_MUTATE_CPU
    unset MOCK_MUTATE_APP
}

run_service() {
    sh "$ROOT/service.sh"
}

test_exact_app_restore() {
    new_fixture
    {
        echo mode=balanced
        echo enable_cpu_throttle=false
        echo enable_force_doze=true
        echo screen_poll=1
        echo screen_off_poll=1
    } >"$log_dir/config"

    run_service

    assert_eq "$(cat "$mock_state/bucket_com.example.app")" 20 "standby bucket restored exactly"
    assert_eq "$(cat "$mock_state/appop_com.example.app")" allow "app-op restored exactly"
    assert_count '^bucket com.example.app 45$' 1 "$mock_state/operations" "restricted bucket applied once"
    assert_count '^bucket com.example.app 20$' 1 "$mock_state/operations" "previous bucket restored once"
    assert_count '^appop com.example.app ignore$' 1 "$mock_state/operations" "background app-op restricted once"
    assert_count '^appop com.example.app allow$' 1 "$mock_state/operations" "previous app-op restored once"
    assert_count '^doze force deep$' 1 "$mock_state/operations" "Doze forced once"
    assert_count '^doze unforce$' 1 "$mock_state/operations" "owned Doze force released once"
    [ ! -e "$log_dir/needs_restore" ] || fail "restore marker was not cleared"
    pass=$((pass + 1))
    echo "ok $pass - exact app and Doze state restoration"
}

test_conservative_defaults() {
    new_fixture

    run_service

    assert_count '^bucket com.example.app 40$' 1 "$mock_state/operations" "Gentle bucket is the default"
    assert_count '^appop com.example.app ignore$' 0 "$mock_state/operations" "default mode did not deny background activity"
    assert_eq "$(cat "$cpu_policy/scaling_governor")" schedutil "CPU throttle is off by default"
    pass=$((pass + 1))
    echo "ok $pass - conservative defaults"
}

test_os_exemption_respected() {
    new_fixture
    echo user,com.example.app >"$mock_state/deviceidle_whitelist"

    run_service

    assert_count '^bucket com.example.app ' 0 "$mock_state/operations" "OS-exempt app was not restricted"
    assert_count '^appop com.example.app ' 0 "$mock_state/operations" "OS-exempt app-op was not changed"
    pass=$((pass + 1))
    echo "ok $pass - Android battery exemption respected"
}

test_cpu_restore() {
    new_fixture
    {
        echo mode=off
        echo enable_cpu_throttle=true
        echo enable_force_doze=false
        echo screen_poll=1
        echo screen_off_poll=1
    } >"$log_dir/config"

    run_service

    assert_eq "$(cat "$cpu_policy/scaling_governor")" schedutil "CPU governor restored"
    assert_eq "$(cat "$cpu_policy/scaling_max_freq")" 2000000 "CPU maximum restored"
    pass=$((pass + 1))
    echo "ok $pass - CPU policy restoration"
}

test_external_app_change_wins() {
    new_fixture
    {
        echo mode=balanced
        echo enable_cpu_throttle=false
        echo enable_force_doze=false
        echo screen_poll=1
        echo screen_off_poll=1
    } >"$log_dir/config"
    export MOCK_MUTATE_APP=1

    run_service

    assert_eq "$(cat "$mock_state/bucket_com.example.app")" 30 "newer external standby bucket preserved"
    assert_eq "$(cat "$mock_state/appop_com.example.app")" deny "newer external app-op preserved"
    assert_count '^bucket com.example.app 20$' 0 "$mock_state/operations" "old bucket did not overwrite external value"
    assert_count '^appop com.example.app allow$' 0 "$mock_state/operations" "old app-op did not overwrite external value"
    pass=$((pass + 1))
    echo "ok $pass - external app manager changes preserved"
}

test_external_cpu_change_wins() {
    new_fixture
    {
        echo mode=off
        echo enable_cpu_throttle=true
        echo enable_force_doze=false
        echo screen_poll=1
        echo screen_off_poll=1
    } >"$log_dir/config"
    export MOCK_MUTATE_CPU=1

    run_service

    assert_eq "$(cat "$cpu_policy/scaling_governor")" performance "newer external governor preserved"
    assert_eq "$(cat "$cpu_policy/scaling_max_freq")" 1500000 "newer external CPU cap preserved"
    pass=$((pass + 1))
    echo "ok $pass - external CPU manager changes preserved"
}

test_crash_marker_recovery() {
    new_fixture
    echo Awake >"$mock_state/wakefulness"
    echo false >"$mock_state/keyguard"
    touch "$log_dir/doze_forced"

    run_service

    assert_count '^doze unforce$' 1 "$mock_state/operations" "stale forced Doze recovered"
    assert_count '^doze force' 0 "$mock_state/operations" "active device was not forced into Doze"
    [ ! -e "$log_dir/doze_forced" ] || fail "stale Doze marker was not removed"
    pass=$((pass + 1))
    echo "ok $pass - crash recovery releases owned Doze"
}

test_action_awake_guard() {
    new_fixture
    echo Awake >"$mock_state/wakefulness"
    /bin/sh -c '/bin/sleep 30' "$ROOT/service.sh" &
    fake_service=$!
    echo "$fake_service" >"$log_dir/service.pid"

    output=$(sh "$ROOT/action.sh")
    kill "$fake_service" 2>/dev/null || true

    printf '%s\n' "$output" | grep -q 'Lock the phone' || fail "Action did not report the awake guard"
    assert_count '^doze force' 0 "$mock_state/operations" "Action forced Doze while screen was awake"
    pass=$((pass + 1))
    echo "ok $pass - Action refuses forced Doze while awake"
}

test_uninstall_exact_restore() {
    new_fixture
    echo 45 >"$mock_state/bucket_com.example.app"
    echo ignore >"$mock_state/appop_com.example.app"
    printf 'com.example.app\t20\tallow\t45\tignore\n' >"$log_dir/app_state"
    touch "$log_dir/needs_restore" "$log_dir/doze_forced"
    mkdir -p "$log_dir/cpu_state"
    echo schedutil >"$log_dir/cpu_state/policy0.gov"
    echo powersave >"$log_dir/cpu_state/policy0.applied_gov"
    echo 2000000 >"$log_dir/cpu_state/policy0.max"
    echo 300000 >"$log_dir/cpu_state/policy0.applied_max"
    echo powersave >"$cpu_policy/scaling_governor"
    echo 300000 >"$cpu_policy/scaling_max_freq"

    sh "$ROOT/uninstall.sh"

    assert_eq "$(cat "$mock_state/bucket_com.example.app")" 20 "uninstall restored exact bucket"
    assert_eq "$(cat "$mock_state/appop_com.example.app")" allow "uninstall restored exact app-op"
    assert_eq "$(cat "$cpu_policy/scaling_governor")" schedutil "uninstall restored CPU governor"
    assert_eq "$(cat "$cpu_policy/scaling_max_freq")" 2000000 "uninstall restored CPU maximum"
    assert_count '^doze unforce$' 1 "$mock_state/operations" "uninstall released owned Doze"
    [ ! -e "$log_dir" ] || fail "uninstall left runtime state behind"
    pass=$((pass + 1))
    echo "ok $pass - uninstall exact restoration"
}

test_exact_app_restore
test_conservative_defaults
test_os_exemption_respected
test_external_app_change_wins
test_cpu_restore
test_external_cpu_change_wins
test_crash_marker_recovery
test_action_awake_guard
test_uninstall_exact_restore

for script in "$ROOT"/*.sh "$ROOT"/META-INF/com/google/android/update-binary; do
    sh -n "$script"
done
node --check "$ROOT/webroot/app.js"
node "$ROOT/tests/webui-check.js"
echo "ok $((pass + 1)) - shell, JavaScript, and WebUI structure"
echo "All $((pass + 1)) tests passed."
