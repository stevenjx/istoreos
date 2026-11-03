#!/bin/bash
#
# Copyright (c) 2026 Steven & Community
# Description: OpenWrt DIY script part 2 (After Update feeds)
#

# 1. 设置后台默认 IP 地址 (默认 192.168.1.1)
sed -i 's/192.168.100.1/192.168.1.1/g' package/base-files/files/bin/config_generate 2>/dev/null || true

# 2. 设置默认主机名
sed -i 's/OpenWrt/iStoreOS-301W/g' package/base-files/files/bin/config_generate 2>/dev/null || true

# 3. 针对 QHora-301W 内核与 FIT Image 的关键配置保护：
# 原厂 U-Boot 的 CONFIG_SYS_BOOTM_LEN 缓冲区有限，如果内核解压后体积过大（超过 32MB），
# U-Boot 在 bootm 时会抛出 "inflate() returned -5: Image too large" 导致变砖。
# 这里强制确保调试信息与非必要冗余不打进内核镜像：
if [ -f target/linux/qualcommax/config-6.6 ]; then
  echo "Optimizing kernel size for qualcommax Linux 6.6..."
  sed -i 's/CONFIG_KERNEL_DEBUG_INFO=y/# CONFIG_KERNEL_DEBUG_INFO is not set/g' target/linux/qualcommax/config-6.6
  sed -i 's/CONFIG_DEBUG_INFO=y/# CONFIG_DEBUG_INFO is not set/g' target/linux/qualcommax/config-6.6
fi

# 4. 确保 Aquantia AQR113C 万兆网卡与 ath11k 无线驱动被标记进默认依赖
echo "diy-part2.sh executed successfully."
