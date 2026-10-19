#!/bin/sh
# ---------------------------------------------------------------------------
# baseline_backup.sh  --  恢复出厂后的"开机基线"全量备份
#
# 为什么要有这个脚本：
#   本机 HOME 只有两个候选（com.oversea.aslauncher / com.sharp.launcher3），
#   而且**两个都装在 /data/app**。恢复出厂若清 /data，桌面 APK 就没了 ——
#   这是整台电视唯一"不可再生"的资产。所以只要 ADB 一通，第一件事就是
#   把桌面 APK 抓到本地，再谈任何精简。
#
# 用法：
#   sh baseline_backup.sh
# 产物：
#   backup/postreset_<时间戳>/       快照（包列表/设置/属性/dumpsys/截图）
#   backup/postreset_<时间戳>/apk/   所有 /data 应用 + 关键系统包的 APK
#   backup/postreset_<时间戳>/apk_manifest.txt
# ---------------------------------------------------------------------------
set -u
export ANDROID_SERIAL="${ANDROID_SERIAL:-192.168.1.194:5555}"
HERE=$(cd "$(dirname "$0")" && pwd)
TS=$(date +%Y%m%d_%H%M%S)
B="$HERE/backup/postreset_$TS"
mkdir -p "$B/apk"

say() { printf '%s\n' "$*"; }
die() { printf '!! %s\n' "$*" >&2; exit 1; }

# --- 0. 连接 ---
adb connect "$ANDROID_SERIAL" >/dev/null 2>&1
STATE=$(adb get-state 2>/dev/null | tr -d '\r')
if [ "$STATE" != "device" ]; then
  say "!! 设备未就绪 (state='${STATE:-none}')"
  say "   若是 unauthorized：请看电视屏幕的『允许 USB 调试』弹窗并勾选『一律允许』。"
  say "   若连不上：确认电视已开 ADB，IP 是否为 192.168.1.194。"
  exit 1
fi
say "== 已连接 $ANDROID_SERIAL =="
say "== boot_completed=$(adb shell getprop sys.boot_completed </dev/null 2>/dev/null | tr -d '\r') =="

# --- 1. 文本快照 ---
say "-- 采集快照 --"
adb shell pm list packages -f -u </dev/null > "$B/packages_all.txt" 2>/dev/null
adb shell pm list packages -e    </dev/null > "$B/packages_enabled.txt" 2>/dev/null
adb shell pm list packages -d    </dev/null > "$B/packages_disabled.txt" 2>/dev/null
adb shell pm list packages -3    </dev/null > "$B/packages_thirdparty.txt" 2>/dev/null
adb shell pm list packages -u    </dev/null > "$B/packages_with_uninstalled.txt" 2>/dev/null
adb shell settings list system   </dev/null > "$B/settings_system.txt" 2>/dev/null
adb shell settings list global   </dev/null > "$B/settings_global.txt" 2>/dev/null
adb shell settings list secure   </dev/null > "$B/settings_secure.txt" 2>/dev/null
adb shell getprop                </dev/null > "$B/props.txt" 2>/dev/null
adb shell dumpsys package        </dev/null > "$B/dumpsys_package.txt" 2>/dev/null
adb shell dumpsys package </dev/null 2>/dev/null | grep -A 12 "Preferred Activities" > "$B/home_candidates.txt"
adb shell "dumpsys package | grep -B8 'android.intent.action.BOOT_COMPLETED'" </dev/null > "$B/boot_receivers.txt" 2>/dev/null
adb shell screencap -p /sdcard/_baseline.png </dev/null 2>/dev/null
adb pull /sdcard/_baseline.png "$B/baseline.png" >/dev/null 2>&1
adb shell rm -f /sdcard/_baseline.png </dev/null 2>/dev/null

# --- 2. APK 备份 ---
#   2a. 所有 /data 应用（桌面就在这里面，最重要）
#   2b. 关键 /system 包（工厂菜单、文件管理器、设置、TV 核心）
: > "$B/apk_manifest.txt"

pull_pkg() {
  pkg="$1"
  paths=$(adb shell "pm path $pkg" </dev/null 2>/dev/null | sed 's/^package://' | tr -d '\r' | grep -v '^$')
  [ -z "$paths" ] && return 1
  mkdir -p "$B/apk/$pkg"
  echo "$paths" | while IFS= read -r ap; do
    [ -z "$ap" ] && continue
    fn=$(basename "$ap")
    adb pull "$ap" "$B/apk/$pkg/$fn" >/dev/null 2>&1
    [ -f "$B/apk/$pkg/$fn" ] && echo "$pkg|$ap|apk/$pkg/$fn" >> "$B/apk_manifest.txt"
  done
  return 0
}

say "-- 备份所有 /data 应用（含桌面）--"
tr -d '\r' < "$B/packages_all.txt" \
  | grep '^package:/data/' \
  | sed 's/package:.*=//' \
  | sort -u > /tmp/_data_pkgs.txt
while IFS= read -r p; do
  [ -z "$p" ] && continue
  pull_pkg "$p" && say "   ok  $p" || say "   --  $p (无 APK 路径，跳过)"
done < /tmp/_data_pkgs.txt

say "-- 备份关键 /system 包 --"
for p in mstar.factorymenu.ui com.fxc.factory.view com.ctv.factorytest \
         com.ctv.newfactorytest com.cultraview.newfilemanager com.fxc.settings \
         com.android.packageinstaller com.mstar.tv.service com.mstar.android.tvboot \
         com.mstar.tv.tvplayer.ui com.android.systemui; do
  pull_pkg "$p" && say "   ok  $p" || say "   --  $p (跳过)"
done

# --- 3. 汇总 ---
CNT_APK=$(find "$B/apk" -name '*.apk' 2>/dev/null | wc -l | tr -d ' ')
CNT_PKG=$(cut -d'|' -f1 "$B/apk_manifest.txt" 2>/dev/null | sort -u | wc -l | tr -d ' ')
SIZE=$(du -sh "$B" 2>/dev/null | awk '{print $1}')

say ""
say "================ 完成 ================"
say "目录      : $B"
say "APK 文件  : $CNT_APK 个（覆盖 $CNT_PKG 个包）"
say "总大小    : $SIZE"
say ""
say "★ 请确认桌面 APK 已在备份里（没有这两行就是没抓到，务必查清）："
ls -l "$B/apk/com.oversea.aslauncher/" 2>/dev/null || say "   !! 缺 com.oversea.aslauncher"
ls -l "$B/apk/com.sharp.launcher3/"   2>/dev/null || say "   !! 缺 com.sharp.launcher3"
say ""
say "★ 把整个 $B 目录复制到 U 盘 / 网盘，再开始精简。"
