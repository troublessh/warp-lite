# Alpine WARP IPv4 Installer

一键给 **原生 IPv6 / 无原生 IPv4 / CGNAT** 的 Alpine VPS 装一个 **WARP IPv4 出口**。

特点：
- 自动安装依赖
- 自动轮询可用的 Cloudflare IPv6 endpoint + port
- 仅接管 `0.0.0.0/0`，保留原生 IPv6
- 自动写入 DNS
- 自动配置开机自启
- 提供 `warp-ipv4` 管理命令

## 一键安装

```sh
wget -qO- https://raw.githubusercontent.com/troublessh/alpine-warp-ipv4-installer/main/warp-ipv4-installer.sh | sh
```

或：

```sh
curl -fsSL https://raw.githubusercontent.com/troublessh/alpine-warp-ipv4-installer/main/warp-ipv4-installer.sh | sh
```

## 安装后命令

```sh
warp-ipv4 status
warp-ipv4 restart
warp-ipv4 down
warp-ipv4 reprobe
```

## 脚本位置

- 安装脚本：`/root/warp-ipv4-installer.sh`
- WireGuard 配置：`/etc/wireguard/warp.conf`
- 状态文件：`/var/lib/warp-ipv4/active-endpoint`
- 启动命令：`/usr/local/bin/warp-ipv4`

## 适用场景

- Alpine Linux
- 原生 IPv6 正常
- 原生 IPv4 不可用或被 CGNAT 限制
- 需要一个稳定的 WARP IPv4 出口
