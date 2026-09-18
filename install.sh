#!/bin/sh
# Short public entrypoint for the sing-box IPv6/NAT installer.
set -eu
url='https://raw.githubusercontent.com/kukumi1/sing-box-v6/main/scripts/vps-node.sh'
curl -fsSL "$url" | sh -s -- "$@"
