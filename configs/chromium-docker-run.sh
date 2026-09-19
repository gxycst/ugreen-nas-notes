#!/bin/sh
set -eu

# Run this on the NAS over SSH. Review paths and ports before use.
docker run -d \
  --name linuxserver_chromium-1 \
  --restart unless-stopped \
  --shm-size="1gb" \
  -e PUID=1000 \
  -e PGID=10 \
  -e TZ=Asia/Shanghai \
  -e TITLE=Chromium \
  -e LANG=zh_CN.UTF-8 \
  -e LANGUAGE=zh_CN:zh \
  -e LC_ALL=zh_CN.UTF-8 \
  -e 'CHROME_CLI=--lang=zh-CN --proxy-server=socks5://192.168.31.192:34421' \
  -e 'http_proxy=socks5://192.168.31.192:34421' \
  -e 'https_proxy=socks5://192.168.31.192:34421' \
  -e 'all_proxy=socks5://192.168.31.192:34421' \
  -p 44635:3000 \
  -p 38517:3001 \
  -v /volume1/docker/linuxserver_chromium-1/config:/config \
  linuxserver/chromium:latest

