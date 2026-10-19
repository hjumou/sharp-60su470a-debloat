#!/bin/sh
# Re-pull APK backups from the TV if local backup/apk/ is lost.
# For each package in debloat_sharp_su470a.txt, resolve pm path and `adb pull`.
# NOTE: only works for packages STILL installed on the device (i.e. before
#       they were uninstalled, or after restore_debloat.sh). For already-
#       removed /data apps whose APK is gone, recovery is via factory reset.
set -u
export ANDROID_SERIAL=192.168.1.194:5555
HERE="$(cd "$(dirname "$0")" && pwd)"
LIST="$HERE/debloat_sharp_su470a.txt"
OUT="$HERE/backup/apk"
MANIFEST="$HERE/backup/apk_manifest.txt"
LOG="$HERE/rebackup_$(date +%Y%m%d_%H%M%S).log"
: > "$LOG"
mkdir -p "$OUT"
: > "$MANIFEST"
echo "== Re-backing up APKs from $ANDROID_SERIAL ==" | tee -a "$LOG"
while IFS= read -r line; do
  pkg=$(printf '%s' "$line" | awk '{print $1}')
  [ -z "$pkg" ] && continue
  case "$pkg" in \#*) continue;; esac
  paths=$(adb shell "pm path $pkg" </dev/null 2>/dev/null | sed 's/^package://' | tr -d '\r' | grep -v '^$')
  if [ -z "$paths" ]; then
    echo "$pkg -> NOT INSTALLED (cannot re-backup)" | tee -a "$LOG"
    continue
  fi
  d="$OUT/$pkg"; mkdir -p "$d"
  echo "$paths" | while IFS= read -r ap; do
    [ -z "$ap" ] && continue
    fn=$(basename "$ap")
    if adb pull "$ap" "$d/$fn" >/dev/null 2>&1; then
      echo "$pkg|$d/$fn" >> "$MANIFEST"
      echo "$pkg -> pulled $fn" | tee -a "$LOG"
    else
      echo "$pkg -> FAILED pull $ap" | tee -a "$LOG"
    fi
  done
done < "$LIST"
echo "== Done. Manifest: $MANIFEST ==" | tee -a "$LOG"
