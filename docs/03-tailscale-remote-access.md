# Tailscale 绿联 NAS Subnet Router：异地访问家庭局域网

本文记录在绿联 NAS 上通过 Docker 部署 Tailscale，并发布 `192.168.31.0/24` 路由，让异地设备访问 NAS 和家庭局域网设备。

## 工作原理

Tailscale 基于 WireGuard 加密隧道。协调服务器负责设备发现与密钥协调；设备会优先通过 NAT 穿透和 UDP 打洞建立点对点连接，直连失败时自动使用 DERP 中继。DERP 转发的是端到端加密流量。

Subnet Router 发布家庭网段后，已登录同一 Tailnet 且获准使用路由的远端设备，可以访问 `192.168.31.0/24`。

## Compose 示例

见 [`../configs/tailscale-compose.yml`](../configs/tailscale-compose.yml)。其中：

```text
TS_AUTH_KEY=tskey-xxxx
```

只是占位符。建议使用短期、可撤销、权限受限的 Auth Key，不要把真实 Key 提交到仓库。

启动后还需要在 Tailscale 管理后台批准 `192.168.31.0/24` 子网路由。不同客户端可能还需要启用“接受路由”。

## SSH 不需要公网映射 22 端口

如果只通过 Tailscale SSH 到 NAS，NAS 本机 SSH 服务监听 `22` 即可；路由器或 UGREENlink 不需要把公网端口映射到 `22`。连接时使用 NAS 的 Tailscale IP、MagicDNS 名称，或经 Subnet Router 可达的局域网地址。

这和 Tailscale SSH 功能本身是两种模式：无论使用普通 OpenSSH 还是 Tailscale SSH，都不应为了 Tailnet 访问而开放公网 `22`。

## 临时停用与恢复

维护时可以临时停止或恢复容器：

```bash
docker stop tailscale
docker start tailscale
```

如果当前 SSH 会话本身依赖 Tailscale，停止容器会立刻断开连接。执行前应确保有局域网 SSH、绿联管理界面或其他恢复路径。

## 验证

```bash
docker exec tailscale tailscale status
docker exec tailscale tailscale ip -4
docker exec tailscale tailscale netcheck
```

在异地客户端测试 NAS 后，再测试局域网其他设备。若 NAS 可达但 `192.168.31.0/24` 不可达，优先检查：路由是否在管理后台获批、客户端是否接受路由、容器是否具备 `/dev/net/tun` 与 `NET_ADMIN`。

