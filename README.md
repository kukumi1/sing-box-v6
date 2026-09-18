# sing-box IPv6/NAT 节点一键部署

支持 Debian、Ubuntu、Rocky/Alma/CentOS、Alpine，自动检测 IPv6、安装 sing-box，并以幂等方式追加 SS2022、AnyTLS、Reality、Hysteria2 或 TUIC 节点。

## 快速开始

```sh
curl -fsSL https://raw.githubusercontent.com/kukumi1/sing-box-v6/main/scripts/vps-node.sh | sh -s -- --port 65432 --protocols ss2022
```

脚本默认开启 TCP/UDP 所需监听，不会禁止 UDP。详细参数见 [`scripts/README.md`](scripts/README.md)。

请勿把 SSH 密码、私钥、证书私钥或已生成节点凭据提交到仓库。