# QNAP QHora-301W 刷机、内核避坑与救砖全指南

## 1. 为什么之前自行编译刷入后会“变砖”？（深度技术解析）

QHora-301W 采用高通 IPQ8072A 处理器、8MB SPI NOR Flash 和 4GB eMMC 存储，配合原厂 U-Boot 引导。自行编译固件刷入导致“变砖”（不断重启或卡死在 U-Boot）的核心原因如下：

### ① 内核解压溢出（U-Boot inflate 错误）—— 最致命的问题
- **报错现象**（串口可见）：
  ```text
  ## Loading kernel from FIT Image at 44000000 …
  Using 'config@hk01' configuration
  Trying 'kernel-1' kernel subimage
  ...
  Uncompressing Kernel Image … Error: inflate() returned -5
  Image too large: increase CONFIG_SYS_BOOTM_LEN
  Must RESET board to recover
  ```
- **技术原因**：
  原厂 U-Boot 固化了 `CONFIG_SYS_BOOTM_LEN`（内核解压最大内存上限，一般限制在 32MB 左右）。在 iStoreOS 24.10（基于 Linux 6.6）中，如果编译时开启了过多内置驱动、调试信息（`CONFIG_KERNEL_DEBUG_INFO`）或未剥离符号表，解压后的内核体积超过了原厂 U-Boot 的阈值，U-Boot 就会解压失败强制复位。

### ② U-Boot 分区启动失败计数看门狗
- 当启动失败连续达到 3 次，原厂 U-Boot 的看门狗会将当前分区的状态标记为损坏：
  `boot_0=bad`（或 `boot_1=bad`）
- 此时 U-Boot 会拒绝继续尝试从该分区引导，表现为“无法进入系统、网口不亮”。
- **解决方法**：需在 U-Boot 下执行 `setenv boot_0 good && setenv boot_1 good && saveenv` 恢复。

### ③ 镜像写入目标错误（未拆分写入 eMMC GPT 分区）
- QHora-301W 是双系统槽位设计：
  - **槽位 0**：`mmcblk0p1`（内核 FIT `0:HLOS`，16MB），`mmcblk0p4`（根文件系统 `rootfs`，512MB）
  - **槽位 1**：`mmcblk0p2`（内核 FIT `0:HLOS_1`，16MB），`mmcblk0p5`（根文件系统 `rootfs_1`，512MB）
- 若直接将包含 MTD 头部或非分区格式的完整固件 `dd` 到某单一分区，U-Boot 无法找到有效的 FIT 节点和 GPT 根文件系统。

---

## 2. 正确的刷机操作流程

### 第一步：获取固件文件
GitHub Actions 自动编译完成后，会在 Release 中提供：
1. `qhora_301w_kernel.bin`（已从 sysupgrade 中提取的内核）
2. `qhora_301w_rootfs.bin`（已从 sysupgrade 中提取的系统）
3. `*sysupgrade.bin`（用于后续在 OpenWrt 网页直接升级）

### 第二步：从原厂 QuRouter OS 刷入
1. 长按路由器背面 WPS 按键直至听到第二声“哔”（约 12 秒）开启 SSH。
2. 登录 SSH（端口为 22200，用户名为 admin）：
   ```bash
   ssh -o HostKeyAlgorithms=ssh-rsa admin@192.168.100.1 -p 22200
   ```
3. 检查并确保当前运行在槽位 1：
   ```bash
   sudo fw_printenv -n current_entry
   # 若返回不是 1，则执行：
   sudo fw_setenv current_entry 1
   sudo reboot
   ```
4. 将 `qhora_301w_kernel.bin` 和 `qhora_301w_rootfs.bin` 上传到路由器的 `/tmp/` 目录。
5. 执行 `dd` 刷入槽位 0：
   ```bash
   sudo dd if=/tmp/qhora_301w_kernel.bin of=/dev/mmcblk0p1
   sudo dd if=/tmp/qhora_301w_rootfs.bin of=/dev/mmcblk0p4
   sudo fw_setenv current_entry 0
   sudo fw_setenv boot_0 good
   sudo reboot
   ```
6. 重启后电脑连接千兆网口，访问 `192.168.1.1` 即可进入 iStoreOS 界面。

---

## 3. 万兆网卡 Aquantia AQR113C 固件配置
进入系统后，检查万兆网卡是否正常：
```bash
dmesg | grep -i aquantia
```
如未加载固件，需将官方 10G 固件 `AQR-G4_*.cld` 写入 SPI NOR Flash 的 `mtd10` (`0:ethphyfw1`) 和 `mtd11` (`0:ethphyfw2`) 分区。

---

## 4. TTL 救砖方法（备用）
若设备已经卡死变砖：
1. 拆机连接 TTL（波特率 `115200, 8N1, 3.3V`，中间 3 针分别为 TX-GND-RX）。
2. 开机时不断按空格键打断引导，进入 U-Boot 命令行：
   ```text
   setenv boot_0 good
   setenv boot_1 good
   setenv current_entry 0
   saveenv
   ```
3. 若需重新加载内核，可通过 TFTP 载入 `openwrt-qualcommax-ipq807x-qnap_301w-initramfs-uImage.itb`：
   ```text
   setenv serverip 192.168.10.1
   setenv ipaddr 192.168.10.10
   tftpboot openwrt-qualcommax-ipq807x-qnap_301w-initramfs-uImage.itb
   bootm
   ```
   进入内存临时系统后，再通过网页后台或 `sysupgrade` 恢复。
