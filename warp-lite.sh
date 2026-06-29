#!/bin/sh
set -eu

SCRIPT_URL="https://raw.githubusercontent.com/troublessh/warp-lite/main/warp-lite.sh"
CONF_DIR=/etc/wireguard
CONF_FILE=$CONF_DIR/warp.conf
DNS_FILE=/etc/resolv.conf
WRAPPER=/usr/local/bin/warp-lite
STATE_DIR=/var/lib/warp-lite
STATE_FILE=$STATE_DIR/active-endpoint
LIBEXEC_DIR=/usr/local/libexec
DNS_HELPER=$LIBEXEC_DIR/warp-lite-write-dns.sh
LOCAL_START=/etc/local.d/warp-lite.start
LOCAL_STOP=/etc/local.d/warp-lite.stop
SYSTEMD_SERVICE=/etc/systemd/system/warp-lite.service
INSTALL_COPY=/root/warp-lite.sh

DEFAULT_ENDPOINTS="2606:4700:d0::a29f:c001 2606:4700:d0::a29f:c005"
DEFAULT_PORTS="500 1701 4500 2408"
LOW_RESOURCE_ENDPOINTS="2606:4700:d0::a29f:c001"
LOW_RESOURCE_PORTS="500 1701"
DEFAULT_DNS="2606:4700:4700::1111 2606:4700:4700::1001 2001:4860:4860::8888"
LOW_RESOURCE_DNS="2606:4700:4700::1111 2001:4860:4860::8888"

PRIVATE_KEY='hTk06uwwXhZx3RVqtug3MQ0RSodzdM/U5z/M5NIbh4c='
WARP_V4='172.16.0.2'
WARP_V6='2606:4700:110:8921:bf06:c4d7:40b7:8afd'
PEER_KEY='bmXOC+F1FxEMF9dyiK2H5/1SUtzH0JuVo51h2wPfgyo='

COMMAND=install
LOW_RESOURCE=0
SKIP_DEPS=0
FORCE_ENDPOINT=
FORCE_PORT=
MODE=v4

log() {
  printf '%s\n' "$*" >&2
}

need_root() {
  [ "$(id -u)" = 0 ] || {
    echo "run as root" >&2
    exit 1
  }
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      install|reprobe|status)
        COMMAND="$1"
        ;;
      --low-resource)
        LOW_RESOURCE=1
        ;;
      --skip-deps)
        SKIP_DEPS=1
        ;;
      --endpoint)
        shift
        [ "$#" -gt 0 ] || { echo "missing value for --endpoint" >&2; exit 1; }
        FORCE_ENDPOINT="$1"
        ;;
      --port)
        shift
        [ "$#" -gt 0 ] || { echo "missing value for --port" >&2; exit 1; }
        FORCE_PORT="$1"
        ;;
      --mode)
        shift
        [ "$#" -gt 0 ] || { echo "missing value for --mode" >&2; exit 1; }
        MODE="$1"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "unknown argument: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
    shift
  done
}

usage() {
  cat <<'EOF'
usage:
  sh warp-lite.sh [install|reprobe|status] [--mode v4|v6] [--low-resource] [--skip-deps] [--endpoint IP] [--port PORT]

examples:
  sh warp-lite.sh
  sh warp-lite.sh install --mode v6
  sh warp-lite.sh install --low-resource
  sh warp-lite.sh reprobe --mode v4
  sh warp-lite.sh install --endpoint 2606:4700:d0::a29f:c001 --port 500
EOF
}

detect_os() {
  OS_ID=unknown
  if [ -r /etc/os-release ]; then
    OS_ID=$(awk -F= '/^ID=/{gsub(/"/,"",$2); print $2; exit}' /etc/os-release)
  fi
  case "$OS_ID" in
    alpine|debian|ubuntu)
      :
      ;;
    *)
      OS_ID=unknown
      ;;
  esac
}

select_profile() {
  case "$MODE" in
    v4|v6)
      :
      ;;
    *)
      echo "unsupported mode: $MODE (use v4 or v6)" >&2
      exit 1
      ;;
  esac

  if [ "$LOW_RESOURCE" = "1" ]; then
    ENDPOINTS="$LOW_RESOURCE_ENDPOINTS"
    PORTS="$LOW_RESOURCE_PORTS"
    DNS_SERVERS="$LOW_RESOURCE_DNS"
    PROBE_SLEEP=4
  else
    ENDPOINTS="$DEFAULT_ENDPOINTS"
    PORTS="$DEFAULT_PORTS"
    DNS_SERVERS="$DEFAULT_DNS"
    PROBE_SLEEP=6
  fi

  if [ -n "$FORCE_ENDPOINT" ]; then
    ENDPOINTS="$FORCE_ENDPOINT"
  fi
  if [ -n "$FORCE_PORT" ]; then
    PORTS="$FORCE_PORT"
  fi
}

install_deps() {
  [ "$SKIP_DEPS" = "1" ] && return 0
  case "$OS_ID" in
    alpine)
      apk add --no-cache wireguard-tools iptables ip6tables openresolv curl >/dev/null
      ;;
    debian|ubuntu)
      export DEBIAN_FRONTEND=noninteractive
      apt-get update -y >/dev/null
      apt-get install -y wireguard-tools iptables openresolv curl >/dev/null
      ;;
    *)
      echo "unsupported system: need Alpine, Debian, or Ubuntu" >&2
      exit 1
      ;;
  esac
}

write_dns() {
  : > "$DNS_FILE"
  for ns in $DNS_SERVERS; do
    printf 'nameserver %s\n' "$ns" >> "$DNS_FILE"
  done
}

write_dns_helper() {
  mkdir -p "$LIBEXEC_DIR"
  cat > "$DNS_HELPER" <<EOF
#!/bin/sh
cat > "$DNS_FILE" <<'EODNS'
$(for ns in $DNS_SERVERS; do printf 'nameserver %s\n' "$ns"; done)
EODNS
EOF
  chmod +x "$DNS_HELPER"
}

write_conf() {
  endpoint="$1"
  port="$2"
  mkdir -p "$CONF_DIR"
  cat > "$CONF_FILE" <<EOF
[Interface]
PrivateKey = ${PRIVATE_KEY}
Address = ${WARP_V4}/32
Address = ${WARP_V6}/128
MTU = 1280

[Peer]
PublicKey = ${PEER_KEY}
EOF
  if [ "$MODE" = "v4" ]; then
    cat >> "$CONF_FILE" <<EOF
AllowedIPs = 0.0.0.0/0
EOF
  else
    cat >> "$CONF_FILE" <<EOF
AllowedIPs = ::/0
EOF
  fi
  cat >> "$CONF_FILE" <<EOF
Endpoint = [${endpoint}]:${port}
PersistentKeepalive = 25
EOF
  chmod 600 "$CONF_FILE"
}

save_state() {
  endpoint="$1"
  port="$2"
  mkdir -p "$STATE_DIR"
  printf 'mode=%s\nendpoint=%s\nport=%s\n' "$MODE" "$endpoint" "$port" > "$STATE_FILE"
}

read_state() {
  [ -s "$STATE_FILE" ] || return 1
  cat "$STATE_FILE"
}

download_self_copy() {
  mkdir -p /root
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$SCRIPT_URL" -o "$INSTALL_COPY" 2>/dev/null || true
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$INSTALL_COPY" "$SCRIPT_URL" 2>/dev/null || true
  fi
  [ -s "$INSTALL_COPY" ] && chmod +x "$INSTALL_COPY" || true
}

bring_down() {
  wg-quick down warp >/dev/null 2>&1 || true
}

bring_up() {
  wg-quick up warp >/tmp/warp-lite-up.log 2>&1
}

try_up() {
  endpoint="$1"
  port="$2"
  log "==> trying [$endpoint]:$port ($MODE)"
  write_conf "$endpoint" "$port"
  bring_down
  if ! bring_up; then
    log "wg-quick up failed"
    cat /tmp/warp-lite-up.log >&2 || true
    return 1
  fi
  sleep "$PROBE_SLEEP"
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
  echo '=== mode ==='
  echo "$MODE"
  echo '=== wg show warp ==='
  wg show warp 2>/dev/null || true
  echo '=== saved endpoint ==='
  read_state || true
  if [ "$MODE" = "v4" ]; then
    echo '=== ipv4 ip ==='
    curl -4 -s --max-time 12 https://api.ipify.org || true
    echo
    echo '=== ipv6 ip ==='
    curl -6 -s --max-time 12 https://api64.ipify.org || true
    echo
    if [ "$LOW_RESOURCE" != "1" ]; then
      echo '=== ipv4 trace ==='
      curl -4 -s --max-time 12 https://www.cloudflare.com/cdn-cgi/trace || true
      echo
    fi
  else
    echo '=== ipv6 ip ==='
    curl -6 -s --max-time 12 https://api64.ipify.org || true
    echo
    if [ "$LOW_RESOURCE" != "1" ]; then
      echo '=== ipv6 trace ==='
      curl -6 -s --max-time 12 https://www.cloudflare.com/cdn-cgi/trace || true
      echo
    fi
  fi
}

write_wrapper() {
  mkdir -p /usr/local/bin
  cat > "$WRAPPER" <<EOF
#!/bin/sh
set -eu
SCRIPT_URL="$SCRIPT_URL"
INSTALL_COPY="$INSTALL_COPY"
refresh_installer() {
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "\$SCRIPT_URL" -o "\$INSTALL_COPY"
  else
    wget -qO "\$INSTALL_COPY" "\$SCRIPT_URL"
  fi
  chmod +x "\$INSTALL_COPY"
}
case "\${1:-status}" in
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
    refresh_installer
    exec "\$INSTALL_COPY" reprobe
    ;;
  status)
    wg show warp 2>/dev/null || true
    echo '---'
    if grep -q '^AllowedIPs = ::/0' /etc/wireguard/warp.conf 2>/dev/null; then
      curl -6 -s --max-time 12 https://api64.ipify.org || true
    else
      curl -4 -s --max-time 12 https://api.ipify.org || true
    fi
    echo
    ;;
  *)
    echo "usage: warp-lite {up|down|restart|reprobe|status}" >&2
    exit 1
    ;;
esac
EOF
  chmod +x "$WRAPPER"
}

write_openrc_autostart() {
  mkdir -p /etc/local.d
  cat > "$LOCAL_START" <<EOF
#!/bin/sh
"$DNS_HELPER"
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

write_systemd_autostart() {
  mkdir -p /etc/systemd/system
  cat > "$SYSTEMD_SERVICE" <<EOF
[Unit]
Description=WARP Lite over native IPv6
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=$DNS_HELPER
ExecStart=/usr/bin/wg-quick up warp
ExecStop=/usr/bin/wg-quick down warp

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload >/dev/null 2>&1 || true
  systemctl enable warp-lite.service >/dev/null 2>&1 || true
}

write_autostart() {
  write_dns_helper
  if command -v rc-update >/dev/null 2>&1; then
    write_openrc_autostart
  elif command -v systemctl >/dev/null 2>&1; then
    write_systemd_autostart
  fi
}

install_main() {
  need_root
  detect_os
  select_profile
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
  write_autostart
  download_self_copy
  echo
  echo "Installed successfully"
  echo "Mode: $MODE"
  echo "Endpoint: [${endpoint}]:${port}"
  status
}

reprobe_main() {
  need_root
  detect_os
  select_profile
  install_deps
  write_dns
  result="$(probe_all)"
  endpoint=$(echo "$result" | awk '{print $1}')
  port=$(echo "$result" | awk '{print $2}')
  write_conf "$endpoint" "$port"
  save_state "$endpoint" "$port"
  write_autostart
  download_self_copy
  echo "Switched to mode=$MODE endpoint=[${endpoint}]:${port}"
  status
}

parse_args "$@"

case "$COMMAND" in
  install)
    install_main
    ;;
  reprobe)
    reprobe_main
    ;;
  status)
    detect_os
    select_profile
    status
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
