# Changelog

## v3.4.1

### WebUI redesign — clearer and outcome-focused
- New **Sleep engine** status and descriptive sleep states instead of raw CPU/governor internals
- **Battery while asleep**: average drain, estimated overnight drain and best–worst range
- **Protected apps** split into Automatically protected, Your whitelist and Restricted counts
- **Recent activity** rewritten into human-readable events with reasons (collapsible)
- **Why an app is protected** view showing the exact reason per app (media, navigation, foreground service, default app, alarm, whitelist…)

### Manage protected apps
- New **app picker**: choose which installed apps to keep awake, with search and an optional "Show system apps" toggle
- Auto-protected apps now appear pre-selected with a green reason badge, and can be toggled
- Clearer black selection checkboxes
- The background service now records the exact protection reason for each app

### Reliability
- The **action button** now starts the background service if it isn't running, so the module works right after flashing without a reboot

### Removed
- Manual Force/Restore controls and the raw output console — the module works automatically when the screen is off

## v3.4
- Longer battery life: deep-sleeps the phone when the screen is off and stops apps draining power, while keeping alarms, calls and messages working
- Works with Magisk, KernelSU and APatch
- Module card banner with WebUI and Action icons
- ACTION button that forces deep sleep on tap
- Clean WebUI dashboard: service status, battery, Doze state and last-enforced time, with Force / Restore controls
- WebUI no longer breaks ("Webpage not available"): external links open via intent instead of navigating the page
- WebUI controls run as root via the verified KernelSU exec API
- Framework settings moved to the post-boot phase so they actually apply
- Bluetooth profiles only disabled when Bluetooth is off
