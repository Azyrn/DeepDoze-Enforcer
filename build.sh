#!/usr/bin/env bash
set -e

cd "$(dirname "$0")"

VER=$(grep -m1 '^version=' module.prop | cut -d= -f2)
ZIP="DeepDoze-Enforcer-${VER}.zip"

FILES="
module.prop
customize.sh
post-fs-data.sh
service.sh
action.sh
icon.png
banner.png
README.md
CHANGELOG.md
META-INF/com/google/android/update-binary
META-INF/com/google/android/updater-script
system/bin/deepdoze
webroot/index.html
webroot/banner.jpg
"

EXE="customize.sh post-fs-data.sh service.sh action.sh system/bin/deepdoze META-INF/com/google/android/update-binary"

chmod 0755 $EXE 2>/dev/null || true

rm -f "$ZIP"

if command -v zip >/dev/null 2>&1; then
    zip -r -X "$ZIP" $FILES >/dev/null
else
    python3 - "$ZIP" $FILES <<'PY'
import sys, os, zipfile
zipname = sys.argv[1]
files = sys.argv[2:]
exe = {"customize.sh","post-fs-data.sh","service.sh","action.sh",
       "system/bin/deepdoze","META-INF/com/google/android/update-binary"}
with zipfile.ZipFile(zipname, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        zi = zipfile.ZipInfo(f)
        zi.compress_type = zipfile.ZIP_DEFLATED
        zi.external_attr = ((0o755 if f in exe else 0o644) & 0o7777) << 16
        with open(f, "rb") as fh:
            z.writestr(zi, fh.read())
print("built", zipname)
PY
fi

echo "Created $ZIP ($(du -h "$ZIP" | cut -f1))"
