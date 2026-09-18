# VPS IPv6/NAT sing-box node installer

`vps-node.sh` is a POSIX `/bin/sh` installer for Debian/Ubuntu/RHEL-family and Alpine.
It adds a managed sing-box fragment without deleting existing node fragments.

## Usage

```sh
chmod +x vps-node.sh
sudo ./vps-node.sh --port 65432 --protocols ss2022
sudo ./vps-node.sh --port 65432 --protocols ss2022,anytls,reality,hysteria2,tuic
```

Options:

- `--port PORT`: first port (default `65432`); selected protocols use consecutive ports.
- `--protocols LIST`: comma-separated `ss2022,anytls,reality,hysteria2,tuic` (default `ss2022`).
- `--sni HOST`: TLS/Reality SNI (default `developer.apple.com`).

The script creates a timestamped backup, uses TCP and UDP listeners where the protocol requires them, and never installs a UDP-blocking rule. Provider-side filtering is reported separately. Alpine downloads the musl sing-box release; glibc Linux downloads the regular release.

The generated SS2022 URI follows SIP002: only `method:password` is Base64 encoded and IPv6 remains in `@[addr]:port` form.
