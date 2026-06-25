# Changelog

## What's new
- Longer battery life: deep-sleeps the phone when the screen is off and stops apps draining power, while keeping alarms, calls and messages working
- Works with Magisk, KernelSU and APatch
- Module card banner with WebUI and Action icons
- ACTION button that forces deep sleep on tap
- Clean WebUI dashboard: service status, battery, Doze state and last-enforced time, with Force / Restore controls

## What's fixed
- WebUI no longer breaks ("Webpage not available"): external links open via intent instead of navigating the page
- WebUI controls now work reliably (run as root via the verified KernelSU exec API)
- Framework settings moved to the post-boot phase so they actually apply
- Removed broken/non-existent shell commands and the over-broad Termux guard
- Removed the pointless "Screen" status row
- Bluetooth profiles only disabled when Bluetooth is off
