# sing-box-v6

跨发行版的 sing-box IPv6/NAT 节点一键部署器。脚本以 POSIX `sh` 实现，默认创建 SS2022，并支持按参数启用 AnyTLS、VLESS-Reality、Hysteria2 和 TUIC。

## 快速安装

默认配置（端口 `65432`、SS2022、`2022-blake3-aes-256-gcm`）：

```sh
curl -fsSL https://raw.githubusercontent.com/kukumi1/sing-box-v6/main/install.sh | sh
```

自定义端口或协议：

```sh
curl -fsSL https://raw.githubusercontent.com/kukumi1/sing-box-v6/main/install.sh \
  | sh -s -- --port 22558 --protocols ss2022
```

支持协议：`ss2022`、`anytls`、`reality`、`hysteria2`、`tuic`。

## 架构

```text
install.sh
  └─ 下载并执行 scripts/vps-node.sh
       ├─ 系统/架构检测（Debian、Ubuntu、RHEL 系、Alpine）
       ├─ IPv6 检测（公网地址、ULA、默认路由、NAT 出站地址）
       ├─ sing-box 安装或复用（glibc / Alpine musl）
       ├─ 生成配置片段 / 证书 / 随机凭据
       ├─ 合并到 /etc/sing-box/conf.d/
       ├─ 配置 systemd 或 OpenRC 服务
       ├─ 检查 TCP/UDP 监听和配置语法
       └─ 输出 URI、JSON、地址、端口和回滚位置
```

脚本只管理自己的配置片段，不删除现有节点；重复执行同一端口时会更新该节点并保留 SS2022 密码。变更前会在 `/etc/sing-box/backups/` 创建时间戳备份。

## 参数

```text
--port PORT             起始端口，默认 65432
--protocols LIST        逗号分隔协议，默认 ss2022
--sni HOST              TLS/Reality SNI，默认 developer.apple.com
```

多个协议会从起始端口连续分配端口；需要 UDP 的协议会创建 UDP 监听。脚本不会添加禁止 UDP 的规则。服务商安全组或 NAT 面板规则需要用户自行放行 TCP/UDP。

## NAT 与 IPv6

- 优先绑定 `::`，由系统同时提供 IPv6 入站及双栈行为。
- `fd00::/8`、`fc00::/7`、`fe80::/10` 不会被当作公网节点地址。
- 只有出站公网 IPv6 时，脚本会显示候选地址，但只有外部端口映射成功后才可连接。
- NAT 机器应在面板映射相同的 TCP 和 UDP 端口，再进行外部验证。

## 文件布局

```text
install.sh                         公网短入口
scripts/vps-node.sh                主安装器
scripts/README.md                  参数、运维和故障排查
/etc/sing-box/config.json          基础配置（保留用户内容）
/etc/sing-box/conf.d/              脚本管理的节点片段
/etc/sing-box/certs/               自签名 TLS 证书（如需要）
/etc/sing-box/backups/             自动备份
```

## 验证与回滚

安装后检查：

```sh
sing-box check -D /var/lib/sing-box -c /etc/sing-box/config.json -C /etc/sing-box/conf.d
ss -lntup
rc-service sing-box-vps-node status  # Alpine
systemctl status sing-box            # systemd
```

回滚时停止服务，删除对应的 `vps-node-*.json` 片段，并从 `backups/` 恢复基础配置后重启服务。不要删除其他节点片段。

## 安全说明

- 不要把 SSH 密码、私钥、证书私钥或节点密码提交到仓库。
- 公网仓库中的脚本不会包含任何 VPS 凭据。
- 自签名证书仅适合测试；生产环境应使用可信域名和证书。
- GitHub PAT 只授予目标仓库的 Contents Read/Write 权限，并在使用后撤销或轮换。
