# 恢复出厂前后操作手册 — Sharp 60SU470A（Android 6.0 / API 23）

> 适用前提：batch 1（24 包）已执行，batch 2（10 包，含工厂菜单）由 Antigravity 执行，
> 导致"工厂菜单能看见但打不开、ADB 无法开启"。现决定恢复出厂。
>
> 本文档 = 出厂前的保险清单 + 出厂后的重建流程 + 验收标准 + 故障分支。
> 所有脚本在仓库根目录，全部可离线执行（只需 adb 与电视）。

---

## 0. 一句话结论

**恢复出厂是正确判断，但出厂有一个不可逆风险：这台电视的桌面装在 `/data`，出厂可能清掉。**
先把桌面 APK 抓到手里，再动恢复出厂。除此之外的一切（工厂菜单、文件管理器、设置、TV 核心）
都在 `/system`，出厂会自动回来。

---

## 1. 为什么"用 U 盘装回去打不开"——诊断

### 1.1 事实链（已从设备快照核实）

| 事实 | 证据 |
|---|---|
| 工厂菜单包本体在 **`/system/app/MTvFactory_2.0/MTvFactory_2.0.apk`** | `pm list packages -f` 快照 |
| 它原本是**系统身份**（`userId=1000`，platform 签名，声明系统级权限） | `dumpsys package` 快照 |
| 你用 U 盘 + 包安装器装的是**同一个 APK 文件** | 文件 MD5 一致 |
| 但安装后它落在 **`/data/app`**，成为普通三方应用 | 安装路径变化 |
| 现象：条目出现在扫描列表（说明 `MAIN` 已注册、APK 可解析），但点开无反应 | 你实测 |

### 1.2 结论：不是"缺依赖"，是"身份不对"

- **能进列表** = 清单扫描（`android.intent.action.MAIN`）读的是 APK 的 manifest，这部分没问题。
- **点开没反应** = Activity 真正启动时要过运行期校验：进程 uid 是不是 system、系统级权限有没有、
  `sharedUserId` 能不能绑上。这些 **写在 `/data` 的普通安装里拿不到**。
- 如果是"缺依赖"，典型表现会是 app 能起来、进去某个功能崩，或 `ActivityNotFoundException` 之类，
  而不是"点了完全没动静"。

> 两种解释的共同结论一样：**只有把 `/system` 原厂文件恢复原状才能根治**，
> 而非 root 无法写 `/system`，`pm install` 只能落 `/data` —— 所以恢复出厂是唯一出路。

### 1.3 顺带记一笔
batch 2 一起删掉的 `com.android.onetimeinitializer` / `com.sharp.fxc.newsetupwiz` /
`com.svox.pico` / `com.android.musicfx` **不是** DesignMenu 的运行依赖，
它们不是这次打不开的原因，但出厂后都会回来，不用额外处理。

---

## 2. 出厂前必做（顺序不能乱）

### 2.1 ★ 第一优先：把桌面 APK 抓到本地（唯一不可再生资产）

**为什么这是硬要求**（快照实证）：

```
Preferred Activities User 0:
    android.intent.action.MAIN:
        com.oversea.aslauncher/.ui.main.MainActivity      <- 当前桌面
          Selected from:
            com.sharp.launcher3/.TopActivity              <- 唯一兜底桌面
            com.oversea.aslauncher/.ui.main.MainActivity
```

这台电视的 HOME **只有这两个候选**，而两者都装在 `/data/app`：

```
package:/data/app/com.oversea.aslauncher-1/base.apk=com.oversea.aslauncher
package:/data/app/com.sharp.launcher3-2/base.apk=com.sharp.launcher3
package:/data/app/com.sharp.home.resource-2/base.apk=com.sharp.home.resource
```

如果出厂清空 `/data` 且不重装预置应用，电视会**没有任何桌面**（只剩 AOSP 的
`com.android.provision` 占位页，即"黑屏但有系统"）。此时**只有这 3 个 APK 能救**，
而它们目前本地一份都没有。

**三选一，按成功率排序：**

**方案 A（推荐，不需要 ADB）**：用 ES 导出
1. U 盘插电视 → 打开 **媒体库**（`com.cultraview.newfilemanager`，`/system` 应用，还在）
2. 进 `FACTORY-RESTORE` → 装 `05-com.estrongs.android.pop.apk`
3. 打开 ES → 左侧「应用」→ 长按/菜单 → **备份**（或"提取 APK"）→ 选
   `桌面`(aslauncher)、`launcher3`、`home.resource` → 目标目录选 **U 盘**
4. 确认 U 盘上出现 3 个 APK

**方案 B**：如果你还能把 ADB 打开（见 §4.3 四条路径），直接跑

```sh
cd /Users/johnnyhoo/WorkBuddy/2026-10-19-05-34-33
sh baseline_backup.sh
```

它会备份**所有 `/data` 应用**（桌面自然包含）+ 关键 `/system` 包，并且会在结尾
专门检查 `com.oversea.aslauncher` / `com.sharp.launcher3` 有没有抓到。

**方案 C**：U 盘里的 `应用管家V1.4.3.apk` 装上去，用它自带的「应用备份/导出」功能。

> **判断标准**：U 盘上必须有这 3 个文件，缺一个都不要恢复出厂。

### 2.2 记录这些信息（出厂后要重新填）

- [ ] WiFi 名称 + 密码（出厂后要重连）
- [ ] 图像模式 / 背光 / 声音设置（你调过的数值）
- [ ] 已登录的账号（如果有）
- [ ] 当前装过的第三方应用清单（`package:/data/app/` 那 29 个，截图留档）
- [ ] 遥控器配对方式（蓝牙遥控可能需要重新配对）

### 2.3 U 盘确认（插上电视前先核对）

| 文件 | 用途 | 状态 |
|---|---|---|
| `FACTORY-RESTORE/01-FIRST-mstar.factorymenu.ui.apk` | 工厂菜单（出厂后是 `/system` 自带，一般用不上，留着兜底） | ✅ 已拷 |
| `FACTORY-RESTORE/05-com.estrongs.android.pop.apk` | ES，出厂前用来**导出桌面**；出厂后用来装 APK | ✅ 已拷 |
| `FACTORY-RESTORE/06-com.xiaobaifile.tv.apk` | 小白文件（备用） | ✅ 已拷 |
| `轻桌面_1.0.21.apk` | 第三方桌面（万一官方桌面找不回来，用它顶上） | ✅ 原有 |
| `应用管家V1.4.3.apk` | 应用备份/安装 | ✅ 原有 |
| **导出得到的 aslauncher / launcher3 / home.resource APK** | 救命桌面 | ⬜ 待做（§2.1） |

### 2.4 确认恢复出厂入口

`设置 → 系统/关于 → 恢复出厂设置`（有的批次在 `设置 → 存储与重置`）。
**不要在工厂菜单里做 factory reset** —— 那是整机烧写级操作，风险完全不同。

---

## 3. 执行恢复出厂

1. **先断网**：拔网线 / 电视 WiFi 不连。目的：防止出厂瞬间 OTA 抢跑，先更新固件再装一堆东西。
2. 确认 U 盘已拔下（避免恢复过程被读写干扰）。
3. `设置 → 恢复出厂设置 → 确认`。
4. 过程约 5–15 分钟（会重启 1–2 次），**中途绝对不要断电**。

---

## 4. 首次开机（顺序很关键，别图快）

### Step 1 — 向导阶段：先跳过联网

首个开机向导（`com.android.wizard` / `com.sharp.fxc.newsetupwiz`）出现时：
语言选中文 → **网络这一步先跳过**（多数版本有「跳过」或按返回键）→ 直接进桌面。
> 目的：在联网前把 ADB 打开并做完基线备份，让 OTA 完全没机会插手。

### Step 2 — 确认桌面在不在（三种分支）

| 现象 | 判断 | 动作 |
|---|---|---|
| 出现 Sharp 桌面（网络连接/一键清理/电视信源/存储设备/桌面设置） | ✅ 正常，桌面已恢复 | 进 Step 3 |
| 黑屏 / 只有一个空白页 / 什么都不显示 | ⚠️ 桌面没恢复 | 见 §7.1 |
| 反复重启 | ❌ 更严重 | 见 §7.4 |

### Step 3 — 打开 ADB（四条路径，按成功率）

1. **红外工厂键（最快）**：依次试
   - `菜单` → `2` `5` `8` `0`
   - `信源/信号源` → `2` `5` `8` `0`
   - `菜单` → `1` `1` `4` `7`
2. 进工厂菜单后找：**`Other Options` / `选项` / `Factory` 下的 `USB Debug` / `ADB Switch` /
   `Debug Enable`** → 设为 `ON`
3. **备用工厂入口**：桌面「电视信源 → 遥控器菜单 → 自定义打开程序」里找
   `Factory Menu` / `FXCFactory` / `Factory Test`
4. **开发者选项**：`设置 → 关于 → 连点「版本号」7 次` → 返回 → 开发者选项 → USB 调试
   （本机部分批次无此开关，属正常）

> 出厂后 `mstar.factorymenu.ui` 是 `/system` 原厂件，**一定能打开**——这正是恢复出厂的意义。

### Step 4 — Mac 侧连上 + 立刻做基线备份

```sh
cd /Users/johnnyhoo/WorkBuddy/2026-10-19-05-34-33
adb connect 192.168.1.194:5555     # 电视上弹窗点「允许」并勾「一律允许」
adb devices                        # 必须显示 device，不是 unauthorized
sh baseline_backup.sh              # ★ 把桌面 APK 抢到手
```

结尾会打印：

```
★ 请确认桌面 APK 已在备份里：
-rw-r--r-- ... base.apk      <- com.oversea.aslauncher
-rw-r--r-- ... base.apk      <- com.sharp.launcher3
```

**看到这两行，才是"以后不会再被锁死"的状态。** 然后把整个
`backup/postreset_<时间戳>/` 复制到 U 盘/网盘。

### Step 5 — 这时才允许联网

联网后 **立刻禁 OTA**（batch 1 清单里已包含 `com.sharp.fxc.upgrade` 等 3 个包），
避免它在后台下固件、把你刚修好的状态又搅乱。

---

## 5. 重建精简（只做 batch 1，永久禁止 batch 2）

```sh
cd /Users/johnnyhoo/WorkBuddy/2026-10-19-05-34-33

# 5.1 干跑：只打印计划，不动手
sh apply_debloat_v2.sh

# 5.2 确认无误后执行（会先逐包校验本地 APK 备份，缺失就先拉）
sh apply_debloat_v2.sh --apply

# 5.3 验收（硬性四条）
sh verify_tv.sh 59

# 5.4 重启，再验一次（关键：验证移除是否持久化、桌面能否回来）
adb reboot
# 等 1~2 分钟电视起来后
sh verify_tv.sh 59
```

**batch 1 = 那 24 个包**（广告/遥测/推广/语音栈/OTA/投屏）。
**batch 2 的 10 个包永久禁止**，尤其是 `mstar.factorymenu.ui` —— 已写进
`safety_whitelist.txt`，脚本会在执行前拦截，不靠人记。

---

## 6. 硬性验收（四条，缺一不可）

| # | 检查项 | 判定 | 失败后果 |
|---|---|---|---|
| 1 | 重启后能正常回到桌面 | 画面与出厂前一致 | 用户用不了电视 |
| 2 | **工厂菜单能真正打开** | 焦点在 `factory`/`DesignMenu` | **下次再也开不了 ADB**（本次事故） |
| 3 | ADB 仍然可连 | `adb devices` = `device` | 失去远程维护能力 |
| 4 | 关键包齐全 + 包数 59 | 见 `verify_tv.sh` 输出 | 功能缺失 |

`sh verify_tv.sh 59` 会一次性跑完这四条，并自动回到桌面（不把你留在工厂菜单里）。

---

## 7. 故障分支

### 7.1 出厂后没有桌面（黑屏/空白）
1. 先试遥控器 `设置` 键、`信源` 键 —— 很多 MStar 机型能直接拉起设置/信源，绕过桌面。
2. 能进任何界面 → 用**媒体库**或**设置里的文件浏览**打开 U 盘，装
   `轻桌面_1.0.21.apk`（第三方桌面，即时可用）。
3. 再补装导出的 `aslauncher` / `launcher3` APK 恢复官方桌面。
4. 若所有按键都无反应 → 试 §4.3 的红外工厂键开 ADB，然后从 Mac 推装：
   ```sh
   adb install -r "/Volumes/U盘/桌面APK/aslauncher.apk"
   ```

### 7.2 工厂菜单打不开（又来了）
- 说明 `/system` 原件不完整或又被改过。**不要再用 pm install 修补**（会重复 §1 的坑）。
- 唯一可靠路径：恢复出厂（第二次）。这次出厂前务必已有桌面 APK 备份。

### 7.3 ADB 就是打不开
- 出厂后工厂菜单一定在（`/system` 原件）；先确认按键序列对不对（不同批次键值不同，逐个试）。
- 确认电视和 Mac 在同一网段（`ping 192.168.1.194`）。

### 7.4 恢复出厂后反复重启
- 固件层面的问题，本手册范围内无解。不要反复尝试；记录屏幕报错，考虑走官方售后/固件刷写。

---

## 8. 教训清单（本次 + Antigravity，共 8 条）

1. **"ADB 入口包"是最高保护级资产。** `mstar.factorymenu.ui` 是这台电视唯一的 ADB 开关，
   把它当噱头广告删掉，等于自己把钥匙锁在屋里。
2. **不要信"报告"，要看脚本和清单。** Antigravity 只留下了 `restore_batch2.sh` +
   `apk_batch2_manifest.txt`，没有任何落盘的 "Optimization Report"。判断它做了什么，
   只能靠这两个文件。
3. **`/data` 应用才是不可再生资源。** `/system` 的原厂 APK 永远在，恢复出厂就能回来；
   `/data` 的桌面、第三方应用清了就真没了。备份优先级应按这个排序。
4. **"装回去" ≠ "恢复"。** 系统身份（uid/签名/权限）不会因为装了同一个 APK 文件就回来。
5. **批量操作必须能一键回滚 + 必须分批。** 一次删 24 个还能回滚，一次删 34 个就把自己闭在门外。
6. **每批之后必须重启 + 验收**，尤其是"工厂菜单还能不能打开"这一条。这次的坑就是验收项漏了它。
7. **白名单要写进脚本，不靠人记。** 人在赶进度时会删掉"看起来没用"的东西，脚本不会。
8. **文档必须和脚本一致。** 旧清单头部写的是 `pm disable-user`，脚本实际跑的是
   `pm uninstall -k --user 0` —— 这种不一致会误导下一个 agent（这次的 Antigravity 就是下一个 agent）。

---

## 9. 文件清单

| 文件 | 作用 | 何时用 |
|---|---|---|
| `POST-RESET-PLAYBOOK.md` | 本文档 | 出厂前后全程 |
| `baseline_backup.sh` | 全量基线备份（**含桌面 APK**） | ADB 一通就跑 |
| `apply_debloat_v2.sh` | 精简执行器（默认干跑 + 白名单守卫） | 出厂后重建时 |
| `verify_tv.sh` | 硬性验收四条 | 每次改完/重启后 |
| `safety_whitelist.txt` | 永不删除白名单（机器强制） | 被 v2 脚本自动读取 |
| `debloat_sharp_su470a.txt` | batch 1 的 24 包清单 | v2 脚本的数据源 |
| `restore_debloat.sh` | 还原 24 包 | 想恢复任何一项时 |
| `restore-usb/` | 工厂类 APK（U 盘用） | 极端情况 |

---

## 附录 A — batch 1（24 包）在 `/system` 与 `/data` 的分布

**`/data`（18 个，出厂会清空，靠本地 `backup/apk/` 还原）**
```
com.fxc.bootad.bootadplayer      com.sharp.fxc.account
com.hpplay.happyplay.aw.new      com.sharp.fxc.adservice
com.iflytek.xiri                 com.sharp.fxc.ai.voice
com.sharp.app.userguide          com.sharp.fxc.app.advert
com.sharp.fxc.assistant          com.sharp.fxc.classification
com.sharp.fxc.fxcscreensaver     com.sharp.fxc.fxctopactivity
com.sharp.fxc.lottery            com.sharp.fxc.mor.tv
com.sharp.fxc.recordcollect      com.sharp.fxc.shortcut
com.sharp.fxc.upgrade            com.sharp.fxc.voicecontrol.action.voiceaction
```

**`/system`（6 个，出厂自动回来，无需备份）**
```
com.android.mcast                com.example.upgrad
com.iflytek.xiri2.sharpvoice     com.iflytek.xiri2.system
com.kehiwn.wzy.foxconnautoota    com.sharp.fxc.tlkgmic.service
```

## 附录 B — 恢复出厂会恢复什么 / 丢什么

| 类别 | 举例 | 出厂后 |
|---|---|---|
| `/system` 全部 | 工厂菜单、FXCFactory、工厂测试×2、媒体库、设置、SystemUI、TV 核心、包安装器 | ✅ 自动恢复 |
| batch 2 的 10 包 | 工厂菜单、ES、小白、onetimeinitializer、newsetupwiz… | ✅ 自动恢复（原本都是 `/system`，除 ES/小白） |
| `/data` 预置应用 | **aslauncher（桌面）**、launcher3、home.resource、OPlayer、trim.tv、轻桌面、ES、小白 | ⚠️ 取决于 ROM 是否恢复预置；**当作会丢来处理** |
| 用户设置 | WiFi、图像/声音参数、账号、安装的第三方应用 | ❌ 全部清空 |
| batch 1 的 18 个 `/data` 包 | 广告、遥测、语音栈、OTA、投屏 | ✅ 全部回来（这是你要的"出厂状态"） |
