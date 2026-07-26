#!/system/bin/sh

SKIPUNZIP=0

ui_print " "
ui_print "  DeepDoze Enforcer"
ui_print "  Conservative Battery Saver"
ui_print " "

if [ "$KSU" = "true" ]; then
  ui_print "- Detected root manager: KernelSU"
elif [ "$APATCH" = "true" ]; then
  ui_print "- Detected root manager: APatch"
else
  ui_print "- Detected root manager: Magisk $MAGISK_VER"
fi

if [ "$API" -lt 26 ]; then
  ui_print "*********************************************"
  ui_print " Unsupported Android version (API $API)"
  ui_print " DeepDoze requires Android 8.0 (API 26) or newer"
  ui_print "*********************************************"
  abort "- Installation aborted"
fi

ui_print "- Android API level: $API"
ui_print "- Installing battery optimization service..."

set_perm_recursive "$MODPATH" 0 0 0755 0644
set_perm "$MODPATH/post-fs-data.sh" 0 0 0755
set_perm "$MODPATH/service.sh" 0 0 0755
set_perm "$MODPATH/action.sh" 0 0 0755
set_perm "$MODPATH/uninstall.sh" 0 0 0755

ui_print " "
ui_print "- Installation complete"
ui_print "- Reboot to activate battery savings"
ui_print "- Manage from the WebUI"
ui_print " "
