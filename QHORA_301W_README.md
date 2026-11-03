# QNAP QHora-301W - iStoreOS 24.10.4 适配与自动化编译指南

本项目为 QNAP QHora-301W 适配 iStoreOS 24.10.4（Linux 6.6 内核），提供专用的内核配置、防变砖策略与 GitHub Actions 云端自动编译工作流。

---

## 目录结构
- `.github/workflows/build-qhora-301w.yml`: GitHub Actions 自动编译工作流
- `qhora-301w.config`: QHora-301w 专用的 OpenWrt/iStoreOS 编译配置（精简内核驱动，防止 U-Boot 解压溢出变砖）
- `diy-part1.sh`: Feeds 更新前自定义脚本
- `diy-part2.sh`: Feeds 更新后自定义脚本（配置调整、内核参数优化、默认 IP 与主题设置）
- `flash-guide.md`: 刷机、分区切换与救砖指南
