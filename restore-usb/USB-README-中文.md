U 盘 FACTORY-RESTORE 目录说明（与 U 盘内 README.txt 同内容的中文版）
================================================================

【位置】2GB U 盘（卷名 NO NAME）→ FACTORY-RESTORE/
已安全推出（ejected），可直接拔下。

【为什么拷这批】
Antigravity 的 batch 2 把 mstar.factorymenu.ui（工厂菜单本体）卸载了，
而它是这台电视唯一的 ADB 开关入口。同时 com.fxc.factory.view、
com.ctv.factorytest、com.ctv.newfactorytest（备用工厂入口）和
ES、小白文件（两个文件管理器）也一起被删。
结果：没有工厂菜单 → 打不开 ADB → 无法远程还原，陷入死锁。

【U 盘里的文件（按安装顺序编号）】
  01-FIRST-mstar.factorymenu.ui.apk     工厂菜单本体（最关键，先装这个）
  02-com.fxc.factory.view.apk           备用工厂入口 FXCFactory
  03-com.ctv.factorytest.apk            工厂测试
  04-com.ctv.newfactorytest.apk         工厂测试（new）
  05-com.estrongs.android.pop.apk       ES 文件管理器（21MB）
  06-com.xiaobaifile.tv.apk             小白文件管理器（6MB）
  07~10                                 onetimeinitializer / newsetupwiz /
                                        svox pico TTS / musicfx（无害系统件）
  restore_batch2.sh                     恢复脚本（ADB 通了之后跑）
  apk_batch2_manifest.txt               包名↔APK 对应清单
  README.txt                            纯 ASCII 版安装步骤（电视端看这个）
  RECOVERY-batch2.md                    完整恢复指南（中文，Mac 上看）

【校验结果】
10 个 APK 全部 MD5 与 SSD 备份源逐一比对一致；已清除 macOS 生成的
._* 元数据文件（否则电视文件列表里会出现一堆乱码项）。
占用 44MB，U 盘剩余 1.8GB。

【电视端怎么装（不需要 ADB）】
1. U 盘插电视。
2. 打开电视自带的媒体浏览器（包名 com.cultraview.newfilemanager，
   **没被删**）。首页上一般在「媒体 / USB / 存储设备 / 文件管理」里。
3. 进 U 盘 → FACTORY-RESTORE → 01-FIRST-mstar.factorymenu.ui.apk
4. 选中安装，允许「未知来源」。
5. 再把 02、03、04 也装上（多一个工厂入口，多一条活路）。
6. 打开水滴轻桌面 → 电视信源 → 遥控器菜单 → 自定义程序列表，
   「工厂菜单」应该回来了。
7. 进工厂菜单把 USB/网络调试（ADB）打开。

【ADB 恢复之后（最干净的路径）】
  adb connect 192.168.1.194:5555
  sh restore_batch2.sh        # 脚本就在 U 盘 FACTORY-RESTORE 目录里

【最后手段】
恢复出厂。batch2 那 10 个包除了 ES/小白，都是 /system 应用，
恢复出厂会自动回来（代价：清空用户设置；ES/小白是 /data 应用不会自动回来）。

【重要教训】
mstar.factorymenu.ui 必须进「永不删」白名单——它是这台 ROM 唯一的 ADB 入口。
