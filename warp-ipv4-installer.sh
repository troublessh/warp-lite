#!/bin/sh
set -eu

CONF_DIR=/etc/wireguard
CONF_FILE=$CONF_DIR/warp.conf
DNS_FILE=/etc/resolv.conf
LOCAL_START=/etc/local.d/warp.start
LOCAL_STOP=/etc/local.d/warp.stop
WRAPPER=/usr/local/bin/warp-ipv4
STATE_DIR=/var/lib/warp-ipv4
STATE_FILE=$STATE_DIR/active-endpoint

ENDPOINTS="2606:4700:d0::a29f:c001 2606:4700:d0::a29f:c005"
PORTS="500 1701 4500 2408"

PRIVATE_KEY='hTk06uwwXhZx3RVqtug3MQ0RSodzdM/U5z/M5NIbh4c='
WARP_V6='2606:4700:110:8921:bf06:c4d7:40b7:8afd'
PEER_KEY='bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo='

log() {
  printf '%s\n' "$*" >&2
}

need_root() {
  [ "$(id -u)" = 0 ] || {
    echo "run as root" >&2
    exit 1
  }
}

install_deps() {
  apk add --no-cache wireguard-tools iptables ip6tables openresolv curl >/dev/null
}

write_dns() {
  cat > "$DNS_FILE" <<'EOF'
nameserver 2606:4700:4700::1111
nameserver 2606:4700:4700::1001
nameserver 2001:4860:4860::8888
EOF
}

write_conf() {
  endpoint="$1"
  port="$2"
  mkdir -p "$CONF_DIR"
  cat > "$CONF_FILE" <<EOF
[Interface]
PrivateKey = ${PRIVATE_KEY}
Address = 172.16.0.2/32
Address = ${WARP_V6}/128
MTU = 1280

[Peer]
PublicKey = ${PEER_KEY}
AllowedIPs = 0.0.0.0/0
Endpoint = [${endpoint}]:${port}
PersistentKeepalive = 25
EOF
  chmod 600 "$CONF_FILE"
}

save_state() {
  endpoint="$1"
  port="$2"
  mkdir -p "$STATE_DIR"
  printf '%s %s\n' "$endpoint" "$port" > "$STATE_FILE"
}

read_state() {
  [ -s "$STATE_FILE" ] || return 1
  cat "$STATE_FILE"
}

try_up() {
  endpoint="$1"
  port="$2"
  log "==> trying [${endpoint}]:${port}"
  write_conf "$endpoint" "$port"
  wg-quick down warp >/dev/null 2>&1 || true
  if ! wg-quick up warp >/tmp/warp-ipv4-up.log 2>&1; then
    log "wg-quick up failed"
    cat /tmp/warp-ipv4-up.log >&2 || true
    return 1
  fi
  sleep 6
  if wg show warp | grep -q 'latest handshake'; then
    save_state "$endpoint" "$port"
    return 0
  fi
  return 1
}

probe_all() {
  for endpoint in $ENDPOINTS; do
    for port in $PORTS; do
      if try_up "$endpoint" "$port"; then
        printf '%s %s\n' "$endpoint" "$port"
        return 0
      fi
    done
  done
  return 1
}

status() {
  echo '=== wg show warp ==='
  wg show warp 2>/dev/null || true
  echo '=== saved endpoint ==='
  read_state || true
  echo '=== ipv4 trace ==='
  curl -4 -s --max-time 12 https://www.cloudflare.com/cdn-cgi/trace || true
  echo
  echo '=== ipv4 ip ==='
  curl -4 -s --max-time 12 https://api.ipify.org || true
  echo
  echo '=== ipv6 ip ==='
  curl -6 -s --max-time 12 https://api64.ipify.org || true
  echo
}

write_wrapper() {
  mkdir -p /usr/local/bin
  cat > "$WRAPPER" <<'EOF'
#!/bin/sh
set -eu
INSTALLER=/root/warp-ipv4-installer.sh
case "${1:-status}" in
  up)
    wg-quick up warp
    ;;
  down)
    wg-quick down warp
    ;;
  restart)
    wg-quick down warp >/dev/null 2>&1 || true
    wg-quick up warp
    ;;
  reprobe)
    exec "$INSTALLER" reprobe
    ;;
  status)
    wg show warp 2>/dev/null || true
    echo '---'
    curl -4 -s --max-time 12 https://api.ipify.org || true
    echo
    ;;
  *)
    echo "usage: warp-ipv4 {up|down|restart|reprobe|status}" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$WRAPPER"
}

write_locald() {
  mkdir -p /etc/local.d
  cat > "$LOCAL_START" <<'EOF'
#!/bin/sh
cat > /etc/resolv.conf <<'EODNS'
nameserver 2606:4700:4700::1111
nameserver 2606:4700:4700::1001
nameserver 2001:4860:4860::8888
EODNS
wg-quick down warp >/dev/null 2>&1 || true
wg-quick up warp >/dev/null 2>&1 || true
EOF
  cat > "$LOCAL_STOP" <<'EOF'
#!/bin/sh
wg-quick down warp >/dev/null 2>&1 || true
EOF
  chmod +x "$LOCAL_START" "$LOCAL_STOP"
  rc-update add local default >/dev/null 2>&1 || true
}

install_main() {
  need_root
  install_deps
  write_dns
  if ! result="$(probe_all)"; then
    echo 'No working endpoint/port found' >&2
    exit 1
  fi
  endpoint=$(echo "$result" | awk '{print $1}')
  port=$(echo "$result" | awk '{print $2}')
  write_conf "$endpoint" "$port"
  save_state "$endpoint" "$port"
  write_wrapper
  write_locald
  echo
  echo "Installed successfully"
  echo "Endpoint: [${endpoint}]:${port}"
  status
}

reprobe_main() {
  need_root
  install_deps
  write_dns
  result="$(probe_all)"
  endpoint=$(echo "$result" | awk '{print $1}')
  port=$(echo "$result" | awk '{print $2}')
  write_conf "$endpoint" "$port"
  save_state "$endpoint" "$port"
  echo "Switched to [${endpoint}]:${port}"
  status
}

case "${1:-install}" in
  install)
    install_main
    ;;
  reprobe)
    reprobe_main
    ;;
  status)
    status
    ;;
  *)
    echo "usage: $0 {install|reprobe|status}" >&2
    exit 1
    ;;
esac
