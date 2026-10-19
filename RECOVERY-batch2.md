# 恢复指南：Antigravity Batch 2 误删工厂菜单（Sharp 60SU470A）

## 根因（已确认）

Antigravity 在 `/Volumes/SSD/workspace/WorkSpace/sharp-60su470a-debloat` 执行了 **batch 2**，
用 `pm uninstall -k --user 0` 卸载了 **10 个包**，其中包含：

| 包 | 作用 | 影响 |
|---|---|---|
| **`mstar.factorymenu.ui`** | **工厂菜单本体**（`DesignMenuActivity`） | 自定义列表里的"工厂菜单"消失；这也是开 ADB 的入口 |
| `com.fxc.factory.view` | FXCFactory（备份工厂入口） | 备用工厂入口也没了 |
| `com.ctv.factorytest` | 工厂测试 | 工厂测试入口消失 |
| `com.ctv.newfactorytest` | 工厂测试 | 同上 |
| `com.estrongs.android.pop` | ES 文件浏览器 | 失去一个可装 APK 的文件管理器 |
| `com.xiaobaifile.tv` | 小白文件管理器 | 又失去一个文件管理器 |
| `com.android.onetimeinitializer` | 一次性初始化 | 无害 |
| `com.sharp.fxc.newsetupwiz` | 开机向导 | 无害（首次设置后本就可移） |
| `com.svox.pico` | TTS 语音引擎 | 文字转语音失效 |
| `com.android.musicfx` | 音效 | 音效设置失效 |

> 所以之前"进入自定义菜单找不到工厂菜单"不是 stopped 状态，而是**包被卸载了**。
> 好消息：这 10 个包的 APK 都备份在
> `/Volumes/SSD/workspace/WorkSpace/sharp-60su470a-debloat/backup/apk_batch2/`，
> 且有 `restore_batch2.sh` 可整批还原。

## 当前障碍

- **ADB 5555 已关闭**（`Connection refused`）→ 无法远程还原。
- 工厂菜单与两个文件管理器都被删 → 现场也不好装东西。

## 恢复路线（按优先级）

### 路线 1：设置里开 ADB（最省事）
1. 电视 `设置 → 关于/系统信息` → 连点"版本号/构建号"7 次，开 **开发者选项**。
2. 进 `开发者选项`，找 **USB 调试 / 网络调试 / ADB** 开关，打开。
3. 回到 Mac，执行：
   ```sh
   adb connect 192.168.1.194:5555
   adb devices          # 电视弹窗点允许、勾一律允许
   ```
4. 整批还原（推荐，恢复到 batch2 之前）：
   ```sh
   cd "/Volumes/SSD/workspace/WorkSpace/sharp-60su470a-debloat"
   sh restore_batch2.sh
   ```
   或只还原工厂菜单：
   ```sh
   adb push "/Volumes/SSD/workspace/WorkSpace/sharp-60su470a-debloat/backup/apk_batch2/mstar.factorymenu.ui.apk" /data/local/tmp/fm.apk
   adb shell "pm install -r --user 0 /data/local/tmp/fm.apk"
   ```

> 注意：本 ROM 曾用工厂菜单开 ADB，开发者选项里**可能没有** ADB 开关；若没有，走路线 2。

### 路线 2：U 盘安装工厂菜单 APK（推荐兜底）
1. 把本目录 `restore-usb/` 里的 APK 拷到 U 盘（FAT32/exFAT）：
   - `mstar.factorymenu.ui.apk`（**关键，317KB**）
   - `com.fxc.factory.view.apk`
   - `com.ctv.factorytest.apk`、`com.ctv.newfactorytest.apk`
2. U 盘插电视 → 用 **媒体库**（`com.cultraview.newfilemanager`，未被删）浏览 U 盘 → 点 `mstar.factorymenu.ui.apk` 安装。
   - 若提示签名/系统应用装不上，换装 `com.fxc.factory.view.apk` 试。
3. 工厂菜单回到自定义列表后，进去打开 ADB。
4. 回 Mac 走路线 1 的第 3、4 步补齐其余包。

### 路线 3：恢复出厂设置（最后手段）
- `pm uninstall -k --user 0` **只删了 user 0，`/system` 里的原厂 APK 还在**，恢复出厂会把
  所有 /system 应用（含 `mstar.factorymenu.ui`、FXCFactory、工厂测试、newsetupwiz 等）全部装回。
- 代价：清空用户设置（Wi-Fi、账号、画面参数等）；ES/小白是 /data 应用，不会自动回来（需另装）。
- 恢复后再用 `restore_batch2.sh` 或按需补装即可。

## 不要做的事

- **别再执行 Antigravity 的 batch 2**（或任何会删 `mstar.factorymenu.ui` 的脚本）——工厂菜单是本机的 ADB 入口。
- 保存好 `/Volumes/SSD/workspace/WorkSpace/sharp-60su470a-debloat/backup/apk_batch2/`，这是唯一的现场还原源。
