# Sharp 60SU470A — 续作清单（Debloat 之后还能做什么）

> 依据：`backup/20261019_054606/dumpsys_package.txt` 快照 + 当前实测（2026-10-19 06:40 PDT）。
> 本文档面向 Antigravity / 下一个 agent。

---

## 0. 当前实测状态

- **电视**：在线（`ping` 1.7ms，ARP MAC `b8:3d:4e:8a:fb:ac`），但 **ADB 5555 已关闭**（`Connection refused`，端口 5037/5555/5556/5557 全 closed）→ 任何设备侧改动前必须先重开 ADB。
- **仓库**：`origin/main` = `e515114`，无新提交；工作区无未提交改动 → **Antigravity 未推送任何改动**（若它在你本地另做了修改，需单独合并）。
- **包数**：上次移除 24 包后为 59；因 ADB 关闭，本次**无法在线复核**，下次连上后先用 `adb shell pm list packages | wc -l` 确认仍为 59。

---

## 1. 重开 ADB（继续操作的前提）

电视端：`设置 → 系统/关于 → 开发者选项 → 打开「USB 调试 / ADB 调试」`
（部分 Sharp 路径为 `设置 → 系统 → 高级 → 开发者选项`）

```sh
adb connect 192.168.1.194:5555
adb devices        # 电视弹「允许 USB 调试?」→ 勾「一律允许」并确认
adb shell "pm list packages" | wc -l   # 期望 59
```

---

## 2. 还能继续精简（均有 BOOT_COMPLETED 开机自启证据）

> 方法同已验证方案：`pm uninstall -k --user 0 <pkg>`；**改动前先备份 APK**（`sh rebackup_apks.sh` 只会备份清单内 24 个，新增包需手动 `pm path` + `adb pull`）。

### Tier A — 第三方/预装（上次你选择保留，收益最直接）
| 包 | 说明 | 建议 |
|---|---|---|
| `com.estrongs.android.pop` | ES 文件浏览器；开机自启；历史广告/隐私争议 | **不用就移除（收益最高）** |
| `com.xiaobaifile.tv` | 小白文件管理器；开机自启 | 用不到可移除 |
| `com.olimsoft.android.oplayer.pro` | OPlayer；开机自启 | 若用电视自带播放器可移除 |

### Tier B — 工厂/测试/厂商服务（可移，但谨慎）
`com.ctv.factorytest`、`com.ctv.newfactorytest`、`com.fxc.factory.view`、`com.foxconn.fxcsprcservice`、`com.kehdev.kehdevmanger`
- 说明：均为开机自启的工厂/诊断/厂商服务。消费场景一般用不到，但**可能挂钩面板/背光/校准等隐藏功能**，建议逐项移除并观察，出问题用还原脚本回来。

### Tier C — 非自启但占空间/可能带广告
`com.trim.tv`、`com.tvshuaji.shuidiui`（水滴）、`com.sharp.fxc.newsetupwiz`（开机向导，首次设置完成后可移）

### 绝不碰（安全边界，保持不变）
`com.oversea.aslauncher`、`com.sharp.launcher3`、`com.mstar.*`、`com.fxc.settings`、`com.android.systemui`、`com.android.bluetooth*`、`com.ctv.autopair`、`com.android.inputmethod.pinyin`（输入法）、`com.android.providers.*`、`com.sharp.adapter`

---

## 3. 非精简类优化（不改包，风险低）

| 项 | 命令/做法 | 效果 | 备注 |
|---|---|---|---|
| **动画归零** | `settings put global window_animation_scale 0`；`transition_animation_scale 0`；`animator_duration_scale 0` | 界面切换瞬开，**体感明显变快** | 零风险，可随时改回 1.0 |
| **清缓存** | `pm trim-caches 2000M` | 释放 /data 缓存 | 零风险 |
| **开机视频** | `persist.sys.bootvideoon=1` 会播开机视频；改 0 可跳过 | 缩短"到 UI"时间 | persist 属性在 user 版 `setprop` 可能被拒，需 root 或找设置项 |
| **量化开机时间** | 断电→上电，轮询 `sys.boot_completed=1` 计时 | 建立基线 | 本次已无精简前基线，只能作为后续对照 |
| **换轻量 launcher** | 选 `minSdk ≤ 23` 的 TV launcher | 观感/速度提升最大 | **风险最高**：需保留 `com.sharp.launcher3` 兜底；Android 6 无 `cmd role`，要用默认应用/Intent 优先级方式设主页 |

---

## 4. 建议执行顺序

1. 重开 ADB，复核包数仍为 59。
2. **Tier A 三项**（若你确实不用文件管理器/OPlayer）→ 收益最直接。
3. **动画归零 + trim-caches**（零风险，立竿见影）。
4. Tier B/C 视需要逐项做，每项后观察一次。
5. 有余力再评估 launcher 替换（先备份、先验证兜底桌面可启动）。

---

## 5. 还原

- 已移除的 24 包：`sh restore_debloat.sh`。
- **新增移除的包**（Tier A/B/C）：`restore_debloat.sh` 不覆盖，需先把它们的 APK 备份进 `backup/apk/` 并追加到 `backup/apk_manifest.txt`，再执行还原；系统应用另有 `/system` 原厂 APK 兜底（恢复出厂可全量回来）。
