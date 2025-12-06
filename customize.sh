#!/system/bin/sh
MODPATH=$1
ui_print "Installing DeepDoze Enforcer v1.1"
set_perm_recursive $MODPATH/system/bin 0 0 0755 0755
ui_print "Installation complete"
