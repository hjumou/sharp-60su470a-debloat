#!/bin/sh
# watch_adb_and_grab.sh — 后台哨兵
# 作用：持续轮询电视 ADB，一旦握手成功立刻抢出 3 个桌面 APK + 关键系统包，
#       然后做一次基础验收并退出。用于「电视重启后 ADB 窗口很短」的场景。
set -u
SERIAL="192.168.1.194:5555"
export ANDROID_SERIAL="$SERIAL"
WS="$(cd "$(dirname "$0")" && pwd)"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="$WS/backup/hotgrab_$TS"
MAX=300   # 最多轮询 300 次 × 5s = 25 分钟

i=0
while [ "$i" -lt "$MAX" ]; do
  i=$((i+1))
  adb connect "$SERIAL" >/dev/null 2>&1
  if [ "$(adb -s "$SERIAL" get-state 2>/dev/null | tr -d '\r')" = "device" ]; then
    if adb shell "echo ok" </dev/null 2>/dev/null | grep -q ok; then
      echo "=== ADB 可用！第 $i 次轮询（约 $((i*5)) 秒）==="
      mkdir -p "$OUT"
      echo "--- 抓取桌面 APK ---"
      for p in com.oversea.aslauncher com.sharp.launcher3 com.sharp.home.resource; do
        paths=$(adb shell "pm path $p" </dev/null 2>/dev/null | sed 's/^package://' | tr -d '\r' | grep -v '^$')
        if [ -z "$paths" ]; then echo "  !! $p : pm path 空"; continue; fi
        mkdir -p "$OUT/$p"
        for ap in $paths; do
          fn=$(basename "$ap")
          if adb pull "$ap" "$OUT/$p/$fn" >/dev/null 2>&1 && [ -s "$OUT/$p/$fn" ]; then
            echo "  OK $p -> $fn ($(wc -c < "$OUT/$p/$fn" | tr -d ' ') bytes)"
          else
            echo "  FAIL $p $ap"
          fi
        done
      done
      echo "--- 设备状态 ---"
      echo "  model: $(adb shell getprop ro.product.model </dev/null 2>/dev/null | tr -d '\r')"
      echo "  boot : $(adb shell getprop sys.boot_completed </dev/null 2>/dev/null | tr -d '\r')"
      echo "  pkgs : $(adb shell 'pm list packages' </dev/null 2>/dev/null | grep -c '^package')"
      echo "--- Home 解析 ---"
      adb shell "pm resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME" </dev/null 2>&1 | tail -2
      echo "--- 工厂菜单是否在位 ---"
      adb shell "pm list packages mstar.factorymenu.ui" </dev/null 2>&1 | tr -d '\r'
      cp -R "$OUT" "$WS/backup/hotgrab_LATEST" 2>/dev/null
      echo "=== 抢抓完成: $OUT ==="
      exit 0
    fi
  fi
  sleep 5
done
echo "=== 超时：25 分钟内未等到可用 ADB ==="
exit 1
