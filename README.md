# DeepDoze Enforcer

Universal battery-saving module for **Magisk**, **KernelSU** and **APatch**. It enforces aggressive Doze, kills background wakelocks, throttles Google Play Services, and restricts background apps — all while respecting your personal preferences for location, sync, animations and battery saver.

## Compatibility

- Android 8.0 (API 26) and newer
- Magisk 24.0+, KernelSU 1.0+, APatch
- Works on most phones — no kernel modifications, framework level only

## What it does

**Deep sleep enforcement**
- Forces the device into deep Doze shortly after the screen turns off
- Re-enforces during long screen-off periods via periodic maintenance

**Background restrictions**
- Denies `RUN_IN_BACKGROUND`, `WAKE_LOCK` and `BOOT_COMPLETED` for non-whitelisted apps
- Moves background apps into the restricted standby bucket
- Cancels scheduled jobs and exact alarms for non-whitelisted apps

**Google Play Services optimization**
- Removes GMS / GSF from the Doze whitelist
- Ignores background app-ops and hibernates GMS when the screen is off
- Reduces check-in frequency and trims memory

**Network, location and sensors**
- Disables Wi-Fi / BLE background scanning and network scoring
- Restricts background data for non-whitelisted apps
- Switches location to battery-saving mode (only if you have location enabled)
- Freezes sensors for background apps

## Respects your choices

The module deliberately does **not** override:
- Your battery-saver preference (uses adaptive power save, not forced low-power)
- Your location toggle (skips entirely if you turned location off)
- Your sync preference (preserved if you enabled it; restored when the screen turns on)
- Animation scales, screen-off timeout and always-on display

## Configuration

A config file is generated on first boot at:

```
/data/adb/deepdoze/config
```

Edit it to change the whitelist, aggression level (`mild` / `moderate` / `nuclear`) or toggle any individual feature, then reboot.

## Command line

```
deepdoze status     Show service, screen, battery and Doze state
deepdoze force      Force deep sleep and clean memory now
deepdoze enable     Force deep sleep
deepdoze disable    Restore normal operation
deepdoze log [n]    Show the last n log lines
```

## WebUI

Open the module in the **KernelSU** or **APatch** manager (or MMRL) to view the live status dashboard and control panel.

## Installation

Flash the zip in your root manager and reboot. Battery savings begin after the first reboot.

## Contact

Telegram: https://t.me/necotinx
