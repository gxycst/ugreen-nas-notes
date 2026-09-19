# 绿联 NAS Docker 持久化数据迁移 SSD：减少机械盘唤醒

> 状态：**待完成 / 待现场核验**。本章是迁移计划，不代表迁移已经执行成功。

目标是把 Docker 相关持久化目录从存储空间 1 的机械盘迁移到存储空间 2 的 `ssd_docker`，减少 Docker 持续访问机械盘，提升硬盘进入休眠的机会。

## 先分清两类数据

Docker Root Dir 与容器 bind mount 是两回事。即使 Docker Root Dir 已位于 SSD，Compose 或 `docker run -v` 仍可能把 `/config`、`/data` 等目录绑定到 `/volume1`。

迁移前先通过 SSH 检查：

```bash
docker info --format '{{.DockerRootDir}}'
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'
docker inspect <CONTAINER_NAME> --format '{{json .Mounts}}'
```

必须逐个检查容器的 `.Mounts`，不能只看 Docker Root Dir。

## 拟迁移范围

至少核对：

- `linuxserver_chromium-1`：当前记录为 `/volume1/docker/linuxserver_chromium-1/config:/config`；
- `ghcr.io_metacubex_metacubexd-server-1` 的持久化挂载；
- Tailscale 状态目录；
- `metacube-gateway` 的 Nginx 配置来源；
- 其他仍引用 `/volume1` 的 Compose 文件和 bind mount。

建议目标统一放在：

```text
/volume2/ssd_docker/<service-name>/
```

实际路径必须以 NAS 当前挂载结果为准。

## 建议迁移流程

1. 确保有不依赖待停容器的 SSH 或管理入口。
2. 保存 `docker inspect` 输出和现有启动/Compose 配置。
3. 停止相关服务；若 SSH 依赖 Tailscale，最后停止 Tailscale。
4. 创建 SSD 目标目录并保留原属主、权限和数字 UID/GID。
5. 复制数据，不删除机械盘源目录。
6. 修改 bind mount / Compose 路径后重建容器。
7. 检查每个新容器的 `.Mounts`、日志和业务访问。
8. 做一次复制差异检查；确认无误后再决定是否删除源数据。

数据复制示例（执行前替换并逐字核对路径）：

```bash
sudo rsync -aH --numeric-ids \
  /volume1/docker/<service>/ \
  /volume2/ssd_docker/<service>/
```

差异复查：

```bash
sudo rsync -aHn --delete --numeric-ids \
  /volume1/docker/<service>/ \
  /volume2/ssd_docker/<service>/
```

`-n` 是 dry run。看到预期差异前不要加入真实删除操作。在部分 NAS 文件系统上，`rsync -aHAX` 可能因 ACL/xattr 支持不同而失败；应先确认文件系统能力，不要盲目复制参数。

## 完成标准

只有以下项目全部通过，才能把本章状态改为“已完成”：

- Docker Root Dir 已记录；
- 所有目标容器的 `.Mounts` 都指向预期 SSD 路径；
- Chromium、MetaCubeXD/Mihomo、Tailscale 和 `metacube-gateway` 均已恢复；
- 局域网与公网入口分别验证；
- 无 Docker 进程继续打开 `/volume1` 下的旧持久化目录；
- 旧数据在充分验证和备份后才处理。

