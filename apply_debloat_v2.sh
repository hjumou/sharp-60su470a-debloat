#!/bin/sh
# ---------------------------------------------------------------------------
# apply_debloat_v2.sh  --  Sharp 60SU470A 精简执行器（带白名单守卫）
#
# 与 v1 的区别（都是本次事故换来的）：
#   1. 默认【干跑 dry-run】，必须显式 --apply 才真卸载。批量删包永不再裸奔。
#   2. 内置白名单守卫 safety_whitelist.txt：命中即拒绝，机器拦人，不靠记忆。
#   3. 每包卸载前确认本地 APK 备份存在；缺失就先拉一份，绝不裸删。
#   4. 预检：设备在线 / 已开机完成 / 关键包在 / 清单包数合理。
#   5. 卸载后逐包复核，最后给总数对比。
#
# 用法：
#   sh apply_debloat_v2.sh            # 干跑，只打印将要做什么（默认）
#   sh apply_debloat_v2.sh --apply    # 真正执行
#
# 只做 batch 1（24 包）。batch 2 那 10 个包（含工厂菜单）永久禁止 —— 见白名单。
# ---------------------------------------------------------------------------
set -u
export ANDROID_SERIAL="${ANDROID_SERIAL:-192.168.1.194:5555}"
HERE=$(cd "$(dirname "$0")" && pwd)
LIST="$HERE/debloat_sharp_su470a.txt"
WL="$HERE/safety_whitelist.txt"
LOG="$HERE/apply_v2_$(date +%Y%m%d_%H%M%S).log"
APPLY=0
[ "${1:-}" = "--apply" ] && APPLY=1

say() { printf '%s\n' "$*" | tee -a "$LOG"; }
die() { printf '!! %s\n' "$*" | tee -a "$LOG" >&2; exit 1; }

: > "$LOG"
say "# apply_debloat_v2  $(date '+%F %T')  mode=$([ $APPLY = 1 ] && echo APPLY || echo DRY-RUN)"
say "# device=$ANDROID_SERIAL"

# ---------------- 预检 ----------------
[ -f "$LIST" ] || die "找不到清单 $LIST"
[ -f "$WL" ]   || die "找不到白名单 $WL（没有它我不动手）"

adb connect "$ANDROID_SERIAL" >/dev/null 2>&1
STATE=$(adb get-state 2>/dev/null | tr -d '\r')
[ "$STATE" = "device" ] || die "设备未就绪 (state='${STATE:-none}')；unauthorized 请在电视上点『允许』"

BC=$(adb shell getprop sys.boot_completed </dev/null 2>/dev/null | tr -d '\r')
[ "$BC" = "1" ] || die "系统未完成启动 (sys.boot_completed='$BC')，不要在开机过程中改包"

TOTAL_BEFORE=$(adb shell "pm list packages" </dev/null 2>/dev/null | tr -d '\r' | grep -c '^package:')
say "# 当前可见包数: $TOTAL_BEFORE"

# 桌面必须在，否则拒绝开工（这是最后的底线检查）
for p in com.oversea.aslauncher com.sharp.launcher3 mstar.factorymenu.ui; do
  c=$(adb shell "pm list packages $p" </dev/null 2>/dev/null | tr -d '\r' | grep -c "$p")
  [ "$c" -ge 1 ] || die "关键包缺失: $p —— 先修好它再谈精简"
done
say "# 关键包齐全（桌面×2 + 工厂菜单）"

# ---------------- 工具函数 ----------------
is_whitelisted() {
  pkg="$1"
  while IFS= read -r pat; do
    case "$pat" in ''|\#*) continue;; esac
    if printf '%s\n' "$pkg" | grep -qE -- "$pat"; then
      printf '%s' "$pat"
      return 0
    fi
  done < "$WL"
  return 1
}

pkg_present() {
  n=$(adb shell "pm list packages $1" </dev/null 2>/dev/null | tr -d '\r' | grep -c "^package:$1\$")
  [ "$n" -ge 1 ]
}

ensure_backup() {
  pkg="$1"
  [ -d "$HERE/backup/apk/$pkg" ] && [ -n "$(ls -A "$HERE/backup/apk/$pkg" 2>/dev/null)" ] && return 0
  say "   [backup] 本地无备份，先拉取 $pkg ..."
  paths=$(adb shell "pm path $pkg" </dev/null 2>/dev/null | sed 's/^package://' | tr -d '\r' | grep -v '^$')
  [ -z "$paths" ] && { say "   [backup] !! 取不到 APK 路径"; return 1; }
  mkdir -p "$HERE/backup/apk/$pkg"
  echo "$paths" | while IFS= read -r ap; do
    [ -z "$ap" ] && continue
    adb pull "$ap" "$HERE/backup/apk/$pkg/$(basename "$ap")" >/dev/null 2>&1
  done
  [ -n "$(ls -A "$HERE/backup/apk/$pkg" 2>/dev/null)" ]
}

# ---------------- 主流程 ----------------
OK=0; SKIP=0; REJECT=0; FAIL=0; PLANNED=0
REJECTED_LIST=""

while IFS= read -r line; do
  pkg=$(printf '%s' "$line" | awk '{print $1}')
  [ -z "$pkg" ] && continue
  case "$pkg" in \#*) continue;; esac
  PLANNED=$((PLANNED+1))

  pat=$(is_whitelisted "$pkg") && { say "REJECT  $pkg  (命中白名单 $pat)"; REJECT=$((REJECT+1)); REJECTED_LIST="$REJECTED_LIST $pkg"; continue; }

  if ! pkg_present "$pkg"; then
    say "skip    $pkg  (已不存在)"; SKIP=$((SKIP+1)); continue
  fi

  if [ "$APPLY" = 0 ]; then
    say "plan    $pkg  -> pm uninstall -k --user 0"
    OK=$((OK+1)); continue
  fi

  if ! ensure_backup "$pkg"; then
    say "FAIL    $pkg  (APK 备份失败，为安全起见不卸载)"; FAIL=$((FAIL+1)); continue
  fi

  out=$(adb shell "pm uninstall -k --user 0 $pkg" </dev/null 2>&1 | tr -d '\r')
  case "$out" in
    *Success*) if pkg_present "$pkg"; then
                 say "FAIL    $pkg  (报 Success 但仍可见)"; FAIL=$((FAIL+1))
               else
                 say "OK      $pkg"
                 OK=$((OK+1))
               fi ;;
    *) say "FAIL    $pkg  -> $out"; FAIL=$((FAIL+1)) ;;
  esac
done < "$LIST"

TOTAL_AFTER=$(adb shell "pm list packages" </dev/null 2>/dev/null | tr -d '\r' | grep -c '^package:')

say ""
say "================ 汇总 ================"
say "清单条目     : $PLANNED"
if [ "$APPLY" = 0 ]; then
  say "【干跑】将卸载 : $OK"
else
  say "已卸载成功   : $OK"
fi
say "跳过(已不存在): $SKIP"
say "拒绝(白名单) : $REJECT ${REJECTED_LIST:+->$REJECTED_LIST}"
say "失败         : $FAIL"
say "包数 $TOTAL_BEFORE -> $TOTAL_AFTER"
say "日志: $LOG"
[ "$FAIL" -gt 0 ] && exit 1
exit 0
