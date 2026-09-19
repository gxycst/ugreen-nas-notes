# LinuxServer Chromium 中文界面、Mihomo 代理与绿联 NAS 远程访问

本文记录绿联 NAS 上 `linuxserver/chromium:latest` 的当前部署方式，包括 HTTPS 入口、中文参数、Mihomo SOCKS5 代理、持久化，以及保留旧镜像标签的升级回滚方法。

## 当前配置

- 容器名：`linuxserver_chromium-1`
- 镜像：`linuxserver/chromium:latest`
- 持久化：`/volume1/docker/linuxserver_chromium-1/config:/config`
- HTTP：NAS `44635` → 容器 `3000`
- HTTPS：NAS `38517` → 容器 `3001`
- 局域网入口：`https://192.168.31.192:38517`

新版 Selkies 前端要求安全连接。局域网应优先使用 HTTPS 38517；直接使用 `http://192.168.31.192:44635` 可能出现安全连接、黑屏或 WebSocket 断开问题。自签名证书首次访问时需要在受信任网络中手动确认浏览器警告。

## 中文与代理环境变量

关键参数：

```text
PUID=1000
PGID=10
TITLE=Chromium
CHROME_CLI=--lang=zh-CN --proxy-server=socks5://192.168.31.192:34421
http_proxy=socks5://192.168.31.192:34421
https_proxy=socks5://192.168.31.192:34421
all_proxy=socks5://192.168.31.192:34421
LANG=zh_CN.UTF-8
LANGUAGE=zh_CN:zh
LC_ALL=zh_CN.UTF-8
```

可直接复用的启动命令见 [`../configs/chromium-docker-run.sh`](../configs/chromium-docker-run.sh)。

注意：`--lang=zh-CN` 控制 Chromium 的语言倾向；`LANG`、`LANGUAGE`、`LC_ALL` 是容器区域设置尝试。镜像内是否包含完整中文 locale 和字体仍取决于具体版本，升级后应实际检查界面和中文输入。

## 升级并保留回滚镜像

先在 NAS 的 SSH 终端检查当前镜像 ID，并给旧镜像增加本地标签：

```bash
docker inspect linuxserver_chromium-1 --format '{{.Image}}'
docker tag linuxserver/chromium:latest linuxserver/chromium:rollback-before-update
docker pull linuxserver/chromium:latest
```

然后停止、删除并用同一组参数重建容器：

```bash
docker stop linuxserver_chromium-1
docker rm linuxserver_chromium-1
bash ./configs/chromium-docker-run.sh
```

数据保存在宿主机 `/config` 映射目录中，删除容器不会删除该目录。重建前仍应确认挂载路径无误，并按自己的备份策略备份重要资料。

如新版有问题，可停止并删除当前容器，再把脚本中的镜像临时改为：

```text
linuxserver/chromium:rollback-before-update
```

## 方案演进

- 旧 Firefox 方案通过 `ibus-libpinyin` 实现过中文输入。
- Kasm Chromium 曾遇到分辨率、黑边和 UGREENlink HTTPS 适配问题，最终放弃。
- 当前方案是 LinuxServer Chromium；其远程桌面传输/前端是 Selkies，不应与旧 KasmVNC 方案混为一谈。

