# 经验教训总汇（两轮实战沉淀）

> 本文件是本仓库最有价值的部分。它不讲"我做了什么"，只讲 **下次谁能少走弯路**。
> 每一条都有对应的采信证据（命令输出、日志、截图），不是推测。
>
> 适用设备：Sharp 60SU470A，Android 6.0 / API 23 / MStar 648 / Foxconn(FXC) 定制 ROM。
> 已装包从 ~85 精简到 57，MemFree 从 ~60MB 提升到 **328MB**，**全程未恢复出厂**。

---

## 一、卸载与还原机制（本 ROM 的特殊性）

### L1. `pm disable-user` 和 `pm hide` 在这台机器上根本用不了

两个方法都会抛 `SecurityException`，根因是 ADB shell（uid 2000）缺少两个系统级权限：

```
java.lang.SecurityException: Neither user 2000 nor current process has
  android.permission.CHANGE_COMPONENT_ENABLED_STATE.   ← pm disable-user 需要
```

```
java.lang.SecurityException: Neither user 2000 nor current process has
  android.permission.MANAGE_USERS.                     ← pm hide 需要
```

**结论**：这个 ROM 的 shell 只拿到 `DELETE_PACKAGES`，所以**唯一可行的手段是 `pm uninstall -k --user 0`**。
网上大量教程默认 `pm disable-user` 可用，在本机不成立 —— 直接照抄会卡在第一步。

---

### L2. `adb install` 报 `Success` 但包不出现（假成功）

```
$ adb install -r foo.apk
Success                     ← 骗你的
$ adb shell pm list packages | grep foo
(空)
```

`dumpsys package` 里能看到 `User 0: installed=false` 的状态没有被清除。

**正解**：把 APK push 到设备，用 `pm` 显式指定 user：

```sh
adb push foo.apk /data/local/tmp/foo.apk
adb shell "pm install -r --user 0 /data/local/tmp/foo.apk"
```

**这条是还原流程的命门**。如果只用 `adb install`，你会以为还原成功了，实际桌面上什么都没有。

---

### L3. 系统应用"装回去了但点不开"——APK 里根本没有 dex

这是本次最贵的一课，也是"以为只能恢复出厂"的唯一原因。

**现象**：U 盘装上工厂菜单 APK，图标回来了，点进去秒退 / 无反应。

**根因**：这类 `/system` 应用的 APK 是**没有 `classes.dex` 的空壳**，代码在配套的 oat 文件里：

```sh
$ unzip -l MTvFactory_2.0.apk | grep -c '\.dex'
0                                        # ← 一个 dex 都没有
$ ls /system/app/MTvFactory_2.0/oat/arm64/
MTvFactory_2.0.odex    (2.2 MB)          # ← 代码在这里
```

装到 `/data` 后，ART 找不到原 dex：

```
ClassNotFoundException: No original dex files found
```

**正确修法**（不是 `pm install`，而是**反向操作**）：

```sh
adb shell pm uninstall <pkg>        # 注意：不带 --user 0
```

不带 `--user` 的 uninstall 会删掉 `/data` 里的升级副本，系统自动退回 `/system` 原厂版，
`UPDATED_SYSTEM_APP` 标志消失，就能用 odex 正常启动。**不需要恢复出厂。**

用这一招当场修好了 4 个工厂入口：`mstar.factorymenu.ui`、`com.fxc.factory.view`、
`com.ctv.factorytest`、`com.ctv.newfactorytest`。

**判定口诀**：`unzip -l X.apk | grep '\.dex'` 为空 + 存在 `oat/arm64/*.odex` → 这类包**永远不要试图用 pm install 修**。

---

### L4. `-k` 保留数据会持续遮蔽 /system 原厂版

`pm uninstall -k` 的 `-k` 会保留 `/data` 数据与升级副本，导致系统继续认为"这是 UPDATED_SYSTEM_APP"。
对 `/system` 应用来说，这恰恰是 L3 那个 bug 的成因。

**对 `/system` 应用，宁可不用 `-k`**；只有 `/data` 应用（用户数据会丢的那种）才需要 `-k` 保护数据。

---

## 二、包身份判定（删包前的生死线）

### L5. PSS = 0 **绝不等于**没用

`com.trim.tv` 在 `dumpsys meminfo` 里 PSS 长期为 0，从未启动，名字带 `trim`、
内部有 `tencent.rmonitor` 埋点、还有 `transcode` 字样 —— 按所有"预装臃肿视频 App"的特征，
体检报告把它判定为可删。

**打开一看**：

```
com.trim.tv/.modules.server.scanDevice.ScanDeviceActivity
→ 界面标题：飞牛TV / 选择影视服务器
→ 已配置并在线：DellNAS  192.168.1.80:8005
```

这是用户**正在用的 NAS 播放器**。差点把主力工具当垃圾删掉。

（后来用户明确说可以删，才删的 —— 但那是**用户决策**，不是我的推断。）

> **规则**：PSS=0 只能证明"它现在没在跑"，不能证明"它没有价值"。
> 判定必须靠 `am start` + 截图，或查它的配置数据（NAS 地址、账号、书签、登录态）。

---

### L6. 包名会骗人，必须开箱验证

| 包名 | 名字暗示 | 实际身份 |
|---|---|---|
| `com.trim.tv` | 腾讯系预装视频 | **飞牛TV**（NAS 播放器） |
| `com.yunpan.appmanage` | 云盘推广包 | **「应用管理」**（应用管理 / 文件管理 / 蓝奏云盘 / 网盘直下 / ADB 状态） |

`com.yunpan.appmanage` 名字最像要删的那类，实际是这台没有 Play 商店的电视上**很实用的工具**，已保留。

---

### L7. "删不掉又没见过的应用" —— 先怀疑它是推广位

水滴桌面 dock 里有个 **"Emotn UI"** 图标，应用管理里也有 Emotn 磁贴。翻遍系统：

```sh
$ adb shell pm list packages | grep -i emotn
(空)
```

**它根本不是已安装的包**，是国产桌面/商店内置的**广告位**，点了才去下载。
以后遇到"这个应用在哪都找不到，但桌面上有"，不要浪费时间找包名 —— 它是推广位。

---

## 三、依赖关系（删一个崩一片）

### L8. `com.sharp.fxc.shortcut` 是「设置」的硬依赖

删了它之后，设置一按就崩：

```
java.lang.NullPointerException
  at com.fxc.settings.home.MainBasePage.getHomePageInfo(MainBasePage.java:288)
```

它提供设置首页要查的 ContentProvider，缺了就 `Cursor.getCount()` on null → NPE → 整个设置进程崩。

**名字像"快捷方式 / 臃肿组件"，实际是必留项**。已加入白名单强制保护。

> 教训：**进程崩在 A，根因常常在 B**。看 NPE 栈的**第一行调用点**，去找它依赖的数据源，
> 而不是去修那个崩掉的 App。

---

### L9. 三个桌面全在 `/data`，是本机唯一不可再生资产

```sh
$ adb shell pm path com.oversea.aslauncher
package:/data/app/com.oversea.aslauncher-1/base.apk     ← /data，不是 /system
```

`com.oversea.aslauncher`、`com.sharp.launcher3`、`com.sharp.home.resource` **都不在 `/system`**。
一旦删掉或恢复出厂清空 `/data`，就再也装不回来（无法从 `/system` 兜底，也没有线上来源）。

**任何大动作（恢复出厂、批量卸载）之前，第一件事是备份这三个 APK。**

---

### L10. `mstar.factorymenu.ui` 是唯一的 ADB 开关入口

一旦删掉，**再也没有任何办法从系统内打开 ADB**，只能走硬件 recovery。
本仓库已把它写进 `safety_whitelist.txt` 做机器级拦截。

这是唯一一个"删了就等于把门锁死把钥匙扔掉"的包。

---

## 四、ADB 与网络诊断（别被工具骗）

### L11. `nc -z` 报 OPEN 不可信

```
$ nc -z 192.168.1.194 5555 && echo OPEN
OPEN                          ← 但 adb 根本连不上
```

TCP 三次握手的 SYN-ACK 是**内核**回的，只要端口在 listen 队列里就会回，跟 adbd 进程是死是活无关。

**唯一可信的判活方法**：发真实的 ADB 握手包 `A_CNXN`，看有没有回包。

```python
# 发 A_CNXN，60 秒内零回包 = adbd 卡死
sock.send(b'CNXN\x00\x00\x00\x01\x00\x10\x00\x00' + b'\x07\x00\x00\x00' + payload)
```

**结论**：端口半开（TCP 能连、握手零回包、不死不关）= **adbd 进程卡死**。

---

### L12. ADB 设置本来就是持久的，丢 ADB 不要反复进工厂菜单

```sh
$ adb shell getprop persist.adb.tcp.port
5555
$ adb shell getprop persist.service.adb.enable
1
$ adb shell getprop persist.sv.debug.adb_enable
1
```

三个属性都在，说明**配置没丢**。丢 ADB 从来不是配置问题，而是 adbd 卡死 →
**重启电视（断电重开）即可恢复**，不需要反复进工厂菜单折腾。

---

### L13. 双网卡同网段会骗你

Mac 上 `en0` 是 `192.168.1.232`、`en1` 是 `192.168.1.154`，同网段双出口。
排查连不通时要**显式绑源地址**，否则你以为在测 A 路径，实际走了 B。

---

### L14. 抓"ADB 短暂活着的窗口"用哨兵轮询

adbd 卡死时偶尔会自己缓过来几十秒，人工重试抓不到。写个每 5 秒轮询的哨兵脚本，
一抓到就立刻执行抢救动作（拉 APK / 备份桌面），比手动靠谱得多。

本仓库的 `watch_adb_and_grab.sh` 就是这个思路 —— 它在 08:45 抓到了窗口，
成功抢救出 3 个桌面 APK，这是后来能安全操作的前提。

---

## 五、桌面更换（这台机器的限制）

### L15. 正版 Google TV 桌面**不可能**装上

```sh
$ adb shell pm list packages | grep -c '^package:com.google'
0
```

**57 个包里 0 个 `com.google.*`** —— 这台夏普国内机型根本没有 GMS。
Google TV 桌面（`com.google.android.apps.tv.launcherx`）强依赖 GMS + Play 商店做内容聚合，
没有 GMS 就是黑屏或闪退。

好消息：`pm list features` 里有 `android.software.leanback`、`leanback_only`、`television`，
**这是真正的 Android TV，不是手机系统套壳**，第三方 TV 桌面可以正常工作。

---

### L16. 实测推翻了"Flutter 一定更重"的预判

| 桌面 | 冷启动 PSS | 说明 |
|---|---:|---|
| 水滴轻桌面（默认） | **41.7 MB** | 最省内存 |
| FLauncher（Flutter） | **74.6 MB** | 比预判轻 |
| Projectivy | **85.2 MB** | 最像 Google TV，最吃内存 |

我原本判断"FLauncher 是 Flutter 写的，肯定比 Projectivy 吃内存"，**实测反而轻 10MB**。
原因大概是 Projectivy 的壁纸动态取色 + 卡片渲染开销更大。

> **规则**：内存占用只能实测，不能从技术栈推断。
> 测法必须统一：`am force-stop` → 冷启动 → **静置 15~18 秒** → 读 PSS（否则读到的是启动峰值）。

---

### L17. 这 ROM 没有任何命令行方式设默认桌面

```sh
$ adb shell cmd package set-home-activity ...
/system/bin/sh: cmd: not found          ← cmd 工具不存在（API 23 太老）

$ adb shell am start -a android.settings.HOME_SETTINGS
Error: Activity not found               ← 没有这个设置页

$ adb shell pm | grep home
(空)                                     ← pm 不支持 set-home-activity
```

三条路全断。**只剩两条可行**：

1. **UI 选择器**：装新桌面 / 清掉默认后按 HOME，弹「仅此一次 / 始终」，遥控器选「始终」。
2. **让 HOME 候选只剩一个**：`pm uninstall` 掉其他所有声明了 HOME 的包，系统别无选择。

---

### L18. 定位遥控器按钮用 UI 树，不要盲按方向键

```sh
adb shell uiautomator dump /sdcard/ui.xml
adb pull /sdcard/ui.xml
# 解析 text="..." bounds="[x1,y1][x2,y2]" → 取中心点
adb shell input tap <cx> <cy>
```

盲按方向键在弹窗上极易错位（按到"仅此一次"就白折腾）。`uiautomator dump` + `input tap`
是可靠路径，本次两次定位桌面选择器都是这么做的。

---

## 六、方法论（可迁移到任何设备）

### L19. 白名单要用机器守卫，不靠人记

`safety_whitelist.txt` 是正则列表，`apply_debloat_v2/v3.sh` 在卸载前逐包匹配，
命中就拒绝执行。脚本还会在**默认干跑**（不带 `--apply` 只打印计划），确认无误才动手。

把"不能删的东西"变成**代码约束**，而不是文档里的一行提醒 —— 因为下一个 agent 不一定读完文档。

### L20. 每一步都要留下可回滚的物证

- 卸载前：备份 APK + 校验大小 + 写 manifest
- 执行后：验证 4 项硬验收（Home 能起、工厂菜单能开、ADB 在、包数符合预期）
- 全部动作：留日志（`apply_v3_*.log`）

本次之所以"删了 29 个包、崩了设置、丢了工厂菜单，最后还能全救回来"，靠的就是这套物证链。

### L21. 文档要写 **reasoning**，不只是结论

"不要删 `com.sharp.fxc.shortcut`" 是一句会被忽略的结论。
"删了它 → 设置首页 `MainBasePage.getHomePageInfo:288` 查 ContentProvider → `Cursor` 为 null → NPE → 设置崩溃"
是可以被复用的推理链。下次遇到类似的崩溃，能顺着同一条路找回去。

### L22. 判断"某个改动是否安全"，要按"配置可被独立修改"推演

不能拿当前实况代替推演。例如"蓝牙没配对设备所以能删" —— 错，
遥控器如果是蓝牙的，删了直接废掉输入设备，而当前"没配对"只说明你没配过。

---

## 七、这把能到哪（能力边界）

1. **1.9GB 内存 + Mali-T72x** 是物理天花板。本轮腾出的 ~250MB 已接近这台机器的极限，
   再往上只能换硬件。
2. 剩余 57 个包里，能删的已经删完。再往下都是要么有系统职责、要么是用户在用的东西。
3. 唯一还有边际收益的低风险项：**动画时值**（当前三项均为 0.5，可改 0，纯观感更跟手，
   不改变实际耗时）。

---

## 八、如果只能记三条

1. **删任何包之前，先 `am start` 打开看一眼。**（L5/L6/L7）
2. **`/system` 应用装不回来时，`pm uninstall`（不带 `--user`）比 `pm install` 有效。**（L3）
3. **丢 ADB 先重启电视，别怀疑配置。**（L12）
