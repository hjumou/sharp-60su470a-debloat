#!/bin/sh
# Restore every debloated package from backed-up APKs (generated during backup step).
# Requires: backup/apk_manifest.txt with lines "pkg|local_apk_path".
# Restore = adb push APK + pm install -r --user 0 (the ONLY install form that
# clears the "installed=false for user 0" state on this Android 6 ROM).
set -u
export ANDROID_SERIAL=192.168.1.194:5555
HERE="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$HERE/backup/apk_manifest.txt"
LOG="$HERE/restore_$(date +%Y%m%d_%H%M%S).log"
: > "$LOG"
if [ ! -f "$MANIFEST" ]; then
  echo "ERROR: $MANIFEST not found" | tee -a "$LOG"; exit 1
fi
echo "== Target $ANDROID_SERIAL ==" | tee -a "$LOG"
echo "== Restoring packages from local APK backups ==" | tee -a "$LOG"
while IFS='|' read -r pkg apk; do
  [ -z "$pkg" ] && continue
  case "$pkg" in \#*) continue;; esac
  if [ ! -f "$apk" ]; then
    echo "$pkg -> APK MISSING: $apk" | tee -a "$LOG"
    continue
  fi
  adb push "$apk" /data/local/tmp/restore.apk >/dev/null 2>&1
  out=$(adb shell "pm install -r --user 0 /data/local/tmp/restore.apk" </dev/null 2>&1)
  echo "$pkg -> $out" | tee -a "$LOG"
done < "$MANIFEST"
adb shell "rm -f /data/local/tmp/restore.apk" </dev/null 2>/dev/null
echo "== Done. Log: $LOG ==" | tee -a "$LOG"
