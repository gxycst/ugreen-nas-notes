# MetaCubeXD 后端无法连接：UGREENlink 远程管理 Mihomo 的实战配置

本文记录绿联 NAS 上通过 UGREENlink 公网访问 MetaCubeXD，并把同一公网入口下的 `/mihomo/` 转发到 Mihomo API 的真实配置与排障过程。重点结论是：服务端 API 和 WebSocket 全部正常时，“后端无法连接”也可能来自浏览器 PWA、Service Worker 或旧缓存。

## 环境与端口

容器名：`ghcr.io_metacubex_metacubexd-server-1`

| NAS 端口 | 容器端口 | 用途 |
| --- | --- | --- |
| `34421` | `7890` | Mihomo mixed proxy |
| `42099` | `8080` | MetaCubeXD Web |
| `36815` | `9090` | Mihomo API |

Mihomo API 已启用 Secret。本文只使用 `<MIHOMO_SECRET>` 占位符。

## 为什么增加 metacube-gateway

UGREENlink 对外提供一个入口。为了让前端页面和 Mihomo API 使用同一个公网域名，增加一个名为 `metacube-gateway` 的 Nginx 容器：

- 使用 host network；
- 监听 NAS 的 `18080`；
- `/` 转发到 `127.0.0.1:42099`；
- `/mihomo/` 转发到 `127.0.0.1:36815`；
- 转发 WebSocket 的 `Upgrade` 和 `Connection` 头；
- `proxy_read_timeout` 设为 `3600s`。

完整示例见 [`../configs/metacube-gateway-nginx.conf`](../configs/metacube-gateway-nginx.conf)。UGREENlink 应把公网入口绑定到 NAS 的 `18080`。

MetaCubeXD 中的后端地址填写：

```text
https://nas.example.com/mihomo
```

Secret 单独填写 `<MIHOMO_SECRET>`。不要把 UGREENlink 自身的 `/api/ugreen/auth?token=...` 地址当成 Mihomo 后端地址。

## 服务端验证过程

在 NAS 上直接请求 Mihomo API，不带鉴权时：

```bash
curl -i http://127.0.0.1:36815/version
```

返回 `401 Unauthorized`，说明 API 在线且鉴权生效。

再经过 Nginx 网关请求：

```bash
curl -i http://127.0.0.1:18080/mihomo/version
```

同样返回 `401 Unauthorized`，说明路径转发已到达 Mihomo，而不是 Nginx 找不到上游。

带 Secret 验证：

```bash
curl -i \
  -H 'Authorization: Bearer <MIHOMO_SECRET>' \
  http://127.0.0.1:18080/mihomo/version
```

实际验证返回 `200 OK`：

```json
{"meta":true,"version":"v1.19.27"}
```

当时 Nginx 日志还确认以下请求均成功：

- `/mihomo/version`、`/configs`、`/proxies`、`/providers/proxies`：HTTP `200`；
- `traffic`、`memory`、`connections`、`logs` WebSocket：HTTP `101 Switching Protocols`。

这组证据说明页面、API、Secret 和 WebSocket 网关都已正常，故障不在 Docker 或 Nginx。

## 最终根因：PWA / Service Worker / 缓存

服务端全部通过后，MetaCubeXD 仍显示“后端无法连接”。最终按以下顺序清理浏览器后恢复：

1. 打开开发者工具的 **Application**。
2. 在 **Service Workers** 中点击 **Unregister**。
3. 在 **Storage** 中点击 **Clear site data**。
4. 按 `Ctrl+Shift+R` 强制刷新。
5. 重新填写公网 `/mihomo` 后端地址与 Secret。

因此，遇到相同现象时不要立刻重建容器。先用 `401 → 带 Secret 200 → WebSocket 101` 的顺序证明服务端链路，再处理浏览器状态。

## 更稳妥的缓存策略

示例 Nginx 配置只为 HTML 入口和 `/sw.js` 增加 `no-store`，没有创建第二个冲突的 `location /`。带 hash 的 JS/CSS/图片仍可沿用上游缓存策略。

如确认当前版本不再依赖 Service Worker，也可以单独让 `location = /sw.js` 返回 `410`；首次部署不建议这样做，先使用示例里的 no-cache 方案。

