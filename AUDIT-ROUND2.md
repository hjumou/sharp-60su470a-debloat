# Sharp 60SU470A 二次精简报告（已执行）

> 采集与执行时间：2026-10-19
> 设备：192.168.1.194:5555（Android 6.0 / API 23 / MStar 648）
> 前提：本机 **无 root**（shell uid 2000），只能做"包级"操作，看不到 `/data` 内部明细。

---

## 一、结果速览

| 指标 | 之前 | 现在 |
|---|---|---|
| 已装包 | 62（含后装的 Projectivy、FLauncher） | **57** |
| 原厂包数 | ~85 | 57 |
| MemFree | 47 ~ 71 MB | **328 MB** |
| 最大单体浪费（ES） | 93.6 MB 常驻 | 已移除 |

**本次删除 5 个包**（全部有 APK 备份，可一键还原）：

| 包名 | 真实身份 | 收益 |
|---|---|---|
| `com.estrongs.android.pop` | ES 文件浏览器（含点心广告 SDK） | 释放 93.6 MB 内存 + 21.6 MB 存储 |
| `com.trim.tv` | **飞牛TV**（原连着 DellNAS 192.168.1.80:8005） | 36.3 MB 存储 |
| `com.foxconn.fxcsprcservice` | 富士康 SPRC 服务（开机拉起） | 8.3 MB 内存 |
| `com.android.musicfx` | 音效均衡器 | 48 KB |
| `com.svox.pico` | TTS 引擎 | 13 KB |

执行日志：`apply_v3_20261019_091907.log`

---

## 二、这次差点犯的错（必读）

**体检报告的第一版把 `com.trim.tv` 判定为"腾讯 SDK 预装视频 App，从未启动"，准备当臃肿删掉。**

实际打开后是：

```
com.trim.tv/.modules.server.scanDevice.ScanDeviceActivity
→ 界面：「飞牛TV / 选择影视服务器」
→ 已配置并在线：DellNAS  192.168.1.80:8005
```

它是你**正在用的 NAS 播放器**。名字里的 `trim`、`tencent.rmonitor`、`transcode` 全是误导线索。

同样被误判的还有 `com.yunpan.appmanage`：名字像"云盘推广包"，实际打开是
**「应用管理」**——带应用管理 / 文件管理 / 蓝奏云盘 / 网盘直下 / ADB 状态指示。这是
这台没有 Play 商店的电视上很实用的工具，**已保留**。

> 教训升级：**"从没启动过"不等于"没用"**。`dumpsys meminfo` 里 PSS=0 只能证明它没在跑，
> 不能证明它没有价值。判定一个包，必须**打开看一眼**（`am start` + 截图），
> 或者看它有没有配置数据（NAS 地址、账号、书签）。这一条已写进白名单文件的注释里。

**另一个发现**：水滴轻桌面 dock 里那个 "Emotn UI"、以及应用管理里的 "Emotn" 磁贴，
**并不是已安装的包**（`pm list packages` 里没有任何 emotn 相关包）。
它是国产桌面/商店内置的**推广位**，点了才会去下载。以后看到"某个应用删不掉也没见过"，
先确认它是不是推广位而不是真包。

---

## 三、为什么没有继续删（剩余候选的处置）

| 包名 | 体积 / 常驻 | 处置 | 理由 |
|---|---:|---|---|
| `com.yunpan.appmanage`（应用管理） | 13.5 MB / 60 MB | **保留** | 蓝奏云盘、网盘直下、文件管理、ADB 状态 —— 实际有用 |
| `com.oversea.aslauncher`（原厂桌面） | 15.4 MB / 20~74 MB | **保留** | 已确认不再是 HOME（HOME 声明数 = 0），但属"不可再生资产"，且重启后只占 20 MB |
| `com.sharp.launcher3` | 35.5 MB / 21 MB | **保留** | 唯一的 AOSP 兜底桌面，换桌面方案定下来之前不动 |
| `com.mstar.android.pppoe` | 小 / 常驻服务 | **不动** | APK 无 `classes.dex`（代码在 odex），删了 `pm install` 修不回来，只能整机恢复 |
| `com.android.bluetooth` 全家 | ~15 MB | **不动** | 无已配对设备，但遥控器若是蓝牙的，删了直接废 |
| `mstar.factorymenu.ui` | 13.5 MB | **不动** | 唯一的 ADB 开关入口 |

---

## 四、还能做的（非删包手段）

1. **动画时值**：当前 `window_animation_scale=0.5`、`transition=0.5`、`animator=0.5`。
   改 0 会让遥控器响应更跟手（不改实际耗时）。
2. **不要再按"名字像臃肿"删包**。剩下的 57 个里，能删的已经删完；
   再往下都是要么有系统职责、要么是你在用的东西。
3. 真正的天花板是 **1.9GB 内存 + Mali-T72x**。本次腾出的 250MB 左右已经是这台机器能拿到的极限，
   再往上只能靠换硬件。

---

## 五、还原方法

```sh
# 单个还原（以 ES 为例）
adb install -r backup/apk/com.estrongs.android.pop/base.apk
adb shell pm install -r --user 0 /data/local/tmp/base.apk   # 若上一条"假成功"

# 飞牛TV
adb install -r backup/apk/com.trim.tv/base.apk
```

APK 备份位置（脚本自动拉取，均在 `backup/apk/` 下）：
- `backup/apk/com.estrongs.android.pop/base.apk`（21 MB）
- `backup/apk/com.trim.tv/base.apk`（35 MB）
- `backup/apk/com.foxconn.fxcsprcservice/base.apk`（4 MB）
- `backup/apk/com.svox.pico/base.apk`（16 KB）
- `backup/apk/com.android.musicfx/base.apk`（48 KB）

---

## 六、证据截图

| 文件 | 内容 |
|---|---|
| `launchers/shots/id_trimtv.jpg` | **关键铁证**：`com.trim.tv` 打开后是「飞牛TV / 选择影视服务器」，且已配 DellNAS `192.168.1.80:8005` |
| `launchers/shots/id_appmanage.jpg` | `com.yunpan.appmanage` 打开后是「应用管理」（含蓝奏云盘、网盘直下、ADB 状态） |
| `launchers/shots/home_chooser.jpg` | 主屏幕选择器（本机唯一的换桌面入口） |
| `launchers/shots/final_state.jpg` | 精简完成后的水滴桌面 |

更多跨轮踩坑记录见 **[LESSONS.md](LESSONS.md)**。
