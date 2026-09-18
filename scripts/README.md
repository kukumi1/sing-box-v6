# 安装器运维说明

主入口：`../install.sh`。它将参数转发给 `vps-node.sh`。

## 参数与默认值

| 参数 | 默认值 | 说明 |
|---|---|---|
| `--port` | `65432` | 起始端口；多协议按端口递增 |
| `--protocols` | `ss2022` | `ss2022,anytls,reality,hysteria2,tuic` |
| `--sni` | `developer.apple.com` | TLS/Reality SNI |

## 运行流程

1. 检查 root、发行版、架构和依赖。
2. 选择系统原生 Alpine 包或 Linux 官方 sing-box 二进制。
3. 读取公网 IPv6；NAT 环境使用出站 IPv6 作为候选并提示外部验证。
4. 生成节点片段、随机凭据和测试证书。
5. 写入 `conf.d/vps-node-<起始端口>.json`。
6. 通过 systemd/OpenRC 重启并检查服务。
7. 输出 SIP002 SS URI 和配置文件位置。

## 协议与端口

SS2022 使用 TCP+UDP；AnyTLS 和 Reality 使用 TCP；Hysteria2 和 TUIC 使用 UDP/QUIC。脚本不会禁止 UDP。多协议部署时必须保证面板和云防火墙放行对应端口。

## 故障排查

```sh
sing-box check -D /var/lib/sing-box -c /etc/sing-box/config.json -C /etc/sing-box/conf.d
ss -lntup
journalctl -u sing-box -n 100 --no-pager
rc-service sing-box-vps-node status
```

如果监听正常但外部不可达，检查公网 IPv6、NAT 面板映射、云安全组和服务商 UDP 策略。`fdxx:`、`fcxx:`、`fe80:` 地址不可直接作为公网节点地址。
