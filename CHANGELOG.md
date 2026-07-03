# Changelog

## v3.5.1

### WebUI redesigned
- Rebuilt from scratch with a Material 3 look: master engine switch, live status chips and a headline **drain-while-asleep** readout with best/worst
- Guided **restriction mode** picker with plain-language explanations and trade-off warnings, including a new **Leave apps alone** option (deep doze and CPU limit only)
- **Force deep doze** and **Slow the CPU** are now switches in the UI instead of hidden config keys
- Protected apps: app names and avatars, quick search, Protected/Paused filters, sorting, system-app toggle, multi-select with bulk protect/unprotect, and instant autosave — no Save button
- **OS-exempt** badge shows apps Android already excludes from battery optimization; always-protected essentials are shown locked
- Settings save atomically and never clobber other config values

### Housekeeping
- Removed the `deepdoze` command-line tool — the WebUI is the interface
- Added `uninstall.sh`: removing the module now restores CPU clocks, app restrictions and doze state
- Faster unlock reaction via screen-event feed instead of pure polling

## v3.5.0

### Protected apps are now fully in your control
- Replaced automatic, behaviour-based protection with a single **explicit list**: apps you check stay awake while your phone is locked; everything else is restricted
- Restrictions are tied to the **lock state**, not the screen: turning on the screen just to check the time keeps savings active — they only lift when you actually unlock
- On first run the important defaults — your **phone, SMS, keyboard and home launcher** — are detected and pre-selected for you, so nothing critical breaks out of the box. Uncheck any you don't want
- Your **clock/alarm apps and root manager** are always protected and aren't shown in the list
- The app list now shows a simple **Protected (kept awake)** and **Restricted while asleep** count — no more confusing "automatically protected" category or per-app reason badges

### WebUI
- Outcome-focused dashboard: **Sleep engine** status, **Battery while asleep** (average / best–worst drain) and human-readable **Recent activity**
- App picker with search and an optional "Show system apps" toggle
- Restriction modes: **Gentle**, **Balanced**, **Aggressive**

### Reliability
- The **action button** starts the background service if it isn't running, so the module works right after flashing without a reboot
- Fixed home-launcher detection (was failing to resolve the default launcher on some devices)
- Restore-on-unlock works with every unlock method (fingerprint, face, Smart Lock / trusted devices); if you have **no lock screen at all**, it falls back to screen-off so savings still apply

### Removed
- Live activity detection and the automatic "in use / media / foreground" protection — protection is now whatever you choose, plus the always-on essentials
- Manual Force/Restore controls and the raw output console — the module works automatically while your phone is locked

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
