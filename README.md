# DeepDoze Enforcer

Battery-saving module for **Magisk**, **KernelSU** and **APatch**. It can enforce Doze and temporarily restrict background apps while your phone is locked, without changing Wi-Fi, Bluetooth, network, location or sensor settings. CPU throttling is available as an opt-in experimental control.

App restrictions are tied to the **lock state**, while forced Doze and optional CPU throttling only run with the display off. Waking the lock screen releases Doze and the CPU cap for responsiveness; the original app state is restored after unlock on the next detection cycle (normally within 10 seconds). With no lock screen, savings fall back to screen-off.

## Compatibility

- Android 8.0 (API 26) and newer
- Magisk 24.0+, KernelSU 1.0+, APatch
- No custom kernel is required; the optional CPU control depends on standard CPU-frequency interfaces exposed by the device

## What it does

**Deep sleep enforcement**
- Forces the device into deep Doze shortly after you lock the phone
- Records forced-Doze ownership so it can recover safely after a service crash

**Background restrictions**
- Moves non-whitelisted apps into the `rare` (gentle) or `restricted` (balanced / aggressive) standby bucket while the phone is locked
- Denies the `RUN_ANY_IN_BACKGROUND` app-op for non-whitelisted apps in balanced and aggressive modes
- In aggressive mode, also force-stops idle non-foreground apps
- The restricted bucket is what the OS uses to defer their jobs, alarms and network — the module sets the bucket, it does not cancel jobs or alarms directly
- The original bucket and app-op are recorded and restored at unlock
- If another tool changes a managed value after DeepDoze, DeepDoze leaves that newer value alone
- Apps already exempted from Android battery optimization are not restricted

**Google Play Services optimization**
- No dedicated GMS / GSF throttling is currently implemented
- Google packages are handled like other apps: protected when whitelisted, otherwise eligible for the same while-locked background restrictions

**Network, location and sensors**
- Does not change Wi-Fi, Bluetooth scanning, network scoring, location mode or sensor settings
- Savings while locked come from Doze enforcement, CPU throttling and app standby / background-run restrictions for eligible third-party apps

## Respects your choices

The module does **not** touch or override any of these system settings:
- Battery-saver / low-power mode
- Location mode and toggles
- Account sync preferences
- Animation scales, screen-off timeout and always-on display
- Android tracing properties

No battery module can guarantee a fixed saving on every device. Results depend on the phone, ROM, radio signal, installed apps and workload. Forced Doze and background restrictions can delay non-critical notifications or sync; use the default Gentle mode first and whitelist apps that must remain responsive. Avoid enabling CPU throttling alongside a kernel/performance manager.

## Configuration

A config file is generated on first boot at:

```
/data/adb/deepdoze/config
```

Edit it to change the mode (`gentle`, the default; `balanced`; `aggressive`; or `off` to disable app restrictions) or to toggle features such as `enable_cpu_throttle` (off by default) and `enable_force_doze`, then reboot. The whitelist is a separate file with one package per line at `/data/adb/deepdoze/whitelist`.

For meaningful validation, compare several overnight idle sessions with and without the module under the same signal, Always-On Display and app conditions. The WebUI current reading is useful for spotting large drains, but it is not a controlled battery benchmark.

## WebUI

Open the module in the **KernelSU** or **APatch** manager (or MMRL) to view the live status dashboard and control panel.

## Installation

Flash the zip in your root manager and reboot. Battery savings begin after the first reboot.

## Contact

Telegram: https://t.me/necotinx
