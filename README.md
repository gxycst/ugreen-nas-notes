# UGREEN NAS Notes

绿联 NAS、Docker、Mihomo、MetaCubeXD、LinuxServer Chromium 与 Tailscale 的真实部署和排障记录。

这里记录的是实际环境中验证过的配置、故障现象和判断方法，不是纯官方文档搬运。示例中的 Secret、Token、密码和公网域名均使用占位符。

## 当前环境

- NAS 局域网地址：`192.168.31.192`
- 容器平台：Docker
- 远程浏览器：LinuxServer Chromium（Selkies）
- 代理与管理：Mihomo + MetaCubeXD
- 异地组网：Tailscale Subnet Router

## 文档

- [MetaCubeXD + Mihomo + UGREENlink 公网管理](./docs/01-metacubex-mihomo-ugreenlink.md)
- [LinuxServer Chromium：中文、代理与远程浏览器](./docs/02-linuxserver-chromium.md)
- [Tailscale：异地访问绿联 NAS 和家庭局域网](./docs/03-tailscale-remote-access.md)
- [Docker 持久化数据迁移 SSD](./docs/04-docker-migrate-to-ssd.md)
- [常见问题与排障](./docs/troubleshooting.md)

## 可复用配置

- [`configs/metacube-gateway-nginx.conf`](./configs/metacube-gateway-nginx.conf)：UGREENlink 单入口 Nginx 反向代理
- [`configs/chromium-docker-run.sh`](./configs/chromium-docker-run.sh)：LinuxServer Chromium 启动示例
- [`configs/tailscale-compose.yml`](./configs/tailscale-compose.yml)：Tailscale Subnet Router Compose 示例

## 状态说明

| 内容 | 状态 |
| --- | --- |
| MetaCubeXD / Mihomo UGREENlink 网关 | 已验证 |
| LinuxServer Chromium HTTPS 访问与代理 | 已使用 |
| Tailscale Subnet Router | 已部署方案记录 |
| Docker 持久化目录迁移 SSD | 待完成；先核对 mounts 与 Docker Root Dir |

## 安全提示

- 不要把 Mihomo `secret`、Tailscale Auth Key、UGREENlink Token 或密码提交到 Git。
- 示例里的 `<MIHOMO_SECRET>`、`tskey-xxxx`、`nas.example.com` 必须替换为自己的值。
- SSH、Mihomo API 和管理页面不要直接裸露到公网；优先使用 Tailscale 或受控的 UGREENlink 入口。

