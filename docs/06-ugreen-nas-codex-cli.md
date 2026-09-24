# 绿联 NAS 运行 Codex CLI：SSD 持久化、ChatGPT 登录与网页终端

本文记录在绿联 NAS（UGOS Pro）上直接运行 OpenAI Codex CLI 的最终可用方案：Codex 安装在 NAS 宿主机，工作目录和会话数据放到 SSD，网络请求单独走 Mihomo，并可用 ttyd 做成浏览器入口。

这是一份从实际部署结果反推出来的最短路径。正文不保留 NextChat、容器内再套 Codex、反复更换终端镜像等未采用路线，避免干扰。

## 最终结构

```text
电脑 / 手机浏览器
        │
        ▼
UGREENlink 或局域网入口
        │
        ▼
ttyd :7681（systemd）
        │
        ▼
NAS 宿主机 Codex CLI
   ├─ 工作区：/volume2/ssd_docker/codex-work
   ├─ 数据：  /volume2/ssd_docker/codex-data
   └─ 代理：  192.168.31.192:34421
```

关键选择只有三个：

1. Codex 直接装在 NAS 宿主机，而不是装进 Docker，这样它能正常操作 NAS 本机文件、Docker 和 systemd。
2. `codex-work` 与 `.codex` 都放到 SSD，避免会话记录和项目读写唤醒机械盘。
3. 只给 Codex/ttyd 服务设置代理，不修改 NAS 全局网络。

## 一、准备 SSH、SSD 目录和代理

在 UGOS Pro 中临时开启 SSH，然后从电脑登录 NAS：

```bash
ssh <NAS_USER>@192.168.31.192
```

创建 SSD 工作区：

```bash
sudo mkdir -p /volume2/ssd_docker/codex-work
sudo mkdir -p /volume2/ssd_docker/codex-data
sudo mkdir -p /volume2/ssd_docker/ttyd
sudo chown -R "$USER":"$(id -gn)" \
  /volume2/ssd_docker/codex-work \
  /volume2/ssd_docker/codex-data \
  /volume2/ssd_docker/ttyd
```

本例使用 NAS 上已经运行的 Mihomo mixed 端口：

```text
http://192.168.31.192:34421
```

先给当前 Shell 设置代理：

```bash
export HTTP_PROXY=http://192.168.31.192:34421
export HTTPS_PROXY=http://192.168.31.192:34421
export ALL_PROXY=http://192.168.31.192:34421
```

这只影响当前 Shell，不会把整个 NAS 改成全局代理。

## 二、安装 Codex CLI

Linux 上直接使用 OpenAI 安装脚本，避免为了 Codex 额外维护 Node.js/npm：

```bash
curl -fsSL https://chatgpt.com/codex/install.sh | sh
```

让当前 Shell 立即识别安装路径：

```bash
export PATH="$HOME/.local/bin:$PATH"
```

验证：

```bash
codex --version
```

如果重新登录 SSH 后提示 `codex: command not found`，把路径永久加入用户环境：

```bash
printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> ~/.bashrc
source ~/.bashrc
```

官方也提供 npm 安装方式，但这台 NAS 已验证使用独立安装脚本更省事。Codex CLI 与 OpenAI API CLI 是两个不同工具，不要误装成 `openai` 命令。

## 三、使用 ChatGPT 账号登录

不要把 API Key 写进文档、脚本或 systemd 服务。使用 ChatGPT 账号登录即可。

### 方式 A：设备代码登录

在 ChatGPT 的安全设置中启用 Codex CLI 设备代码授权，然后在 NAS 执行：

```bash
codex login --device-auth
```

在电脑或手机浏览器打开命令显示的网址，输入一次性设备代码并完成授权。设备代码相当于临时凭据，不要发送给其他人。

### 方式 B：SSH 转发登录回调

如果设备代码登录不可用，使用这一条已经实际验证过的方式。

先在 Windows PowerShell 建立带回调端口的 SSH 连接：

```powershell
ssh -L 1455:localhost:1455 <NAS_USER>@192.168.31.192
```

保持窗口不关，在这条 SSH 会话里设置代理并登录：

```bash
export HTTP_PROXY=http://192.168.31.192:34421
export HTTPS_PROXY=http://192.168.31.192:34421
export ALL_PROXY=http://192.168.31.192:34421
codex login
```

打开命令给出的登录地址。浏览器最后访问 Windows 的 `localhost:1455` 时，SSH 会把回调转到 NAS 上的 Codex。

出现 `Signed in to Codex` 后验证：

```bash
codex login status
```

授权信息会保存在 `~/.codex`，日常运行不再需要 `-L 1455`；只有重新登录时才可能再次使用。

## 四、把 Codex 数据迁到 SSD

`~/.codex` 保存登录状态、配置、会话历史和本地数据库。迁移前先退出所有 Codex 进程。

使用“复制、保留旧目录、再建立软链接”的流程，不直接删除原数据：

```bash
cp -a ~/.codex/. /volume2/ssd_docker/codex-data/
mv ~/.codex ~/.codex.backup
ln -s /volume2/ssd_docker/codex-data ~/.codex
```

验证软链接和登录状态：

```bash
ls -ld ~/.codex
codex login status
```

预期路径关系：

```text
/home/<NAS_USER>/.codex -> /volume2/ssd_docker/codex-data
```

确认使用数日都正常后，再自行决定是否删除 `~/.codex.backup`。不要刚迁完就删备份。

## 五、直接运行 Codex

```bash
cd /volume2/ssd_docker/codex-work

export HTTP_PROXY=http://192.168.31.192:34421
export HTTPS_PROXY=http://192.168.31.192:34421
export ALL_PROXY=http://192.168.31.192:34421

codex
```

不要在整个用户主目录下直接信任 Codex。把日常项目放进 `codex-work`，只信任明确的工作目录。

常用检查：

```bash
codex --version
codex login status
codex resume
```

更新仍使用同一个安装脚本：

```bash
export HTTP_PROXY=http://192.168.31.192:34421
export HTTPS_PROXY=http://192.168.31.192:34421
export ALL_PROXY=http://192.168.31.192:34421
curl -fsSL https://chatgpt.com/codex/install.sh | sh
codex --version
```

更新 Codex 不会删除 `/volume2/ssd_docker/codex-data` 中的登录状态和历史会话。

## 六、可选：做成浏览器里的 Codex 网页终端

只在 SSH 中使用 Codex，到上一节已经完成。需要从 UGOS 桌面、手机或其他电脑浏览器进入时，再增加 ttyd。

### 1. 下载已验证的 ttyd 版本

实际使用中，某些后续构建的 ttyd/libwebsockets 组合在粘贴约 2 KB 以上文本时会断开 WebSocket，表现为 `Reconnecting...`。最终使用官方 ttyd `1.7.7` 静态文件解决。

```bash
cd /volume2/ssd_docker/ttyd

curl -L \
  https://github.com/tsl0922/ttyd/releases/download/1.7.7/ttyd.x86_64 \
  -o ttyd-host

chmod 755 ttyd-host
./ttyd-host --version
```

如果是 ARM NAS，不能使用 `ttyd.x86_64`，需要换成与 CPU 架构匹配的 Release 文件。本次实测机型为 x86_64。

### 2. 安装 systemd 服务

仓库提供了模板：[`configs/codex-web.service`](../configs/codex-web.service)。复制前替换：

```text
<NAS_USER>
```

然后安装：

```bash
sudo cp /path/to/codex-web.service /etc/systemd/system/codex-web.service
sudo systemctl daemon-reload
sudo systemctl enable --now codex-web
sudo systemctl status codex-web --no-pager
```

局域网访问：

```text
http://192.168.31.192:7681
```

需要 UGREENlink 时，给 `7681` 创建一个受控的桌面快捷方式。不要把这个无鉴权的 HTTP 端口直接转发到公网；至少放在 UGREENlink 登录层、Tailscale 或其他有认证的反向代理后面。

## 七、最重要的排障顺序

### Codex 能启动，但无法联网

```bash
env | grep -i proxy
curl -I https://chatgpt.com
codex login status
```

如果手动运行正常、网页终端不正常，检查 systemd 服务是否包含三个代理环境变量：

```bash
sudo systemctl cat codex-web
```

### 浏览器粘贴长文本后出现 Reconnecting

先看日志：

```bash
sudo journalctl -u codex-web -n 100 --no-pager
```

如果出现类似：

```text
lws_extension_callback_pm_deflate: rx buffer underflow
```

不要重装 Codex。问题在 ttyd/libwebsockets，换成本页指定的官方 ttyd `1.7.7`。

### NAS 重启后网页打不开

```bash
sudo systemctl status codex-web --no-pager
sudo ss -lntp | grep 7681
```

### 登录成功但历史消失

```bash
ls -ld ~/.codex
ls -la /volume2/ssd_docker/codex-data | head
```

重点确认 `~/.codex` 软链接没有被重新创建成普通目录。

## 八、这套方案没有采用什么

为了避免正文再次变成试错记录，只保留结论：

- 不用 NextChat：它走 API Key 单独计费，不能直接消费 ChatGPT Plus 的 Codex 用量。
- 不把 Codex 装进 ttyd Docker：容器会隔离宿主机能力，不适合让 Codex维护 NAS 本机。
- 不用 Chromium 承担终端：ttyd 资源更少，启动更直接。
- 不关闭 SSH 后再让容器 SSH 回宿主机：SSH 服务关闭后这条链路必然断开。
- 不使用来源不明的 ttyd 构建：长文本粘贴可能触发 WebSocket 重连。

## 安全提醒

- 不要提交 `~/.codex/auth.json`、访问令牌、设备代码或 API Key。
- `codex-data` 包含登录状态和会话记录，备份时按敏感数据处理。
- Codex 拥有当前 Linux 用户能够访问的文件和命令权限；不要用 root 用户长期运行。
- ttyd 本身只是网页终端，不等于身份认证系统，不要裸露到公网。

## 参考

- [OpenAI Codex](https://developers.openai.com/learn/codex)
- [Codex CLI 设备代码身份验证说明](https://developers.openai.com/zh-Hans/docs/enterprise/access-tokens)
- [ttyd 1.7.7 Release](https://github.com/tsl0922/ttyd/releases/tag/1.7.7)
