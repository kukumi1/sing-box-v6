#!/bin/sh
set -eu
PORT=65432
PROTOCOLS=ss2022
SNI=developer.apple.com
CONFIG_DIR=${SING_BOX_CONFIG_DIR:-/etc/sing-box}
TAG_PREFIX=${SING_BOX_TAG_PREFIX:-vps-node}
YES=0
PORT_SET=0
PROTOCOLS_SET=0
SNI_SET=0
usage(){ cat <<EOF
Usage: vps-node.sh [--port PORT] [--protocols LIST] [--sni HOST] [--yes]
LIST: ss2022,anytls,reality,hysteria2,tuic
EOF
}
die(){ echo "ERROR: $*" >&2; exit 1; }
log(){ printf '[vps-node] %s\n' "$*"; }
contains(){ printf '%s' ",$1," | grep -q ",$2,"; }
while [ "$#" -gt 0 ]; do
 case "$1" in
  --port) PORT=${2:?missing port}; PORT_SET=1; shift 2;;
  --protocols) PROTOCOLS=${2:?missing protocols}; PROTOCOLS_SET=1; shift 2;;
  --sni) SNI=${2:?missing sni}; SNI_SET=1; shift 2;;
  --yes) YES=1; shift;;
  -h|--help) usage; exit 0;;
  *) die "unknown argument: $1";;
 esac
done
if [ "$YES" -eq 0 ] && [ -r /dev/tty ]; then
  printf "\n==== sing-box IPv6/NAT 节点安装器 ====\n" >/dev/tty
  if [ "$PORT_SET" -eq 0 ]; then printf "节点端口 [65432]: " >/dev/tty; IFS= read -r ans </dev/tty || ans=; [ -n "$ans" ] && PORT=$ans; fi
  if [ "$PROTOCOLS_SET" -eq 0 ]; then printf "协议 (1=ss2022, 2=anytls, 3=reality, 4=hysteria2, 5=tuic) [1]: " >/dev/tty; IFS= read -r ans </dev/tty || ans=; case "$ans" in 2) PROTOCOLS=anytls;; 3) PROTOCOLS=reality;; 4) PROTOCOLS=hysteria2;; 5) PROTOCOLS=tuic;; *) PROTOCOLS=ss2022;; esac; fi
  if [ "$SNI_SET" -eq 0 ]; then printf "SNI [developer.apple.com]: " >/dev/tty; IFS= read -r ans </dev/tty || ans=; [ -n "$ans" ] && SNI=$ans; fi
  printf "端口=%s  协议=%s  SNI=%s\n继续安装？[Y/n]: " "$PORT" "$PROTOCOLS" "$SNI" >/dev/tty
  IFS= read -r ans </dev/tty || ans=; case "$ans" in n|N) exit 0;; esac
fi
case "$PORT" in *[!0-9]*|'') die 'port must be numeric';; esac
[ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ] || die 'port out of range'
[ "$(id -u)" -eq 0 ] || die 'run as root'
has(){ command -v "$1" >/dev/null 2>&1; }
need(){ has "$1" || die "missing command: $1"; }
bootstrap(){
  if command -v apt-get >/dev/null 2>&1; then apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl ca-certificates openssl tar iproute2 coreutils >/dev/null;
  elif command -v apk >/dev/null 2>&1; then apk add --no-cache curl ca-certificates openssl tar iproute2 coreutils >/dev/null;
  elif command -v dnf >/dev/null 2>&1; then dnf install -y curl ca-certificates openssl tar iproute coreutils >/dev/null;
  elif command -v yum >/dev/null 2>&1; then yum install -y curl ca-certificates openssl tar iproute coreutils >/dev/null;
  fi
}
OS=unknown; [ -r /etc/os-release ] && . /etc/os-release && OS=${ID:-unknown}
case "$OS" in debian|ubuntu|rocky|almalinux|alma|centos|rhel|fedora|alpine) ;; *) die "unsupported OS: $OS";; esac
ARCH=$(uname -m)
case "$ARCH" in x86_64|amd64) SB_ARCH=amd64;; aarch64|arm64) SB_ARCH=arm64;; armv7l|armv7) SB_ARCH=armv7;; *) die "unsupported architecture: $ARCH";; esac
bootstrap
need ip; need openssl; need tar; need base64
install_sing_box(){
 has sing-box && sing-box version >/dev/null 2>&1 && return 0
 if [ "$OS" = alpine ]; then apk update >/dev/null && apk add --no-cache sing-box sing-box-openrc; return 0; fi
 has curl || die 'curl is required to install sing-box'
 ver=${SING_BOX_VERSION:-}
 [ -n "$ver" ] || ver=$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest | sed -n 's/.*"tag_name": "\([^"]*\)".*/\1/p' | head -n1)
 [ -n "$ver" ] || die 'set SING_BOX_VERSION when GitHub API is unavailable'
 v=${ver#v}; tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT INT TERM
 suffix=; [ "$OS" = alpine ] && suffix=-musl
 url="https://github.com/SagerNet/sing-box/releases/download/${ver}/sing-box-${v}-linux-${SB_ARCH}${suffix}.tar.gz"
 curl -fL "$url" -o "$tmp/sing-box.tgz"; tar -xzf "$tmp/sing-box.tgz" -C "$tmp"
 bin=$(find "$tmp" -type f -name sing-box | head -n1); [ -n "$bin" ] || die 'sing-box binary not found'
 install -m 0755 "$bin" /usr/local/bin/sing-box
}
global_v6(){ ip -6 -o addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | while read -r a; do case "$a" in fe80:*|fd*|fc*) ;; *) echo "$a"; return;; esac; done; }
PUBLIC_V6=$(global_v6 | head -n1 || true)
[ -n "$PUBLIC_V6" ] || has curl && PUBLIC_V6=$(curl -6 -fsS --max-time 8 https://api64.ipify.org 2>/dev/null || true)
install_sing_box
SB_BIN=$(command -v sing-box)
mkdir -p "$CONFIG_DIR/conf.d" "$CONFIG_DIR/certs" "$CONFIG_DIR/backups"
[ -f "$CONFIG_DIR/config.json" ] || printf '%s\n' '{"log":{"level":"info"},"outbounds":[{"type":"direct"}]}' > "$CONFIG_DIR/config.json"
STAMP=$(date -u +%Y%m%dT%H%M%SZ); cp -a "$CONFIG_DIR/config.json" "$CONFIG_DIR/backups/config.json.$STAMP"
rand_b64(){ openssl rand -base64 32 | tr -d '\n'; }
rand_hex(){ openssl rand -hex 16 | tr -d '\n'; }
uuid(){ cat /proc/sys/kernel/random/uuid; }
CERT="$CONFIG_DIR/certs/$TAG_PREFIX.crt"; KEY="$CONFIG_DIR/certs/$TAG_PREFIX.key"
if [ ! -s "$CERT" ] || [ ! -s "$KEY" ]; then openssl req -x509 -newkey rsa:2048 -nodes -days 825 -subj "/CN=$SNI" -keyout "$KEY" -out "$CERT" >/dev/null 2>&1; chmod 600 "$KEY"; chmod 644 "$CERT"; fi
port=$PORT; first=1; OUT="$CONFIG_DIR/conf.d/${TAG_PREFIX}-${PORT}.json"; OLD_SS_PW=; [ -f "$OUT" ] && OLD_SS_PW=$(sed -n "s/.*\"tag\":\"$TAG_PREFIX-ss2022\".*\"password\":\"\([^\"]*\)\".*/\1/p" "$OUT" | head -n1 || true); rm -f "$OUT"; printf '{"inbounds":[' > "$OUT"
add_json(){ [ "$first" -eq 1 ] || printf ',' >> "$OUT"; first=0; cat >> "$OUT"; }
if contains "$PROTOCOLS" ss2022; then
 ss_pw=${OLD_SS_PW:-$(rand_b64)}; add_json <<EOF
{"type":"shadowsocks","tag":"$TAG_PREFIX-ss2022","listen":"::","listen_port":$port,"method":"2022-blake3-aes-256-gcm","password":"$ss_pw"}
EOF
 SS_URI="ss://$(printf '%s' "2022-blake3-aes-256-gcm:$ss_pw" | base64 | tr -d '\n')@[$PUBLIC_V6]:$port#$TAG_PREFIX-ss2022"; port=$((port+1))
fi
if contains "$PROTOCOLS" anytls; then
 any_pw=$(rand_hex); add_json <<EOF
{"type":"anytls","tag":"$TAG_PREFIX-anytls","listen":"::","listen_port":$port,"users":[{"name":"default","password":"$any_pw"}],"tls":{"enabled":true,"certificate_path":"$CERT","key_path":"$KEY"}}
EOF
 port=$((port+1))
fi
if contains "$PROTOCOLS" reality; then
 keys=$($SB_BIN generate reality-keypair 2>/dev/null) || die 'Reality key generation failed'; private=$(printf '%s\n' "$keys" | sed -n 's/^PrivateKey: //p'); public=$(printf '%s\n' "$keys" | sed -n 's/^PublicKey: //p'); rid=$(openssl rand -hex 4); ruuid=$(uuid)
 add_json <<EOF
{"type":"vless","tag":"$TAG_PREFIX-reality","listen":"::","listen_port":$port,"users":[{"uuid":"$ruuid"}],"tls":{"enabled":true,"server_name":"$SNI","reality":{"enabled":true,"handshake":{"server":"$SNI","server_port":443},"private_key":"$private","short_id":["$rid"]}}}
EOF
 port=$((port+1))
fi
if contains "$PROTOCOLS" hysteria2; then
 hpw=$(rand_b64); add_json <<EOF
{"type":"hysteria2","tag":"$TAG_PREFIX-hysteria2","listen":"::","listen_port":$port,"users":[{"password":"$hpw"}],"tls":{"enabled":true,"certificate_path":"$CERT","key_path":"$KEY"}}
EOF
 port=$((port+1))
fi
if contains "$PROTOCOLS" tuic; then
 tuic_uuid=$(uuid); tuic_pw=$(rand_hex); add_json <<EOF
{"type":"tuic","tag":"$TAG_PREFIX-tuic","listen":"::","listen_port":$port,"users":[{"uuid":"$tuic_uuid","password":"$tuic_pw"}],"tls":{"enabled":true,"certificate_path":"$CERT","key_path":"$KEY"}}
EOF
 port=$((port+1))
fi
printf ']}' >> "$OUT"
if command -v systemctl >/dev/null 2>&1; then
 mkdir -p /etc/systemd/system/sing-box.service.d
 cat >/etc/systemd/system/sing-box.service.d/vps-node.conf <<EOF
[Service]
ExecStart=
ExecStart=$SB_BIN -D /var/lib/sing-box -c $CONFIG_DIR/config.json -C $CONFIG_DIR/conf.d run
EOF
 systemctl daemon-reload; $SB_BIN check -D /var/lib/sing-box -c "$CONFIG_DIR/config.json" -C "$CONFIG_DIR/conf.d"; systemctl enable sing-box >/dev/null 2>&1 || true; systemctl stop sing-box >/dev/null 2>&1 || true; for pid in $(pidof sing-box 2>/dev/null || true); do kill "$pid" >/dev/null 2>&1 || true; done; sleep 1; systemctl start sing-box
elif command -v rc-service >/dev/null 2>&1; then
 cat >/etc/init.d/sing-box-vps-node <<EOF
#!/sbin/openrc-run
command="$SB_BIN"
command_args="-D /var/lib/sing-box -c $CONFIG_DIR/config.json -C $CONFIG_DIR/conf.d run"
command_background=true
pidfile=/run/sing-box-vps-node.pid
EOF
 chmod +x /etc/init.d/sing-box-vps-node; rc-update add sing-box-vps-node default >/dev/null 2>&1 || true; rc-service sing-box-vps-node restart
else die 'no supported service manager found'; fi
if command -v ufw >/dev/null 2>&1; then p=$PORT; while [ "$p" -lt "$port" ]; do ufw allow "$p/tcp" >/dev/null 2>&1 || true; ufw allow "$p/udp" >/dev/null 2>&1 || true; p=$((p+1)); done
elif command -v firewall-cmd >/dev/null 2>&1; then p=$PORT; while [ "$p" -lt "$port" ]; do firewall-cmd --permanent --add-port="$p/tcp" >/dev/null 2>&1 || true; firewall-cmd --permanent --add-port="$p/udp" >/dev/null 2>&1 || true; p=$((p+1)); done; firewall-cmd --reload >/dev/null 2>&1 || true
else log 'no local firewall manager; UDP was not disabled; check provider rules'; fi
echo "NODE_CONFIG=$OUT"; echo "PUBLIC_IPV6=$PUBLIC_V6"; [ -n "${SS_URI:-}" ] && echo "SS2022_URI=$SS_URI"; echo "PORTS=$PORT-$((port-1))"; ss -lntup 2>/dev/null | grep -E "(:$PORT|:$((port-1)))" || true








