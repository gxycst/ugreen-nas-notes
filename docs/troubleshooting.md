# 绿联 NAS Docker 常见问题：MetaCubeXD、Mihomo、Chromium 与 Tailscale 排障

## MetaCubeXD 显示“后端无法连接”

按证据从后端向浏览器排查：

1. `http://127.0.0.1:36815/version` 无 Secret 返回 `401`：Mihomo API 在线且鉴权生效。
2. `http://127.0.0.1:18080/mihomo/version` 无 Secret 返回 `401`：Nginx 路径转发正常。
3. 加 `Authorization: Bearer <MIHOMO_SECRET>` 返回 `200`：Secret 正确。
4. Nginx 日志中的 `traffic`、`memory`、`connections`、`logs` 返回 `101`：WebSocket 正常。
5. 如果以上都通过，清理浏览器 Service Worker 和站点数据，再强制刷新。

不要把 UGREENlink 的认证 Token 当成 Mihomo Secret，也不要把 `/api/ugreen/auth?token=...` 当作后端地址。

## Nginx 出现 502 Bad Gateway

- 确认 `metacube-gateway` 使用 host network，否则容器内的 `127.0.0.1` 不是 NAS 主机。
- 检查 NAS 本机 `42099` 和 `36815` 是否监听。
- 检查主 MetaCubeXD/Mihomo 容器是否正在运行。
- 检查防火墙与端口占用。

## 公网入口打不开，但局域网正常

- 确认 UGREENlink 入口绑定的是 `18080`。
- 检查 `metacube-gateway` 是否因维护被停止后未恢复。
- 查看 Nginx access log：完全没有公网请求时，优先检查 UGREENlink 绑定、快捷方式和域名入口。
- 有请求且 API/WebSocket 正常时，检查浏览器 PWA/Service Worker 缓存。

## Chromium 显示 WebSocket disconnected 或黑屏

- 使用 `https://192.168.31.192:38517`，不要把 HTTP 44635 当作新版的首选入口。
- 先验证局域网直连，再排查 UGREENlink 公网链路。
- 确认 HTTPS 证书警告已被浏览器接受。
- 检查 `linuxserver_chromium-1` 日志和 `38517 -> 3001` 映射。
- 不要因为错误信息中出现 WebSocket 就直接重建容器。

## Chromium 代理不可用

- 检查 Mihomo mixed proxy 是否监听 NAS 的 `34421`。
- 容器参数应为 `socks5://192.168.31.192:34421`。
- 同时检查 `CHROME_CLI` 与大小写环境变量。
- 在 NAS 和容器内分别验证到 `192.168.31.192:34421` 的连通性。

## 旧浏览器方案

- Firefox 曾通过 `ibus-libpinyin` 实现中文输入，可作为历史备选。
- Kasm Chromium 因分辨率、黑边和 UGREENlink HTTPS 等问题放弃。
- 当前 LinuxServer Chromium 使用 Selkies；旧 KasmVNC 的排障方法不一定适用。

## Tailscale 子网设备不可达

- 确认容器运行且已登录 Tailnet。
- 确认发布 `192.168.31.0/24`。
- 在管理后台批准该路由。
- 客户端启用接受路由。
- 确认 `/dev/net/tun`、`NET_ADMIN` 和 NAS 转发能力。
- 直连失败可能走 DERP，不等于连接失败；用 `tailscale status` 和 `tailscale netcheck` 判断。

## 机械盘仍被唤醒

- `DockerRootDir` 在 SSD 不代表 bind mount 也在 SSD。
- 对每个容器执行 `docker inspect` 并检查 `.Mounts`。
- 搜索 Compose、脚本和计划任务中残留的 `/volume1`。
- 迁移验证前不要删除机械盘源数据。

