#!/bin/sh
# ---------------------------------------------------------------------------
# verify_tv.sh  --  精简后的硬性验收（每次改完、每次重启后都跑）
#
# 验收四条（缺一不可）：
#   1. 桌面能回到 Home（显示层没坏）
#   2. 工厂菜单能真正打开（ADB 入口没坏）★ 本次事故的核心教训
#   3. ADB 仍然可连（没把自己锁在外面）
#   4. 关键包齐全 + 包数符合预期
#
# 用法： sh verify_tv.sh [期望包数]     例： sh verify_tv.sh 59
# ---------------------------------------------------------------------------
set -u
export ANDROID_SERIAL="${ANDROID_SERIAL:-192.168.1.194:5555}"
HERE=$(cd "$(dirname "$0")" && pwd)
EXPECT="${1:-}"
PASS=0; FAIL=0
ok()   { printf '  [PASS] %s\n' "$*"; PASS=$((PASS+1)); }
bad()  { printf '  [FAIL] %s\n' "$*"; FAIL=$((FAIL+1)); }

echo "=============================================="
echo " Sharp 60SU470A 验收  $(date '+%F %T')"
echo "=============================================="

adb connect "$ANDROID_SERIAL" >/dev/null 2>&1
STATE=$(adb get-state 2>/dev/null | tr -d '\r')
if [ "$STATE" = "device" ]; then ok "ADB 连接正常 ($ANDROID_SERIAL)"
else bad "ADB 连不上 (state='${STATE:-none}') —— 先去工厂菜单开 ADB"; echo; echo "结论: 无法验收 ($FAIL 项失败)"; exit 1; fi

BC=$(adb shell getprop sys.boot_completed </dev/null 2>/dev/null | tr -d '\r')
[ "$BC" = "1" ] && ok "系统已完成启动" || bad "sys.boot_completed='$BC'（还没起完？）"

# ---- 3. 关键包齐全 ----
echo "-- 关键包检查 --"
for p in com.oversea.aslauncher com.sharp.launcher3 com.sharp.home.resource \
         mstar.factorymenu.ui com.fxc.factory.view com.ctv.factorytest \
         com.ctv.newfactorytest com.cultraview.newfilemanager com.fxc.settings \
         com.android.systemui com.android.packageinstaller com.mstar.tv.service \
         com.mstar.android.tvboot com.mstar.tv.tvplayer.ui; do
  c=$(adb shell "pm list packages $p" </dev/null 2>/dev/null | tr -d '\r' | grep -c "^package:$p\$")
  [ "$c" -ge 1 ] && ok "$p" || bad "$p 缺失"
done

# ---- 1. 桌面 ----
echo "-- 桌面检查 --"
HOME_OUT=$(adb shell "am start -a android.intent.action.MAIN -c android.intent.category.HOME" </dev/null 2>&1 | tr -d '\r')
case "$HOME_OUT" in
  *Error*|*Exception*) bad "启动 Home 失败: $HOME_OUT" ;;
  *) ok "Home intent 可启动" ;;
esac
sleep 2
FOCUS=$(adb shell "dumpsys window" </dev/null 2>/dev/null | tr -d '\r' | grep -m1 "mCurrentFocus")
echo "     当前焦点: ${FOCUS:-<取不到>}"

# ---- 2. 工厂菜单（关键）----
echo "-- 工厂菜单检查（ADB 入口）--"
FM_OUT=$(adb shell "am start -n mstar.factorymenu.ui/mstar.tvsetting.factory.ui.designmenu.DesignMenuActivity" </dev/null 2>&1 | tr -d '\r')
case "$FM_OUT" in
  *Error*|*Exception*|*"does not exist"*|*"Permission Denial"*)
      bad "工厂菜单打不开 -> $FM_OUT"
      echo "     补救: 恢复出厂 / 重新 pm install -r --user 0 原厂 APK" ;;
  *)
      sleep 2
      F2=$(adb shell "dumpsys window" </dev/null 2>/dev/null | tr -d '\r' | grep -m1 "mCurrentFocus")
      case "$F2" in
        *factory*|*Factory*|*designmenu*|*DesignMenu*) ok "工厂菜单已打开 ($F2)" ;;
        *) bad "am start 没报错但焦点不在工厂菜单: ${F2:-<空>}" ;;
      esac ;;
esac
# 回到桌面，别把用户留在工厂菜单里
adb shell "am start -a android.intent.action.MAIN -c android.intent.category.HOME" </dev/null >/dev/null 2>&1

# ---- 4. 包数 ----
echo "-- 包数检查 --"
N=$(adb shell "pm list packages" </dev/null 2>/dev/null | tr -d '\r' | grep -c '^package:')
if [ -n "$EXPECT" ]; then
  [ "$N" = "$EXPECT" ] && ok "包数 $N = 期望 $EXPECT" || bad "包数 $N != 期望 $EXPECT"
else
  echo "     当前包数: $N （未给期望值，仅记录）"
fi

# ---- 被移除的包确实不在了 ----
echo "-- 移除项复核 --"
if [ -f "$HERE/debloat_sharp_su470a.txt" ]; then
  STILL=0
  while IFS= read -r line; do
    pkg=$(printf '%s' "$line" | awk '{print $1}')
    [ -z "$pkg" ] && continue
    case "$pkg" in \#*) continue;; esac
    c=$(adb shell "pm list packages $pkg" </dev/null 2>/dev/null | tr -d '\r' | grep -c "^package:$pkg\$")
    [ "$c" -ge 1 ] && { echo "     仍存在: $pkg"; STILL=$((STILL+1)); }
  done < "$HERE/debloat_sharp_su470a.txt"
  [ "$STILL" = "0" ] && ok "清单内 24 个包均已移除" || bad "$STILL 个包仍在"
fi

# ---- 截图 ----
adb shell screencap -p /sdcard/_verify.png </dev/null 2>/dev/null
adb pull /sdcard/_verify.png "$HERE/backup/verify_$(date +%H%M%S).png" >/dev/null 2>&1
adb shell rm -f /sdcard/_verify.png </dev/null 2>/dev/null
echo "  截图已存 backup/"

echo "=============================================="
printf ' 结论: %s  (PASS=%s FAIL=%s)\n' "$([ "$FAIL" -eq 0 ] && echo 通过 || echo 未通过)" "$PASS" "$FAIL"
echo "=============================================="
[ "$FAIL" -eq 0 ] || exit 1
