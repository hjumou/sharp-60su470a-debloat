# 工厂菜单 / 设置 / ADB 全部恢复 —— 完整诊断与修复记录

> 日期：2026-10-19
> 设备：Sharp 60SU470A（`LCD_xxSUFOC470A`），Android 6.0 / API 23，平台 mooney（MStar 648）
> 结果：**无需恢复出厂**。设置、工厂菜单、ADB 全部恢复正常。

---

## 一、最终结论（先看这个）

| 问题 | 真正根因 | 修复动作 |
|---|---|---|
| 工厂菜单"条目能看见、点了没反应" | 装到 `/data` 的 APK **里面没有 `classes.dex`**（该应用的代码在 `/system/app/MTvFactory_2.0/oat/arm64/MTvFactory_2.0.odex`）→ `ClassNotFoundException` | `pm uninstall mstar.factorymenu.ui` 让它**退回 /system 原厂版** |
| 「设置」按钮打不开 | `com.sharp.fxc.shortcut` 被当"臃肿"删了，而它是设置首页的 **ContentProvider 数据源** → `MainBasePage.getHomePageInfo()` 拿到 null Cursor → NPE | 用备份 APK `pm install -r --user 0` 装回 |
| ADB 时通时断 / `offline` / `refused` | ADB 配置**本来是持久的**（`persist.adb.tcp.port=5555`），但 **adbd 进程卡死**过 → 端口半开、不回包；进程死后端口彻底关闭 | 等 adbd 恢复或重启；配置无需重设 |

**一句话**：不是"身份不对"，也不是"缺依赖包"这种笼统说法——是 **无 dex 的预编译系统应用被装到了 /data**，加上 **一个隐性 Provider 依赖被删**。

---

## 二、诊断过程（可复现的推理链）

### 2.1 第一层：ADB 到底是什么状态

`adb devices` 长期显示 `192.168.1.194:5555  offline`，`adb connect` 要卡满 **10 秒**才报 `failed to connect`。

分层排除：

| 检查 | 结果 | 结论 |
|---|---|---|
| `ping` | 1.6–1.9 ms，0 丢包 | 电视在线 |
| `arp -n 192.168.1.194` | MAC `b8:3d:4e:8a:fb:ac`（与基线一致） | IP 没变，确实是这台 |
| 端口扫描 | 只开 `554`(RTSP) 和 `5555` | **不是**路由器 HomeProxy 拦截（代理会接受大量端口） |
| 手写 A_CNXN 握手包 | TCP 秒连，**60 秒零回包**；4 条并发同样无回包；发垃圾数据也不被 close | **adbd 进程卡死**（内核 backlog 在、无人 accept） |
| 两个网卡分别绑源地址重测（en0 `.232` / en1 `.154`） | 结果一致 | 排除路由/网卡因素 |

> 陷阱：`nc -z` 报 `OPEN` **会误导**——内核 backlog 会先回 SYN-ACK，即使进程已挂。

> 另一个陷阱：本机两个网卡在同一网段（en0 `192.168.1.232`、en1 `192.168.1.154`），
> `.186` 在 en1 上解析出的 MAC 也是电视 → 一度误判"有两个开 5555 的主机"。
> 排查多网卡同网段环境时要**指定源地址**复测。

### 2.2 第二层：ADB 为什么"一死就不回来"

```
[persist.adb.tcp.port]      : [5555]      ← persist.* 重启保留
[persist.service.adb.enable]: [1]
[persist.sv.debug.adb_enable]: [1]
[init.svc.adbd]             : [running]
```

配置**是持久的**，不需要每次手工开。之前反复丢 ADB，是**进程层面**的问题
（adbd 卡死 → 端口半开 → 进程退出 → 端口关闭），不是配置没保存。
**重启电视即可让 adbd 重新干净启动。**

### 2.3 第三层：工厂菜单为什么"看得见、打不开"

`am start` 之后前台立刻退回 `com.mstar.tv.tvplayer.ui/.RootActivity`，logcat 给出决定性证据：

```
java.lang.RuntimeException: Unable to instantiate activity
  ComponentInfo{mstar.factorymenu.ui/mstar.tvsetting.factory.ui.designmenu.DesignMenuActivity}:
  java.lang.ClassNotFoundException: Didn't find class
  "mstar.tvsetting.factory.ui.designmenu.DesignMenuActivity"
  on path: DexPathList[[zip file "/data/app/mstar.factorymenu.ui-1/base.apk"], ...]
Suppressed: java.io.IOException:
  No original dex files found for dex location /data/app/mstar.factorymenu.ui-1/base.apk
```

进一步验证：

```sh
adb pull /system/app/MTvFactory_2.0/MTvFactory_2.0.apk   # 317,011 bytes
unzip -l MTvFactory_2.0.apk | grep -E "\.dex"            # → 无任何 dex（共 81 个文件）
ls -lR /system/app/MTvFactory_2.0/oat
#   /system/app/MTvFactory_2.0/oat/arm64/MTvFactory_2.0.odex   2,265,856 bytes
```

**APK 里根本没有 `classes.dex`，代码全在 `/system` 的 odex 里。**
所以任何"把这个 APK 装到 /data"的做法（U 盘安装、`pm install`）都必然启动失败。

> 这也解释了一个反直觉现象：备份出来的 APK 与原厂 APK **字节完全一致**
> （都是 317,011 bytes），不是备份坏了，而是**它本来就没有 dex**。

### 2.4 第四层：「设置」为什么打不开（另一个独立 bug）

```
java.lang.RuntimeException: Unable to start activity ComponentInfo{com.fxc.settings/com.android.settings.Settings}:
  java.lang.NullPointerException: Attempt to invoke interface method
  'int android.database.Cursor.getCount()' on a null object reference
    at com.android.settings.base.MainBasePage.getHomePageInfo(MainBasePage.java:288)
    at com.android.settings.base.MainBasePage.initData(MainBasePage.java:264)
    at com.android.settings.Settings.initPage(Settings.java:154)
```

设置首页是**动态拼装**的，它去查某个 Provider 拿菜单数据，Provider 不在 → Cursor 为 null → 崩。

在快照里筛出"被删的 24 个包中声明了 ContentProvider 的"：

```
com.sharp.fxc.account        com.sharp.fxc.shortcut      com.sharp.fxc.upgrade
com.sharp.fxc.ai.voice       com.sharp.fxc.lottery       com.sharp.fxc.recordcollect
com.hpplay.happyplay.aw.new
```

逐个装回 + 试启，**第一个 `com.sharp.fxc.shortcut` 装回后设置立刻正常**。

---

## 三、修复步骤（实际执行的命令）

```sh
export ANDROID_SERIAL=192.168.1.194:5555

# ── 1. 先抢救唯一不可再生的资产：3 个桌面 APK（它们的 codePath 在 /data）──
for p in com.oversea.aslauncher com.sharp.launcher3 com.sharp.home.resource; do
  ap=$(adb shell "pm path $p" | sed 's/package://' | tr -d '\r')
  mkdir -p backup/apk/$p && adb pull "$ap" backup/apk/$p/
done

# ── 2. 修「设置」：装回它依赖的 Provider 包（用备份的 APK）──
adb push backup/apk/com.sharp.fxc.shortcut/*.apk /data/local/tmp/_r.apk
adb shell "pm install -r --user 0 /data/local/tmp/_r.apk"     # → Success

# ── 3. 修「工厂菜单」：把 /data 的坏副本卸掉，退回 /system 原厂版 ──
adb shell "pm uninstall mstar.factorymenu.ui"                 # → Success
# 验证：codePath 变成 /system/app/MTvFactory_2.0，flags 不再有 UPDATED_SYSTEM_APP
adb shell "dumpsys package mstar.factorymenu.ui" | grep -E "codePath=|flags=|User 0:"

# ── 4. 同样处理另外 3 个工厂入口 ──
for p in com.fxc.factory.view com.ctv.factorytest com.ctv.newfactorytest; do
  adb shell "pm uninstall $p"
done

# ── 5. 验证工厂菜单真的能打开 ──
adb shell "am start -n mstar.factorymenu.ui/mstar.tvsetting.factory.ui.designmenu.DesignMenuActivity"
adb shell "dumpsys activity activities" | grep mResumedActivity
#   期望：mResumedActivity: ... mstar.factorymenu.ui/...DesignMenuActivity
```

### 为什么 `pm uninstall` 能修好

`pm install` 对"已存在于 /system 的系统应用"会生成一个 `/data` 的**升级副本**
（`UPDATED_SYSTEM_APP`），运行时用的是 `/data` 那份 —— 没有 odex → 崩。

`pm uninstall <pkg>`（**不带** `--user`）对这类包的行为是**删除 /data 升级副本、退回 /system 原厂版**：

```
卸载前: codePath=/data/app/mstar.factorymenu.ui-1   flags=[SYSTEM ... UPDATED_SYSTEM_APP ...]
卸载后: codePath=/system/app/MTvFactory_2.0          flags=[SYSTEM HAS_CODE ...]
        User 0: installed=true  stopped=false        ← 仍然是"已安装、未停用"
```

退回后 ART 使用 `/system/app/X/oat/arm64/X.odex` → 正常启动。

---

## 四、修复后状态（实测）

```
包数：60（原 83，净减 23）
mstar.factorymenu.ui            1   ← /system，可正常打开
com.fxc.factory.view            1   ← /system
com.ctv.factorytest             1   ← /system
com.ctv.newfactorytest          1   ← /system
com.oversea.aslauncher          1   ← 桌面（APK 已本地备份）
com.sharp.launcher3             1   ← 兜底桌面（APK 已本地备份）
com.sharp.home.resource         1   ← 桌面资源（APK 已本地备份）
com.fxc.settings                1   ← 可正常打开
com.sharp.fxc.shortcut          1   ← 设置首页的 Provider 依赖
```

- 工厂菜单截图：`backup/factorymenu_ok.png`（主板 CV648H_D / 型号 LCD_60SU470A / 屏 RUNKT0246FVZA）
- 设置截图：`backup/settings_ok.png`
- 桌面 APK 抢抓记录：`backup/hotgrab_20261019_083159/`

---

## 五、教训（已写入 safety_whitelist.txt，机器强制拦截）

1. **无 dex 的系统应用不能"装回来"**。判断方法：
   `unzip -l X.apk | grep '\.dex'` 为空 + `/system/app/X/oat/` 里有 `.odex` → 就是这种包。
   恢复只能靠 `pm uninstall`（退回 /system），**永远不要试图 `pm install`**。

2. **`com.sharp.fxc.shortcut` 是「设置」的硬依赖**（Provider 数据源），
   名字看着像"快捷方式/臃肿"，实际删了设置就崩。已加入白名单。

3. **`mstar.factorymenu.ui` 是唯一 ADB 入口**，已加入白名单（最高优先级）。

4. **ADB 配置是持久的**（`persist.adb.tcp.port=5555`），丢了是 adbd 进程问题，**重启即可**，
   不需要反复进工厂菜单重开。

5. **`nc -z` 报 OPEN 不可信**：要判定 adbd 是否真活着，必须发真实 `A_CNXN` 包看有没有回包。

6. **多网卡同网段时**（en0 `.232` / en1 `.154`），排查要绑定源地址，否则 ARP/连接结果会互相污染。
