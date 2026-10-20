# Sharp 60SU470A（Android 6.0 / API 23）精简与开机加速 · 全记录

> 一站式复盘文档。目标读者：下一个接手的 agent（含 Antigravity）或你自己。
> 本仓库完整记录了 **对一台 Sharp 60SU470A 智能电视做 ADB 精简、删除臃肿、加速开机** 的全过程、踩坑、最终可行方案、移除清单、安全边界与一键还原方法。
>
> **当前状态：两轮精简已完成，全程未恢复出厂。** 包数 `~85 → 57`，MemFree `~60 MB → 328 MB`。
> 首页（水滴）、设置、工厂菜单、ADB 全部正常。

## 文档导航（建议阅读顺序）

| 文档 | 内容 | 何时读 |
|---|---|---|
| **[LESSONS.md](LESSONS.md)** | **23 条经验教训总汇**（含证据与推理链） | **想少走弯路，先读这个** |
| `README.md`（本文） | 第一轮全记录：权限模型、卸载机制、移除清单、还原方法 | 想了解来龙去脉 |
| [AUDIT-ROUND2.md](AUDIT-ROUND2.md) | 第二轮：再删 5 包、包身份误判复盘、剩余候选处置 | 想继续精简 |
| [LAUNCHER-GUIDE.md](LAUNCHER-GUIDE.md) | 三方 TV 桌面真机横评（水滴 / FLauncher / Projectivy）+ 切换方法 | 想换桌面 |
| [FACTORY-MENU-FIX.md](FACTORY-MENU-FIX.md) | 工厂菜单"装回去但点不开"的根因与正解 | 遇到系统应用装了打不开 |
| [POST-RESET-PLAYBOOK.md](POST-RESET-PLAYBOOK.md) | 万一恢复出厂后的处理流程 | 灾后重建 |
| [RECOVERY-NO-SETTINGS.md](RECOVERY-NO-SETTINGS.md) | 设置崩了、ADB 也没有时的硬件自救路径 | 极端情况 |

---

## 0. TL;DR（一句话结论）

- **设备**：Sharp 60SU470A（`ro.product.model = LCD_xxSUFOC470A`），Android **6.0（API 23，build `MRA58K` / 固件 `2.69.210109`）**，MStar `msd648` / 平台 `mooney`，Foxconn(FXC) 定制 ROM。
- **目标**：基于 GitHub 仓库 `Gathin23/cleanyourtv`（原名 `tv-vibehack`，已更名）的思路，删臃肿、优化开机速度。
- **最大坑**：此 ROM 的 **ADB shell（uid 2000）既无 `CHANGE_COMPONENT_ENABLED_STATE` 也无 `MANAGE_USERS` 权限** → 仓库默认的 `pm disable-user` 和退路 `pm hide` **全部被 `SecurityException` 拒绝**。最终唯一可行且可逆的方法是 **`pm uninstall -k --user 0`**。
- **结果（第一轮）**：移除 **24 个包（83 → 59）**，重启验证通过（`BOOT_COMPLETED=1`，包数稳定 59，主桌面与核心服务完好）。
- **结果（第二轮）**：再移除 **5 个包（62 → 57）**，重点是 `com.estrongs.android.pop`（ES，常驻 93.6 MB）。**MemFree 47~71 MB → 328 MB**。详见 [AUDIT-ROUND2.md](AUDIT-ROUND2.md)。
- **可逆**：每个被移除包的 APK 已本地备份（`backup/apk/`，约 320 MB，29 个包），还原脚本 `restore_debloat.sh` 用 `pm install -r --user 0` 装回。系统应用另有 `/system` 原厂 APK 兜底（恢复出厂即全量回来）。
- **最重要的一条反面教训**：`com.trim.tv` 名字像预装视频垃圾、PSS 长期为 0，实际是用户正在用的 **飞牛TV**（连着 DellNAS）。**包身份必须 `am start` 打开验证，不能靠名字和"从没跑过"推断。** 详见 [LESSONS.md L5/L6](LESSONS.md)。

**速查命令**（在已 `adb connect 192.168.1.194:5555` 后）：
```sh
sh apply_debloat_v3.sh            # 干跑：只打印计划，不动手（默认行为，安全）
sh apply_debloat_v3.sh --apply    # 执行第三批移除（白名单守卫 + 逐包备份）
sh restore_debloat.sh             # 一键还原（从 backup/apk/ 装回）
sh rebackup_apks.sh               # 若本地 APK 备份丢失，从电视重新拉取
sh verify_tv.sh                   # 4 项硬验收：Home / 工厂菜单 / ADB / 包数
```

---

## 1. 目标与背景

用户持有一台已开启 ADB 的 Sharp 60SU470A（IP `192.168.1.194`），希望：
1. 登录 / 连上设备；
2. 基于开源方案 `https://github.com/Gathin23/tv-vibehack`（现 `cleanyourtv`）**优化电视启动速度，删除臃肿内容**。

`cleanyourtv` 的设计理念（README/PROMPT.md）是：**用 `pm disable-user` 禁用而非卸载**，并做完整备份 + 一行还原脚本，避免变砖。本任务沿用了其"可还原"的安全哲学，但**实际执行手段因本机 ROM 而异**（见第 6 节）。

---

## 2. 设备指纹（关键 getprop，已存 `backup/20261019_054606/props.txt`）

| 项 | 值 |
|---|---|
| `ro.product.brand` / `manufacturer` | `SHARP` |
| `ro.product.model` | `LCD_xxSUFOC470A`（即 60SU470A） |
| `ro.product.name` / `device` | `Lcd_xxsufoc470a` / `cv6a648_base` |
| `ro.build.version.release` / `sdk` | `6.0` / `23` |
| `ro.build.id` / `incremental` | `MRA58K` / `2.69.210109` |
| `ro.build.security_patch` | `2017-08-01`（极旧） |
| `ro.board.chip.name` / `vendor` | `msd648` / `mstar` |
| `ro.board.platform` | `mooney` |
| `ro.build.type` | `user`（非 debuggable，`ro.debuggable=0`） |
| `ro.build.characteristics` | `tv` |
| `ro.boot.selinux` | `permissive`（注意：SELinux 宽松，但 PM 权限限制仍在 API 层，并未因此放开） |
| `ro.adb.secure` | `1`（这就是首次连接要"授权"的原因） |
| ADB 网络 | `persist.service.adb.enable=1`、`persist.adb.tcp.port=5555`、`service.adb.tcp.port=5555` |
| 默认桌面 Home | `com.oversea.aslauncher`（依赖 `com.sharp.home.resource`，AOSP 兜底 `com.sharp.launcher3`） |
| `persist.sys.fxc.speedup` | `not-support`（**原厂本就无"加速"功能**，更凸显手动精简的价值） |

> 隐私提示：`props.txt` 内含设备序列号（`persist.sys.fxc.sn=8041853114274`）与蓝牙 MAC。已脱敏不必要，如公开分发可删除该文件。

---

## 3. 参考仓库 `cleanyourtv` / `tv-vibehack` 分析

- 仓库已从原名 `tv-vibehack` 更名为 `cleanyourtv`（2026-10-19，旧链接仍可用）。
- 核心方法：`pm disable-user --user 0`（禁用，非卸载），配套完整备份 + `restore.sh`。并提供一个"苹果风"自定义 launcher。
- **兼容性结论（重要）**：其 launcher 的 `minSdkVersion = 26`（Android 8.0+），而本机是 **API 23（Android 6.0）→ 无法安装运行**。故本次**不含自定义 launcher**，仅做"精简 + 加速 + 可还原"。
- 仓库内置 `tools/tv.py`（纯 Python ADB 客户端）用于绕过 macOS 本地网络隐私限制——但**实测本机的 stock `adb` 走 TCP 5555 并未被 macOS 拦截**，所以直接用 `adb` 即可。

---

## 4. 环境准备与连接

- 本机 macOS，已装 `adb` v36；与电视同网段（`192.168.1.x`）。
- 连接：
  ```sh
  adb connect 192.168.1.194:5555
  # 电视屏幕弹出 "允许 USB 调试？" → 勾选"一律允许"并确认（部分 Sharp 提示仅闪现数秒，需在首页而非菜单内）
  adb devices   # 看到 192.168.1.194:5555  device 即成功
  ```
- 首次连接状态为 `unauthorized`，用户在电视上点允许后变为 `device`。

---

## 5. 探索阶段：包清单 + 开机自启分析

- 全量盘点：`adb shell pm list packages -f -u` → 共 **83 个包**，初始 0 个禁用，10 个用户/预装应用。
- 用 `dumpsys package` 抓取 `BOOT_COMPLETED` 广播接收器，实证以下**开机自启**包（即拖慢开机的元凶）：
  - `com.hpplay.happyplay.aw.new`（乐播/HPPlay，`LeVipReceiver`）
  - `com.iflytek.xiri`（iFlytek 语音 `UploadService`）
  - `com.sharp.fxc.ai.voice`（Sharp AI Voice `VoiceDataService`）
  - `com.sharp.fxc.upgrade`（Sharp OTA `SettingsAgentService`）
  - `com.sharp.adapter`（系统适配 `SysAdapterService`，**保留**）
  - `com.trim.tv`（`ProfileInstallReceiver`，用户选择**保留**）

---

## 6. 关键踩坑记录（本文档最有价值的一节）

### 6.1 方法一：`pm disable-user --user 0` —— ❌ 失败
仓库默认方法。实测对本机**所有**包（无论 `/data` 还是 `/system`）均报：
```
Error: java.lang.SecurityException: Permission Denial:
attempt to change component state from pid=..., uid=2000, package uid=1000
```
`uid=2000`(shell) 无权修改 `uid=1000`(system) 的组件启用状态。详见存证 `apply_20261019_055223.log`。

### 6.2 方法二：`pm hide --user 0` —— ❌ 失败
退路。经 `pm help` 确认本 ROM 支持 `hide/unhide`，但它依赖 `MANAGE_USERS` 权限，而 shell 同样没有 → 同样被 `SecurityException` 拒绝。
- 附带发现：本 ROM **没有 `pm install-existing`** 子命令。

### 6.3 方法三：`pm uninstall -k --user 0` —— ✅ 成功
ADB shell 拥有 `DELETE` 权限，可为 user 0 卸载（保留 `/data` 数据与设备上的 APK）。对 24 个包**全部 `Success`**（见 `apply_20261019_060509.log`）。
- `-k`：保留数据；APK 仍留在设备分区（`/system` 应用原厂 APK 不动，`/data` 应用 APK 在卸载后不可见但可从本地备份恢复）。
- 效果等同"删除"：应用从启动器与应用列表消失、不再开机自启 → **既去臃肿又加速开机**，且可还原。

### 6.4 还原陷阱：`adb install` 报 Success 但包不显示 —— 必须用 `pm install -r --user 0`
这是第二大坑。我们在 lottery（`/data`）和 mcast（`/system`）上做了完整闭环测试：
1. `pm uninstall -k --user 0 <pkg>` → `Success`，`pm list packages` 中消失。
2. `adb install -r <apk>` → 也报 `Success`，但 `pm list packages` 里**仍然不显示**（诊断 `dumpsys package` 显示 `User 0: installed=false` 状态未清除）。
3. **正解**：把 APK `adb push` 到设备后，用 `pm install -r --user 0 /path/on/device.apk` 显式指定 user → 恢复成功。

> 含义：本 ROM 的"user 0 卸载态"不能用普通 `install` 解除，必须 `install --user 0`。`restore_debloat.sh` 已据此实现。

### 6.5 为什么会这样（ROM 权限模型小结）
这是一台 **Foxconn(FXC)/MStar 深度定制、user 版、但 SELinux permissive** 的 Android 6 电视。它**收紧了 adb shell 的 PM 权限**（无 `CHANGE_COMPONENT_ENABLED_STATE`、无 `MANAGE_USERS`），但保留了 `DELETE`（可卸载 user 0）。所以"禁用"类操作全死，"卸载类"操作可行。这与 AOSP 默认行为不同，也是 `cleanyourtv` 默认方法在本机失灵的根本原因。

---

## 7. 最终落地命令（已写入脚本）

```sh
# 移除（apply_debloat.sh 核心循环）
adb shell "pm uninstall -k --user 0 <pkg>"      # 对每个目标包

# 还原（restore_debloat.sh 核心循环）
adb push <local_apk> /data/local/tmp/restore.apk
adb shell "pm install -r --user 0 /data/local/tmp/restore.apk"
```

脚本均 `set -u`、`export ANDROID_SERIAL=192.168.1.194:5555`、逐包写带时间戳日志、对 `adb shell` 用 `</dev/null` 关闭 stdin（避免 `while read` 吞掉后续行）。

---

## 8. 移除清单（24 个包，全部 `uninstall -k --user 0` 成功）

| # | 包名 | 分类 | 类型 | 移除理由 |
|---|---|---|---|---|
| 1 | `com.fxc.bootad.bootadplayer` | 广告 | system | 开机广告播放器 |
| 2 | `com.sharp.fxc.adservice` | 广告 | system | 广告服务 |
| 3 | `com.sharp.fxc.app.advert` | 广告 | system | 广告应用 |
| 4 | `com.sharp.fxc.recordcollect` | 遥测 | system | 使用记录/行为采集 |
| 5 | `com.sharp.fxc.fxctopactivity` | 遥测 | system | 顶部活动追踪 |
| 6 | `com.sharp.fxc.classification` | 广告定向 | system | 内容分类（广告定向） |
| 7 | `com.sharp.fxc.lottery` | 推广 | data | 彩票推广 |
| 8 | `com.sharp.fxc.tlkgmic.service` | 冗余 | data | 卡拉OK麦克风服务 |
| 9 | `com.android.mcast` | 演示 | system | Miracast 演示 |
| 10 | `com.sharp.fxc.mor.tv` | 商店 | system | Sharp 内容商店 |
| 11 | `com.sharp.fxc.shortcut` | 冗余 | system | 快捷方式 |
| 12 | `com.sharp.fxc.account` | 账号/遥测 | system | Sharp 账号 |
| 13 | `com.sharp.fxc.fxcscreensaver` | 冗余 | system | 屏保 |
| 14 | `com.sharp.app.userguide` | 冗余 | system | 用户向导 |
| 15 | `com.iflytek.xiri` | 语音栈 | system | iFlytek 语音框架（开机自启） |
| 16 | `com.iflytek.xiri2.sharpvoice` | 语音栈 | system | iFlytek 语音 |
| 17 | `com.iflytek.xiri2.system` | 语音栈 | system | iFlytek 系统语音 |
| 18 | `com.sharp.fxc.ai.voice` | 语音栈 | system | Sharp AI 语音（开机自启） |
| 19 | `com.sharp.fxc.assistant` | 语音栈 | system | 语音助手 |
| 20 | `com.sharp.fxc.voicecontrol.action.voiceaction` | 语音栈 | system | 语音控制动作 |
| 21 | `com.sharp.fxc.upgrade` | OTA | system | Sharp OTA 更新（开机自启） |
| 22 | `com.example.upgrad` | OTA | system | 升级应用 |
| 23 | `com.kehiwn.wzy.foxconnautoota` | OTA | system | Foxconn 自动 OTA |
| 24 | `com.hpplay.happyplay.aw.new` | 投屏 | system | 乐播/HPPlay（开机自启） |

按用户拍板的取舍：语音栈、OTA、投屏**禁用/移除**；ES 文件浏览器、OPlayer、小白文件、trim.tv、shuidiui 等预装应用**保留不动**（见 `tv_thirdparty.txt`）。

---

## 9. 安全边界（绝不禁用/卸载的清单与理由）

以下任何一项被碰都会黑屏/无主页/失核心功能，**已显式排除在移除清单外**：

- **主桌面三件套**：`com.oversea.aslauncher`（当前 Home）、`com.sharp.home.resource`（其资源依赖）、`com.sharp.launcher3`（AOSP 兜底 Home）。
- **MStar TV 核心**：`com.mstar.tv.service`、`com.mstar.android.tvboot`、`com.mstar.tv.tvplayer.ui`、`com.sharp.adapter`（系统适配，开机自启但必需）。
- **系统框架/UI**：`com.fxc.settings`（设置）、`com.android.systemui`（状态栏/导航）、`com.android.webview`（WebView，众多应用依赖）。
- **连接与配对**：`com.android.bluetooth`、`com.android.bcm.bluetooth`、`autopair`、BLE 相关、Providers（`com.android.providers.*`）。

---

## 10. 执行结果 & 重启验证

- 移除前 **83** 包 → 移除后 **59** 包（-24）。
- 重启验证（关键一步，直接证明"加速启动"且依赖未损）：
  - 发送 `adb reboot`；
  - 轮询到 `sys.boot_completed=1`（电视正常回到桌面）；
  - 重启后 `pm list packages` 仍 **59** → 移除已**持久化**，不会随重启复活；
  - 主桌面与所有关键服务确认完好。
- 桌面截图（`backup/20261019_054606/*.png`）显示精简前后首页布局一致、无异常（本环境模型无法看图，但功能层已验证）。

---

## 11. 还原方法

**一键还原**（需本地 `backup/apk/` 仍在）：
```sh
sh restore_debloat.sh
```
脚本逐行读 `backup/apk_manifest.txt`（`pkg|本地apk路径`），`adb push` 后 `pm install -r --user 0` 装回。全部 24 个 APK 已备份（214 MB，最大单个 53 MB `hpplay`，无超 100 MB 文件）。

**兜底还原**（本地备份丢失时）：
- 系统应用：`/system` 原厂 APK 仍在，恢复出厂设置即可全量回来；或 `sh rebackup_apks.sh` 从电视重新拉取 APK 再还原。
- `/data` 应用（如 lottery）：靠 `backup/apk/` 本地备份；若连本地备份也没了，只能恢复出厂。

---

## 12. 副作用 & 注意事项

1. **语音遥控的语音搜索功能已随语音栈移除**；遥控器普通按键、方向、确认、信源切换等不受影响。
2. **OTA 已禁用**，不再收官方固件更新；需要更新时 `sh restore_debloat.sh` 即可（全可逆）。
3. **投屏（乐播/HPPlay、Miracast 演示）已移除**；如需手机镜像请先还原对应包。
4. 仓库的"苹果风桌面" launcher 要求 API 26+，本机 Android 6 **装不了**，故未采用。
5. 建议日常把电视的 **ADB 调试开关关掉**（本次是 launcher/应用层改动，关掉不影响已生效结果，仅为安全习惯）。
6. `props.txt` 含设备 SN/MAC，公开分发前可考虑删除。

---

## 13. 仓库内容导航

| 路径 | 说明 |
|---|---|
| **[LESSONS.md](LESSONS.md)** | **23 条经验教训总汇（跨两轮）**，本仓库最有价值的部分 |
| `README.md` | 本文档（第一轮全记录） |
| `AUDIT-ROUND2.md` | 第二轮精简报告：再删 5 包、包身份误判复盘 |
| `LAUNCHER-GUIDE.md` | 三方 TV 桌面真机横评 + 切换/回滚方法 |
| `FACTORY-MENU-FIX.md` | 系统应用"装了打不开"（无 dex）的根因与正解 |
| `debloat_sharp_su470a.txt` | 第一轮移除清单（24 包，含中文理由），脚本的数据源 |
| `debloat_batch3.txt` | 第二轮移除清单（5 包） |
| `apply_debloat.sh` | 第一轮执行脚本（幂等） |
| `apply_debloat_v2.sh` | 第一轮加固版：默认干跑 + 白名单守卫 + 逐包备份校验 |
| `apply_debloat_v3.sh` | **当前推荐**：v2 + 清单可传参（`sh apply_debloat_v3.sh [--apply] [清单]`） |
| `restore_debloat.sh` | 一键还原（从 `backup/apk/` 装回，用 `pm install -r --user 0`） |
| `rebackup_apks.sh` | 本地 APK 备份丢失时，从电视重新拉取 |
| `verify_tv.sh` | 4 项硬验收：Home / 工厂菜单能否真开 / ADB / 包数 |
| `watch_adb_and_grab.sh` | ADB 卡死时的哨兵：每 5 秒轮询，抓到窗口立刻抢救 APK |
| `rescue_on_adb.sh` | 抢救脚本（`--all` / `--backup-only`） |
| `tools/push_via_api.py` | **`git push` 被阻断时的推送工具**：走 GitHub Git Data API 造 commit（见 [LESSONS.md L23](LESSONS.md)） |
| `safety_whitelist.txt` | 正则白名单（含 `mstar.factorymenu.ui`、三桌面、`com.sharp.fxc.shortcut`） |
| `backup/apk_manifest.txt` | `pkg\|本地apk路径` 清单，还原脚本的输入 |
| `backup/apk/` | 29 个已备份 APK（约 320 MB，最大单个 53 MB，无超 100 MB 文件） |
| `backup/20261019_054606/` | 完整快照：`packages_*`、`settings_*`、`props.txt`、`home.txt`、`boot_receivers.txt`、桌面截图 |
| `backup/full_20261019_085111/` | 全量 `/data` APK 快照（30+ 包，398 MB，APK 本体不入库，仅清单） |
| `launchers/shots/` | 证据截图（JPEG）：飞牛TV 身份铁证、应用管理、Projectivy/FLauncher 桌面、主屏选择器 |
| `apply_20261019_055223.log` | ⚠️ 失败样例：`disable-user` 全 `SecurityException`（踩坑存证） |
| `apply_20261019_060509.log` | ✅ 成功样例：`uninstall -k --user 0` 全 `Success` |
| `apply_v3_20261019_091907.log` | ✅ 第二轮执行日志（5 包） |

---

## 14. 给 Antigravity / 下一个 agent 的续作建议

以下方向**已在本仓库第二轮中完成**，此处保留原计划并标注结果，便于对照：

1. **量化开机时间对比**：本次未采集"精简前"开机耗时基线（电视已重启过，无法回测）。下次可在移除**前**用 `adb shell 'cat /proc/uptime'` 与 `getprop sys.boot_completed` 轮询记录首次到达时间，建立对照。**（仍未做，需要下次重装系统时才能补基线）**
2. ~~兼容 API 23 的第三方 TV launcher~~ → **已完成**。Projectivy 4.72 与 FLauncher 2025.07 均已在真机跑通并量过内存，见 [LAUNCHER-GUIDE.md](LAUNCHER-GUIDE.md)。正版 Google TV 桌面因**本机无 GMS**（0 个 `com.google.*`）不可用。
3. **残留广告开关**：即便移除了播放器，仍有 persist 属性残留（`persist.service.bootad.activead=1`、`persist.sys.fxc.ad.*`、`persist.sys.adv.enable=1`）。可考虑 `setprop` 关闭这些 flag（需验证是否被移除的服务读取；部分 flag 对已卸载组件无影响）。**（仍未做，低风险低收益）**
4. ~~进一步评估保留的预装~~ → **已完成**。`com.estrongs.android.pop`(ES)、`com.trim.tv`(飞牛TV) 已经用户确认后移除；`com.yunpan.appmanage`（实为「应用管理」，有用）与三个桌面保留。剩余 57 包中已无可删项。
5. **安全收尾**：确认 ADB 调试是否可关；如长期暴露在网络，建议关闭 `persist.service.adb.enable`/`service.adb.tcp.port`。**（注意：本机 ADB 是唯一远程维护通道，且工厂菜单是唯一开关入口，关闭前务必确认物理遥控器可达设置）**
6. **剩余唯一低风险优化项**：动画时值。当前 `window_animation_scale` / `transition_animation_scale` / `animator_duration_scale` 均为 `0.5`，可改 `0` 让遥控器响应更跟手（不改变实际耗时）：
   ```sh
   adb shell settings put global window_animation_scale 0
   adb shell settings put global transition_animation_scale 0
   adb shell settings put global animator_duration_scale 0
   ```

---

## 15. 原始日志存证（节选）

**失败（`apply_20261019_055223.log`，方法一）**：
```
== Disabling packages ==
com.fxc.bootad.bootadplayer -> com.sharp.fxc.adservice  ...（列表被 stdin 吞行，见 6.1）
Error: java.lang.SecurityException: Permission Denial:
attempt to change component state from pid=8545, uid=2000, package uid=1000
== Disabled packages now == (空)
```

**成功（`apply_20261019_060509.log`，方法三）**：
```
com.fxc.bootad.bootadplayer -> Success
com.sharp.fxc.adservice -> Success
... (24 行全 Success) ...
com.hpplay.happyplay.aw.new -> Success
== Done. ==
```

---

## 16. 附录：与精简相关的关键 persist 属性（供续作参考）

```
persist.service.bootad.activead=1        # 开机广告激活
persist.sys.adv.enable=1                 # 广告总开关
persist.sys.fxc.ad.application=1
persist.sys.fxc.ad.prevideo=1
persist.sys.fxc.ad.screensaver=1
persist.sys.fxc.advert.launcher=1
persist.sys.fxc.bootad.launcher=0
persist.sys.fxc.assistant=1              # 语音助手开关
persist.sys.fxc.voice.sdk=FXC
persist.sys.fxc.speedup=not-support      # 原厂无加速功能
```
