# QHora-301W NSS 硬件卸载验证指南

适用于本仓库 `qhora-301w-24.10` 分支（Linux 6.6.141 + qosmio NSS 12.5 栈）。
目标：确认固件运行时 NSS 驱动、firmware、ECM 与 WiFi offload 是否**真正加载并工作**，而不只是"包被编译进去"。

---

## 1. 最快判断：一条命令看总体状态

路由器上执行（本仓库新增的 LuCI 后端同时暴露了同一接口）：

```sh
ubus call luci.nss status
```

返回字段中重点看：

| 字段 | 期望值 | 含义 |
|---|---|---|
| `firmware_loaded` | `true` | `qca_nss_drv` 已加载且 debugfs 就绪 |
| `debugfs_ready` | `true` | `/sys/kernel/debug/qca-nss-drv/stats` 存在 |
| `ecm_ready` | `true` | ECM 连接管理引擎已注册 |
| `wifi_offload` | `0`（默认）/`1` | ath11k WiFi 卸载运行时开关 |
| `modules` | 各模块 `true` | 对应内核模块已加载 |
| `cpu_load` | 有非 0 值 | NSS firmware 正在处理数据包 |

若 `firmware_loaded=false` 或 `cpu_load` 全空，说明 NSS 数据通道并未真正运行（见第 4 节排查）。

---

## 2. 分层验证（从内核到数据流）

### 2.1 内核模块是否加载

```sh
cat /proc/modules | grep -E 'qca_nss|qca_ssdk|nss_ifb|ath11k'
```

应至少看到：

```
qca_nss_ecm
qca_nss_drv
qca_nss_dp
qca_ssdk
ath11k
```

按配置还应看到 `qca_nss_bridge_mgr`、`qca_nss_vlan_mgr`、`qca_nss_crypto`、`qca_nss_cfi_cryptoapi`、`qca_nss_macsec`、`nss_ifb` 以及 pppoe/l2tp/pptp/gre/vxlan/qdisc/mcs 等可选模块。

> 注意：`ath11k` 存在只说明 WiFi 驱动加载，不代表 WiFi offload 生效（见 2.4）。

### 2.2 NSS firmware 是否运行

```sh
ls /sys/kernel/debug/qca-nss-drv/stats/
cat /sys/kernel/debug/qca-nss-drv/stats/cpu_load_ubi/*     # 各 NSS 核心 ubi 负载
cat /sys/kernel/debug/qca-nss-drv/project/version          # firmware 版本（若节点存在）
```

判定要点：

- `stats/` 目录存在 → nss-drv 初始化成功，firmware 已加载。
- 制造一些流量（例如 LAN↔WAN 打流或 `iperf3`），再观察 `cpu_load_ubi/*` 出现非 0 值 → 数据包确实走了 NSS 硬件路径。
- 若目录不存在：检查 firmware 文件是否随固件打包（NSS firmware 11.4 Release 6，闭源 blob），以及 dts 中 NSS 节点是否生效。

### 2.3 ECM 连接管理引擎

```sh
ls /sys/kernel/debug/ecm/ecm_state/
cat /sys/kernel/debug/ecm/ecm_state/state_dev_major
cat /sys/kernel/debug/ecm/ecm_state/ecm_state              # 当前加速的连接条目
```

- `state_dev_major` 存在 → ECM 字符设备注册成功。
- 建立一条 TCP/UDP 流后，`ecm_state` 中出现对应条目 → 连接被 ECM 接管加速。
- 若为空，说明流量未被分类到加速路径（检查 bridge/vlan manager、SFE/ECM 规则）。

### 2.4 WiFi offload（默认关闭，需手动开启才生效）

```sh
cat /sys/module/ath11k/parameters/nss_offload               # 0=关（默认）, 1=开
cat /sys/module/ath11k/parameters/frame_mode                # 本固件固定为 2
```

- 本固件为规避 Apple WPA 握手问题与 AP_VLAN/mesh 限制，**默认关闭**（`nss_offload=0`）。
- 开启运行时开关并持久化：

  ```sh
  echo 1 > /sys/module/ath11k/parameters/nss_offload
  # 持久化由 LuCI「状态 → NSS 设置」完成，写入 /etc/modules.d/ath11k
  ```

- 部分 ath11k NSS 统计可在 station 调试节点查看（补丁引入的 `nss_stats` 会把 offload 收发计数同步回 mac80211 的 `sinfo`）。用 `iw dev <ifname> station dump` 观察每台 STA 的 rx/tx 计数在 offload 开启后仍正常增长，即说明 WiFi 卸载链路工作。

### 2.5 编译标识

```sh
cat /etc/ipq_release
```

确认 `IPQ_BRANCH` / `IPQ_COMMIT` 与 qosmio 24.10-nss 基线一致，避免刷入旧固件。

---

## 3. 用 LuCI 侧边栏直观查看

固件启动后，侧边栏：

- **状态 → NSS 加速**：模块加载、firmware、ECM、WiFi offload、NSS 核心负载、固件版本，5 秒自动刷新。
- **状态 → NSS 设置**：一键切换 WiFi offload（自动写入 `/etc/modules.d/ath11k` 持久化）。

两者数据均来自上面的 ubus 接口 `luci.nss`，与命令行检查完全等价。

---

## 4. 常见故障排查

| 现象 | 可能原因 | 处理 |
|---|---|---|
| `qca_nss_drv` 未加载 | firmware blob 缺失或 dts NSS 节点未生效 | 确认 `ipq8072-301w.dts` 包含 `ipq8074-nss.dtsi`；确认 NSS firmware 文件已打包 |
| debugfs `stats` 不存在 | debugfs 未挂载 / nss-drv 初始化失败 | `mount -t debugfs none /sys/kernel/debug`；看 `dmesg \| grep -i nss` |
| 模块加载了但 `cpu_load_ubi` 全 0 | 无流量经过 NSS 路径，或 bridge/vlan mgr 未接管 | 打流后复测；确认 `qca_nss_bridge_mgr`/`vlan_mgr` 已加载；检查 ECM 状态 |
| `ecm_state` 为空 | 流量未被 ECM 分类 | 确认 `kmod-qca-nss-ecm` 已加载；检查 netfilter/ECM 规则 |
| WiFi offload 开启后断流/握手失败 | 已知 Apple WPA / AP_VLAN 限制 | 关闭 offload（`echo 0`），这是本固件默认关闭的原因 |
| `nss_offload` 参数节点不存在 | ath11k 编译时未启用 NSS 支持 | 确认 `CONFIG_ATH11K_NSS_SUPPORT=y` 且 `package/kernel/mac80211` 使用了含 nss 补丁的版本 |

---

## 5. 判定"NSS 真正工作"的最小充分条件

同时满足以下三点即可认为 NSS 硬件卸载已正确加载并运行：

1. `/proc/modules` 中存在 `qca_nss_drv`、`qca_nss_dp`、`qca_ssdk`、`qca_nss_ecm`；
2. `/sys/kernel/debug/qca-nss-drv/stats/` 存在，且打流时 `cpu_load_ubi/*` 有非 0 值；
3. `/sys/kernel/debug/ecm/ecm_state/ecm_state` 中出现加速连接条目。

WiFi offload 为可选增强，默认关闭不影响上述三项判定。
