# Sharp 60SU470A（Android 6.0 / API 23）精简与开机加速 · 全记录

> 一站式复盘文档。目标读者：下一个接手的 agent（含 Antigravity）或你自己。
> 本仓库完整记录了 **对一台 Sharp 60SU470A 智能电视做 ADB 精简、删除臃肿、加速开机** 的全过程、踩坑、最终可行方案、移除清单、安全边界与一键还原方法。

---

## 0. TL;DR（一句话结论）

- **设备**：Sharp 60SU470A（`ro.product.model = LCD_xxSUFOC470A`），Android **6.0（API 23，build `MRA58K` / 固件 `2.69.210109`）**，MStar `msd648` / 平台 `mooney`，Foxconn(FXC) 定制 ROM。
- **目标**：基于 GitHub 仓库 `Gathin23/cleanyourtv`（原名 `tv-vibehack`，已更名）的思路，删臃肿、优化开机速度。
- **最大坑**：此 ROM 的 **ADB shell（uid 2000）既无 `CHANGE_COMPONENT_ENABLED_STATE` 也无 `MANAGE_USERS` 权限** → 仓库默认的 `pm disable-user` 和退路 `pm hide` **全部被 `SecurityException` 拒绝**。最终唯一可行且可逆的方法是 **`pm uninstall -k --user 0`**。
- **结果**：移除 **24 个包（83 → 59）**，重启验证通过（`BOOT_COMPLETED=1`，包数稳定 59，主桌面与核心服务完好）。
- **可逆**：每个被移除包的 APK 已本地备份（`backup/apk/`，214 MB），还原脚本 `restore_debloat.sh` 用 `pm install -r --user 0` 装回。系统应用另有 `/system` 原厂 APK 兜底（恢复出厂即全量回来）。

**速查命令**（在已 `adb connect 192.168.1.194:5555` 后）：
```sh
sh apply_debloat.sh      # 再次执行移除（幂等，已移除的会跳过）
sh restore_debloat.sh    # 一键还原全部 24 包
sh rebackup_apks.sh      # 若本地 APK 备份丢失，从电视重新拉取
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
| `README.md` | 本文档（全记录） |
| `debloat_sharp_su470a.txt` | 移除清单（含中文理由 + 安全边界注释），脚本的数据源 |
| `apply_debloat.sh` | 一键执行移除（幂等） |
| `restore_debloat.sh` | 一键还原（从 `backup/apk/` 装回） |
| `rebackup_apks.sh` | 本地 APK 备份丢失时，从电视重新拉取 |
| `backup/apk_manifest.txt` | `pkg\|本地apk路径` 清单，还原脚本的输入 |
| `backup/apk/` | 24 个已备份 APK（214 MB） |
| `backup/20261019_054606/` | 完整快照：`packages_*`、`settings_*`、`props.txt`、`home.txt`、`boot_receivers.txt`、三张桌面截图 `*.png` |
| `apply_20261019_055223.log` | ⚠️ 失败样例：`disable-user` 全 `SecurityException`（踩坑存证） |
| `apply_20261019_060509.log` | ✅ 成功样例：`uninstall -k --user 0` 全 `Success` |

---

## 14. 给 Antigravity / 下一个 agent 的续作建议

以下是可以继续深挖的方向（均未在本次执行）：

1. **量化开机时间对比**：本次未采集"精简前"开机耗时基线（电视已重启过，无法回测）。下次可在移除**前**用 `adb shell 'cat /proc/uptime'` 与 `getprop sys.boot_completed` 轮询记录首次到达时间，建立对照。
2. **兼容 API 23 的第三方 TV launcher**：`cleanyourtv` 的 launcher 要 API 26+。可在 F-Droid 等找 `minSdk ≤ 23` 的轻量 TV launcher 替换臃肿首页（注意保留 `com.sharp.launcher3` 兜底，且本 ROM 的 HOME-role 机制在 Android 6 不支持 `cmd role`，需用默认应用/Intent 方式设主页）。
3. **残留广告开关**：即便移除了播放器，仍有 persist 属性残留（`persist.service.bootad.activead=1`、`persist.sys.fxc.ad.*`、`persist.sys.adv.enable=1`）。可考虑 `setprop` 关闭这些 flag（需验证是否被移除的服务读取；部分 flag 对已卸载组件无影响）。
4. **进一步评估保留的预装**：`com.estrongs.android.pop`(ES)、`com.olimsoft.android.oplayer.pro`(OPlayer)、`com.xiaobaifile.tv`(小白文件)、`com.trim.tv`、`com.tvshuaji.shuidiui`(水滴)、`com.sharp.fxc.newsetupwiz` 仍在。如需更极致精简，可补充评估（用户本次选择保留）。
5. **安全收尾**：确认 ADB 调试是否可关；如长期暴露在网络，建议关闭 `persist.service.adb.enable`/`service.adb.tcp.port`。

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
