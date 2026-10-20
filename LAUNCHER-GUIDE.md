# 桌面方案：三家实测对比（Projectivy / FLauncher / 水滴）

> 全部在 192.168.1.194 真机装好、跑通、量过内存。
> 采集时间：2026-10-19

## 0. 最重要的一句

**正版 Google TV 桌面（`com.google.android.apps.tv.launcherx`）在这台电视上装不了。**

不是 Android 版本的问题 —— 本机 57 个包里 **0 个 `com.google.*`**，这台夏普国内机型
**根本没有 GMS**。Google TV 桌面强依赖 GMS + Play 商店做内容聚合，没有就是黑屏。
所以"类似 Google TV"只能靠第三方桌面模拟。

好消息：`pm list features` 里有 `android.software.leanback`、`leanback_only`、`television`
—— **这是真正的 Android TV，不是手机系统套壳**，第三方 TV 桌面可以正常工作。

---

## 1. 三家实测数据（同一台机器，force-stop 后冷启动，静置 15~18 秒再测）

| 桌面 | 冷启动 PSS | vs 水滴 | 界面 | 状态 |
|---|---:|---:|---|---|
| **水滴轻桌面**（现用默认） | **41.7 MB** | 基准 | 国产极简，dock + 推广位 | 默认 |
| **FLauncher** 2025.07 | **74.6 MB** | +32.9 MB | 极简网格，分类两段式 | 已装，未设默认 |
| **Projectivy** 4.72 | **85.2 MB** | +43.5 MB | **最像 Google TV** | 已装，未设默认 |

> 我原本预判"FLauncher 是 Flutter 写的，肯定比 Projectivy 更吃内存"。
> **实测打脸：FLauncher 74.6MB 反而比 Projectivy 85.2MB 轻 10MB。**
> 原因大概是 Projectivy 的壁纸动态取色 + 卡片渲染开销更大。

---

## 2. 逐个体感

### 水滴轻桌面（现用，41.7MB）
- 优点：**内存最省**，和 1.9GB 的机器最匹配；中文语境；dock 直接放常用 App
- 缺点：dock 里有**推广位**（那个 "Emotn UI" 根本不是已安装的包，是广告位）
- 适合：只想安安稳稳看电视

### FLauncher 2025.07（74.6MB，GPL-3.0 开源）
- 优点：**完全开源、无广告、无推广位**；分类清晰（TV Applications / Non-TV Applications）；
  会把侧载的 App 单独归到 Non-TV，一眼看得出哪些是"手机应用"
- 缺点：界面素，没有壁纸/动态效果；功能少（不能隐藏应用、不能自定义分类）
- 适合：讨厌一切推广、只想要一个"干净的应用抽屉"

### Projectivy 4.72（85.2MB，闭源但 GitHub 发版）
- 优点：**最像 Google TV**（顶部栏 + 横排卡片 + 壁纸动态取色）；可隐藏应用、
  可自定义分类、可设"开机直进某个 App 或 HDMI 输入源"、遥控器按键可重映射
- 缺点：最吃内存；部分个性化功能要付费
- 适合：想要"客厅电视该有的样子"，或想让电视开机直接进某个源

---

## 3. 建议

- **要省内存 / 给播放器留余量** → 保持水滴（41.7MB），FLauncher 和 Projectivy 都留着不启用
- **要干净无推广** → 换 FLauncher（+33MB）
- **要 Google TV 观感 + 可定制** → 换 Projectivy（+44MB）

> 本次精简已把 MemFree 从 ~60MB 拉到 **328MB**，所以这三个都能跑得动，
> 不再是"内存不够不敢换"的局面。选择权回到"你想要什么界面"。

---

## 4. 切换方法（本机 `cmd` 不存在，`pm` 也不支持 `set-home-activity`）

这 ROM 的 `am`/`pm` 都是 API 23 老版本：
- ❌ `cmd package set-home-activity` —— `cmd` 不存在
- ❌ `android.settings.HOME_SETTINGS` —— 无此 Activity
- ✅ 装新桌面 / 清除默认后按 HOME 会弹选择器（本次已验证），选「始终」即固定

### 推荐：走 UI 选择器（最安全）
装好新桌面后，按 HOME 会弹出「将 XXX 设为主屏幕应用 / 仅此一次 / 始终 / 使用其他应用」。
遥控器选「始终」即可。**这条路径实测可用，且能随时再换回来**（重装/删除桌面会让选择器重现）。

### 备选：脚本强制切（候选只剩一个时自动生效）
```sh
# 切到 FLauncher（先退出水滴与 launcher3 的 HOME 竞争）
adb shell pm uninstall -k --user 0 com.tvshuaji.shuidiui
adb shell pm uninstall -k --user 0 com.sharp.launcher3
adb shell pm uninstall --user 0 com.spocky.projengmenu   # 若也不要 Projectivy
adb shell am start -a android.intent.action.MAIN -c android.intent.category.HOME
```

### 回滚
```sh
adb install -r backup/full_20261019_085111/apk/com.tvshuaji.shuidiui/base.apk
adb shell pm uninstall --user 0 me.efesser.flauncher
```

> ⚠️ 切换瞬间如果旧桌面都退出了而新桌面起不来，会暂时没有桌面，
> 但 **ADB 不会断**，用上面回滚命令就能救回来 —— 这条路径走过，是通的。

---

## 5. 安装包来源（APK 不入库，按链接自行下载）

三方桌面的 APK **不纳入本仓库**（体积 + 版权原因），需要时按下表下载：

| 桌面 | 版本 | 来源 |
|---|---|---|
| Projectivy | 4.72 | `github.com/spocky/miproja1/releases/tag/4.72` |
| FLauncher | 2025.07 | `github.com/osrosal/flauncher/releases/tag/v2025.07.001`（arm64-v8a） |

下载后安装：

```sh
adb install -r <launcher>.apk
```

> 国内网络直连 GitHub Releases 常失败。本次是通过 `ghfast.top` / `ghproxy.net` /
> `gh-proxy.com` / `mirror.ghproxy.com` 四个镜像依次回退下载成功的。
>
> FLauncher 必须选 **arm64-v8a** 版本（本机 ABI：`arm64-v8a`，`ro.product.cpu.abilist=arm64-v8a,armeabi-v7a,armeabi`）。

## 6. 截图证据

| 文件 | 内容 |
|---|---|
| `launchers/shots/proj5.jpg` | Projectivy 桌面（中文分类 + 横排卡片） |
| `launchers/shots/flauncher_1.jpg` | FLauncher 桌面（TV / Non-TV 两段式分类） |
| `launchers/shots/final_state.jpg` | 当前默认桌面（水滴轻桌面） |
| `launchers/shots/home_chooser.jpg` | 主屏幕选择器（「仅此一次 / 始终」） |
