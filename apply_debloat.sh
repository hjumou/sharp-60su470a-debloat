#!/bin/sh
# Sharp 60SU470A debloat (Android 6.0, no root).
# Method: pm uninstall -k --user 0  (APK+data kept on device, reversible via restore_debloat.sh)
# NOTE: this ROM denies pm disable-user AND pm hide from adb shell
#       (SecurityException: CHANGE_COMPONENT_ENABLED_STATE / MANAGE_USERS).
set -u
export ANDROID_SERIAL=192.168.1.194:5555
HERE="$(cd "$(dirname "$0")" && pwd)"
LIST="$HERE/debloat_sharp_su470a.txt"
LOG="$HERE/apply_$(date +%Y%m%d_%H%M%S).log"
: > "$LOG"
echo "== Target $ANDROID_SERIAL ==" | tee -a "$LOG"
echo "== Removing packages (pm uninstall -k --user 0) ==" | tee -a "$LOG"
while IFS= read -r line; do
  pkg=$(printf '%s' "$line" | awk '{print $1}')
  [ -z "$pkg" ] && continue
  case "$pkg" in \#*) continue;; esac
  vis=$(adb shell "pm list packages $pkg" </dev/null 2>/dev/null | grep -c "$pkg")
  if [ "$vis" = "0" ]; then
    echo "$pkg -> already absent, skip" | tee -a "$LOG"
    continue
  fi
  out=$(adb shell "pm uninstall -k --user 0 $pkg" </dev/null 2>&1)
  echo "$pkg -> $out" | tee -a "$LOG"
done < "$LIST"
echo "== Done. Log: $LOG ==" | tee -a "$LOG"
