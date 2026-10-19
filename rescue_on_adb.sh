#!/bin/sh
# ============================================================================
# rescue_on_adb.sh — 一旦 ADB 可用，一次窗口内完成「先备份 → 再还原 → 再验收」
#
# 目标（按优先级）：
#   1) 抢救出 3 个桌面 APK（aslauncher / launcher3 / home.resource）—— 唯一不可再生资产
#   2) 还原 batch2 里被误删的工厂类包（factory menu / factorytest / fxc.factory.view）
#   3) 还原 batch1 的 24 个包（可选，默认不还原，因为你本来就想去掉它们）
#   4) 硬验收：工厂菜单能否真正启动、Home 是否正常
#
# 用法：
#   sh rescue_on_adb.sh              # 备份 + 还原工厂类关键包 + 验收
#   sh rescue_on_adb.sh --all        # 额外把 batch1 的 24 个包也全部还原
#   sh rescue_on_adb.sh --backup-only
#
# 设计原则：每一步都可单独重跑（幂等），任何一步失败不中断后续步骤。
# ============================================================================
set -u

SERIAL="${ANDROID_SERIAL:-192.168.1.194:5555}"
export ANDROID_SERIAL="$SERIAL"

WS="$(cd "$(dirname "$0")" && pwd)"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="$WS/backup/rescue_$TS"

# batch2 备份源（Antigravity 那份）
B2="/Volumes/SSD/workspace/WorkSpace/sharp-60su470a-debloat/backup/apk_batch2"

MODE="default"
[ "${1:-}" = "--all" ] && MODE="all"
[ "${1:-}" = "--backup-only" ] && MODE="backup-only"

say() { printf '%s\n' "$*"; }
hr()  { say "------------------------------------------------------------"; }

# ---------------------------------------------------------------- 0. 预检
hr; say "[0] 预检"
adb connect "$SERIAL" >/dev/null 2>&1
STATE="$(adb -s "$SERIAL" get-state 2>&1 | tr -d '\r')"
say "  get-state = $STATE"
if [ "$STATE" != "device" ]; then
  say "  ✗ 设备不可用，退出（不做任何操作）"
  exit 1
fi
BOOT="$(adb shell getprop sys.boot_completed </dev/null 2>/dev/null | tr -d '\r')"
say "  sys.boot_completed = $BOOT"
if [ "$BOOT" != "1" ]; then
  say "  ✗ 系统未启动完成，退出"
  exit 1
fi
mkdir -p "$OUT"
say "  输出目录: $OUT"

# ---------------------------------------------------------- 1. 抢救桌面 APK
hr; say "[1] 抢救桌面 APK（最关键，先做这一步）"
CRIT="com.oversea.aslauncher com.sharp.launcher3 com.sharp.home.resource"
RESULT_CRIT=""
for p in $CRIT; do
  paths="$(adb shell "pm path $p" </dev/null 2>/dev/null | sed 's/^package://' | tr -d '\r' | grep -v '^$')"
  if [ -z "$paths" ]; then
    say "  ✗ $p : pm path 为空（可能已不在设备上）"
    RESULT_CRIT="$RESULT_CRIT $p:MISSING"
    continue
  fi
  mkdir -p "$OUT/$p"
  ok=0
  for ap in $paths; do
    fn="$(basename "$ap")"
    if adb pull "$ap" "$OUT/$p/$fn" >/dev/null 2>&1 && [ -s "$OUT/$p/$fn" ]; then
      sz="$(wc -c < "$OUT/$p/$fn" | tr -d ' ')"
      say "  ✓ $p -> $fn ($sz bytes)"
      ok=1
    else
      say "  ✗ $p : 拉取失败 $ap"
    fi
  done
  [ "$ok" = "1" ] && RESULT_CRIT="$RESULT_CRIT $p:OK" || RESULT_CRIT="$RESULT_CRIT $p:FAIL"
done

# 同时把防火墙级的 home/launcher 相关包也带走，防止后续再翻车
for p in com.sharp.adapter com.cultraview.newfilemanager com.fxc.settings; do
  paths="$(adb shell "pm path $p" </dev/null 2>/dev/null | sed 's/^package://' | tr -d '\r' | grep -v '^$')"
  [ -z "$paths" ] && { say "  - $p : 无 APK 可拉"; continue; }
  mkdir -p "$OUT/$p"
  for ap in $paths; do
    adb pull "$ap" "$OUT/$p/$(basename "$ap")" >/dev/null 2>&1 \
      && say "  ✓ $p 已备份" || say "  ✗ $p 拉取失败"
  done
done

say "  桌面备份结果:$RESULT_CRIT"

[ "$MODE" = "backup-only" ] && { hr; say "backup-only 模式结束"; exit 0; }

# ------------------------------------------------ 2. 还原工厂类关键包（batch2）
hr; say "[2] 还原工厂类关键包（batch2）"
# 顺序很重要：先工厂菜单本体，再备用入口
PKGS_B2="mstar.factorymenu.ui com.fxc.factory.view com.ctv.factorytest com.ctv.newfactorytest com.android.onetimeinitializer com.svox.pico com.android.musicfx"
if [ "$MODE" = "all" ]; then
  PKGS_B2="$PKGS_B2 com.estrongs.android.pop com.xiaobaifile.tv com.sharp.fxc.newsetupwiz"
fi

restore_one() {
  p="$1"
  apk="$B2/$p.apk"
  if [ ! -f "$apk" ]; then
    say "  ✗ $p : 本地无备份 ($apk)"
    return 1
  fi
  # 已在设备上则跳过，避免重复安装
  if adb shell "pm path $p" </dev/null 2>/dev/null | grep -q "package:"; then
    say "  = $p 已在设备上，跳过"
    return 0
  fi
  adb push "$apk" "/data/local/tmp/_r.apk" >/dev/null 2>&1 || { say "  ✗ $p push 失败"; return 1; }
  # 关键：必须带 --user 0，否则装完不显示（本 ROM 已验证的坑）
  r="$(adb shell "pm install -r --user 0 /data/local/tmp/_r.apk" </dev/null 2>&1 | tr -d '\r')"
  adb shell "rm -f /data/local/tmp/_r.apk" </dev/null >/dev/null 2>&1
  case "$r" in
    *Success*) say "  ✓ $p 已还原  ($r)"; return 0 ;;
    *)         say "  ✗ $p 还原失败: $r"; return 1 ;;
  esac
}

N_OK=0; N_FAIL=0
for p in $PKGS_B2; do
  if restore_one "$p"; then N_OK=$((N_OK+1)); else N_FAIL=$((N_FAIL+1)); fi
done
say "  小计: 成功 $N_OK / 失败 $N_FAIL"

# ------------------------------------------------ 3. 可选：还原 batch1 的 24 个
if [ "$MODE" = "all" ]; then
  hr; say "[3] 还原 batch1（24 包）"
  i=0
  while IFS= read -r line; do
    pkg=$(printf '%s' "$line" | awk '{print $1}')
    [ -z "$pkg" ] && continue
    case "$pkg" in \#*) continue ;; esac
    apk=""
    for cand in "$WS/backup/apk/$pkg"/*.apk; do
      [ -f "$cand" ] && apk="$cand" && break
    done
    if [ -z "$apk" ]; then say "  ✗ $pkg : 无本地备份"; N_FAIL=$((N_FAIL+1)); continue; fi
    if adb shell "pm path $pkg" </dev/null 2>/dev/null | grep -q "package:"; then
      say "  = $pkg 已在，跳过"; continue
    fi
    adb push "$apk" "/data/local/tmp/_r.apk" >/dev/null 2>&1
    r="$(adb shell "pm install -r --user 0 /data/local/tmp/_r.apk" </dev/null 2>&1 | tr -d '\r')"
    case "$r" in
      *Success*) say "  ✓ $pkg"; N_OK=$((N_OK+1)) ;;
      *)         say "  ✗ $pkg : $r"; N_FAIL=$((N_FAIL+1)) ;;
    esac
    i=$((i+1))
  done < "$WS/debloat_sharp_su470a.txt"
  say "  小计累计: 成功 $N_OK / 失败 $N_FAIL"
fi

# ------------------------------------------------------------- 4. 硬验收
hr; say "[4] 硬验收"
say "  包总数: $(adb shell "pm list packages" </dev/null 2>/dev/null | grep -c '^package')"

say "  --- 关键包在位检查 ---"
for p in mstar.factorymenu.ui com.oversea.aslauncher com.sharp.launcher3 com.sharp.home.resource com.fxc.settings; do
  c=$(adb shell "pm list packages $p" </dev/null 2>/dev/null | grep -c "$p")
  say "    $p = $c"
done

say "  --- 工厂菜单 Activity 是否可解析 ---"
adb shell "pm resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.MAINMENU" </dev/null 2>&1 | tail -3
say "  直接尝试启动工厂菜单:"
adb shell "am start -n mstar.factorymenu.ui/mstar.tvsetting.factory.ui.designmenu.DesignMenuActivity" </dev/null 2>&1 | head -4

say "  --- Home 是否可解析 ---"
adb shell "pm resolve-activity --brief -a android.intent.action.MAIN -c android.intent.category.HOME" </dev/null 2>&1 | tail -3

say "  --- 截图存证 ---"
adb shell "screencap -p /sdcard/rescue_$TS.png" </dev/null >/dev/null 2>&1
adb pull "/sdcard/rescue_$TS.png" "$OUT/after_rescue.png" >/dev/null 2>&1 \
  && say "    ✓ 截图: $OUT/after_rescue.png" || say "    ✗ 截图失败"
adb shell "rm -f /sdcard/rescue_$TS.png" </dev/null >/dev/null 2>&1

hr
say "完成。备份在: $OUT"
say "若工厂菜单仍打不开，请把上面 am start 的输出发我。"
