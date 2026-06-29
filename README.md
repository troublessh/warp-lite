# warp-lite

一键给 **原生 IPv6 / 无原生 IPv4 / CGNAT** 的 VPS 装一个轻量 WARP 出口。

支持：
- Alpine Linux
- Debian
- Ubuntu

当前支持模式：
- `--mode v4`：WARP 提供 IPv4 出口，保留原生 IPv6
- `--mode v6`：WARP 提供 IPv6 出口

脚本会：
- 自动安装依赖
- 自动轮询可用的 Cloudflare IPv6 endpoint + port
- 自动写入 DNS
- 自动配置开机自启
- 提供 `warp-lite` 管理命令

## 一键安装

默认安装 `v4` 模式：

```sh
wget -qO- https://raw.githubusercontent.com/troublessh/warp-lite/main/warp-lite.sh | sh
```

或：

```sh
curl -fsSL https://raw.githubusercontent.com/troublessh/warp-lite/main/warp-lite.sh | sh
```

## 安装 IPv6 单栈模式

```sh
wget -qO- https://raw.githubusercontent.com/troublessh/warp-lite/main/warp-lite.sh | sh -s -- install --mode v6
```

或：

```sh
curl -fsSL https://raw.githubusercontent.com/troublessh/warp-lite/main/warp-lite.sh | sh -s -- install --mode v6
```

## 低性能机器模式

适合小鸡、低内存、慢 CPU：
- 更少的 endpoint/port 探测
- 更少的 DNS
- 少一次 trace 输出

默认 `v4`：

```sh
wget -qO- https://raw.githubusercontent.com/troublessh/warp-lite/main/warp-lite.sh | sh -s -- install --low-resource
```

`v6`：

```sh
wget -qO- https://raw.githubusercontent.com/troublessh/warp-lite/main/warp-lite.sh | sh -s -- install --mode v6 --low-resource
```

## 安装后命令

```sh
warp-lite status
warp-lite restart
warp-lite down
warp-lite reprobe
```

## 高级用法

强制指定 endpoint / port：

```sh
sh warp-lite.sh install --mode v4 --endpoint 2606:4700:d0::a29f:c001 --port 500
```

跳过依赖安装：

```sh
sh warp-lite.sh install --skip-deps
```

## 脚本落地位置

- 安装副本：`/root/warp-lite.sh`
- WireGuard 配置：`/etc/wireguard/warp.conf`
- 状态文件：`/var/lib/warp-lite/active-endpoint`
- 管理命令：`/usr/local/bin/warp-lite`

## 适用场景

- 原生 IPv6 正常
- 原生 IPv4 不可用或被 CGNAT 限制
- 需要一个稳定的 WARP IPv4 / IPv6 单栈出口
- 不想让 WARP 接管另一栈
