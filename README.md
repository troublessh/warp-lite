# WARP IPv4 Installer

一键给 **原生 IPv6 / 无原生 IPv4 / CGNAT** 的 VPS 装一个 **WARP IPv4 出口**。

支持：
- Alpine Linux
- Debian
- Ubuntu

脚本会：
- 自动安装依赖
- 自动轮询可用的 Cloudflare IPv6 endpoint + port
- 仅接管 `0.0.0.0/0`，保留原生 IPv6
- 自动写入 DNS
- 自动配置开机自启
- 提供 `warp-ipv4` 管理命令

## 一键安装

```sh
wget -qO- https://raw.githubusercontent.com/troublessh/warp-lite/main/warp-ipv4-installer.sh | sh
```

或：

```sh
curl -fsSL https://raw.githubusercontent.com/troublessh/warp-lite/main/warp-ipv4-installer.sh | sh
```

## 低性能机器模式

适合小鸡、低内存、慢 CPU：
- 更少的 endpoint/port 探测
- 更少的 DNS
- 更短的依赖链
- 少一次 trace 输出

```sh
wget -qO- https://raw.githubusercontent.com/troublessh/warp-lite/main/warp-ipv4-installer.sh | sh -s -- install --low-resource
```

或：

```sh
curl -fsSL https://raw.githubusercontent.com/troublessh/warp-lite/main/warp-ipv4-installer.sh | sh -s -- install --low-resource
```

## 安装后命令

```sh
warp-ipv4 status
warp-ipv4 restart
warp-ipv4 down
warp-ipv4 reprobe
```

## 高级用法

强制指定 endpoint / port：

```sh
sh warp-ipv4-installer.sh install --endpoint 2606:4700:d0::a29f:c001 --port 500
```

跳过依赖安装：

```sh
sh warp-ipv4-installer.sh install --skip-deps
```

## 脚本落地位置

- 安装副本：`/root/warp-ipv4-installer.sh`
- WireGuard 配置：`/etc/wireguard/warp.conf`
- 状态文件：`/var/lib/warp-ipv4/active-endpoint`
- 管理命令：`/usr/local/bin/warp-ipv4`

## 适用场景

- 原生 IPv6 正常
- 原生 IPv4 不可用或被 CGNAT 限制
- 需要一个稳定的 WARP IPv4 出口
- 不想让 WARP 接管原生 IPv6
