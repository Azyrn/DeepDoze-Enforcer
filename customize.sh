#!/system/bin/sh
# DeepDoze Enforcer v1.5 - Installation Script
MODPATH=$1
ui_print "Installing DeepDoze Enforcer v1.5"
ui_print "- Ultimate Battery Optimizer"
ui_print "- Setting permissions..."
set_perm_recursive $MODPATH/system 0 0 0755 0755
set_perm_recursive $MODPATH 0 0 0755 0755
ui_print "✅ Installation complete - Reboot to activate"
