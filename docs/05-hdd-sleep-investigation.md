# 绿联 NAS 硬盘休眠失效排查：风扇高转、Chromium、相册智能分类与网盘同步

本文记录一次绿联 NAS “疑似机械硬盘无法休眠，同时风扇周期性高速运转”的真实排查。近期变量包括新增照片、短暂开启后关闭相册智能分类，以及新增共享文件夹到阿里云盘的自动同步任务。

最终最重要的经验是：**风扇高速运转不等于机械硬盘没有休眠**。CPU 高温、内存压力、SSD 活动和机械盘活动必须分别验证。

## 初始现象

任务管理器曾显示：

- CPU 利用率约 `85%`；
- CPU 温度约 `83°C`；
- 内存占用约 `88%`；
- 机械盘有间歇读取；
- 风扇随后明显升速。

如果只听声音，很容易把风扇噪声误认为机械盘一直旋转。

## 第一条问题：Chromium renderer 失控

按 CPU 排序后发现一个 Chromium renderer 异常占用：

```text
CPU        约 43%
内存       约 68%
持续时间   约 2 天
```

查看 cgroup 后确认它属于 `linuxserver_chromium-1`：

```bash
for p in $(pgrep -x chromium); do
  echo "--- PID $p ---"
  ps -p "$p" -o pid,ppid,user,%cpu,%mem,etime,args
  printf 'cgroup: '
  tr '\n' ' ' < "/proc/$p/cgroup" 2>/dev/null
  echo
done
```

异常进程是一个定时刷新的网页标签。关闭该页面后，全部 Chromium 进程退出，内存从：

```text
已用 7.3 GiB，可用 171 MiB
```

恢复为：

```text
已用 2.5 GiB，可用 5.0 GiB
```

因此，风扇高转的直接原因是网页 renderer 持续占用 CPU 和约 5 GiB 内存，而不是相册或网盘任务。

可随时复查：

```bash
ps -C chromium \
  -o pid,ppid,%cpu,%mem,rss,etime,cmd \
  --sort=-%cpu | head -15

free -h
```

必要时可重启容器清理异常 renderer：

```bash
sudo docker restart linuxserver_chromium-1
```

宿主机的 `/config` 挂载不会因重启容器而删除。

## 第二条问题：Swap 是否会唤醒机械盘

高内存占用时系统使用了约 2.3 GiB Swap，因此需要确认 Swap 位于哪块设备：

```bash
cat /proc/swaps
lsblk -o NAME,TYPE,FSTYPE,SIZE,MOUNTPOINTS
findmnt /volume1
```

实际环境中：

- `/dev/zram0` 至 `/dev/zram3` 是压缩内存 Swap；
- `/dev/mmcblk0p5` 是 NAS 内置系统闪存上的 Swap；
- 机械盘是 `/dev/sda`，组成 `/volume1`；
- SSD 是 `/dev/nvme0n1`，组成 `/volume2`。

所以 Chromium 引起的 Swap 不会直接访问机械盘。它会造成 CPU 高温和风扇噪声，但不能据此认定 `/dev/sda` 没有休眠。

## 相册智能分类是否仍在后台运行

先比较相册、数据库和网盘进程的真实块设备 I/O：

```bash
sudo pidstat -d \
  -p "$(pgrep -d, -f 'photo_serv|cloud_serv|syncbackup_serv|postgres')" \
  1 20
```

排查时，相册相关进程大部分时间为 `0 KB/s`，偶尔只有约 `8–12 KB/s`。日志中也没有出现持续的人脸识别、分类、推理或模型任务；出现的主要是：

```text
/photo/auth/transcode/getPathPermission
```

这更像相册客户端请求转码路径或新增照片后的普通处理，不能证明智能分类模型仍在运行。

新增照片本身仍可能触发短期缩略图、索引和数据库更新。判断模型是否残留不能只看 `photo_serv` 是否存在，因为它也是相册核心服务。

可针对模型关键词检查近期日志：

```bash
sudo journalctl --since '24 hours ago' --no-pager |
  grep -Ei 'photo_serv.*(model|face|recogn|classif|cluster|embedding|detect|infer|ai|task|job|scan)' |
  tail -150
```

## 网盘同步显示完成后是否仍扫描

日志中 `syncbackup_serv` 多次明确显示：

```text
task is idle
```

`cloud_serv` 曾出现一秒约 `2 MB/s` 的读取峰值，但进一步检查发现其常驻文件全部位于 SSD：

```text
/volume2/@appstore/com.ugreen.netdisk/sbin/cloud_serv
/volume2/@appstore/com.ugreen.netdisk/db/net_disk.db
/volume2/@appstore/com.ugreen.netdisk/db/net_disk.db-wal
```

15 秒实时路径跟踪也没有捕获到 `/volume1`。因此这次读取峰值更可能来自 SSD 上的程序或数据库，暂时没有证据证明它在持续扫描机械盘上的共享文件夹。

检查长期打开的文件：

```bash
sudo lsof -p "$(pgrep -x cloud_serv)" 2>/dev/null |
  grep -E '/volume1/|/volume2/' |
  head -100
```

如果系统提供 `strace`，可短时捕获实时访问路径：

```bash
sudo timeout 15 strace -f -tt \
  -e trace=openat,newfstatat,statx,getdents64 \
  -p "$(pgrep -x cloud_serv)" 2>&1 |
  grep -E '/volume1/|/volume2/' |
  tail -100
```

## 采样时还要排除正常使用

一次采样中 `video_serv` 持续读取，日志显示 Android TV 正在播放 NAS 视频并每隔约 5 秒上报播放进度。它能解释当时的机械盘读取，但属于用户主动播放，不能用来判断空闲时的休眠故障。

因此，正式测试休眠前需要停止：

- 电视或手机端的视频播放；
- 文件复制、下载和备份；
- 正在浏览大量照片的相册客户端；
- 会定时刷新的远程 Chromium 网页。

## 正确判断机械盘是否休眠

停止正常读盘活动并等待系统设定的休眠时间后，检查 `/dev/sda`：

```bash
sudo smartctl -n standby /dev/sda
```

没有 `smartctl` 时可使用：

```bash
sudo hdparm -C /dev/sda
```

- `STANDBY`：机械盘已经休眠；如果仍然很吵，应检查 CPU 温度和风扇。
- `ACTIVE or IDLE`：机械盘仍处于工作状态，需要继续抓周期 I/O。

抓取两分钟内真正发生 I/O 的进程：

```bash
sudo timeout 120 iotop -botqqq -d 2 -o
```

如果系统没有 `iotop`，不要为了单次排查随意安装，可以继续使用 `pidstat` 对可疑进程分别采样。

## 本次结论

1. 风扇高速运转已经确认由 LinuxServer Chromium 中失控的定时刷新网页 renderer 引起。
2. Chromium 配置在 SSD，Swap 位于 zram 和系统闪存，因此没有证据表明它直接阻止机械盘休眠。
3. 相册智能分类没有发现持续运行的模型任务；新增照片可能带来短期普通索引。
4. 网盘同步任务显示空闲，`cloud_serv` 常驻文件位于 SSD，暂未捕获到它持续访问 `/volume1`。
5. 判断机械盘休眠必须在停止电视播放后直接检查 `/dev/sda` 的电源状态，不能仅凭风扇声音判断。

