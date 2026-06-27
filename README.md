# DeepDoze Enforcer

Universal battery-saving module for **Magisk**, **KernelSU** and **APatch**. It enforces aggressive Doze, throttles the CPU while your phone is locked, and restricts background apps — without changing your Wi-Fi, Bluetooth, network, location or sensor settings, and with no dedicated Google Play Services handling (Google apps are treated like any other app).

Savings are tied to the **lock state, not the screen**: turning on the screen just to check the time keeps them active; everything is restored the moment you unlock (any method — fingerprint, face, Smart Lock). If you run with **no lock screen** at all, it falls back to screen-off so savings still apply.

## Compatibility

- Android 8.0 (API 26) and newer
- Magisk 24.0+, KernelSU 1.0+, APatch
- Works on most phones — no kernel modifications, framework level only

## What it does

**Deep sleep enforcement**
- Forces the device into deep Doze shortly after you lock the phone
- Re-enforces during long locked periods via periodic maintenance

**Background restrictions**
- Moves non-whitelisted apps into the `rare` (gentle) or `restricted` (balanced / aggressive) standby bucket while the phone is locked
- Denies the `RUN_ANY_IN_BACKGROUND` app-op for non-whitelisted apps in balanced and aggressive modes
- In aggressive mode, also force-stops idle non-foreground apps
- The restricted bucket is what the OS uses to defer their jobs, alarms and network — the module sets the bucket, it does not cancel jobs or alarms directly
- Everything is reverted (buckets back to `active`, app-op re-allowed) the moment you unlock

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

## Configuration

A config file is generated on first boot at:

```
/data/adb/deepdoze/config
```

Edit it to change the mode (`gentle` / `balanced` / `aggressive`, or `off` to disable app restrictions) or to toggle features such as `enable_cpu_throttle` and `enable_force_doze`, then reboot. The whitelist is a separate file with one package per line at `/data/adb/deepdoze/whitelist`.

## WebUI

Open the module in the **KernelSU** or **APatch** manager (or MMRL) to view the live status dashboard and control panel.

## Installation

Flash the zip in your root manager and reboot. Battery savings begin after the first reboot.

## Contact

Telegram: https://t.me/necotinx
