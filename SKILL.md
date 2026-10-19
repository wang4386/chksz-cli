# chksz CLI 操作技能

- 这是 `chksz` 项目的 agent 操作手册。`chksz` 是一个纯 Bash 交互式音乐下载脚本，基于 ChKSz API 下载网易云音乐，由 [ChKSz/CDown](https://github.com/ChKSz/CDown)（PyQt6 GUI 版）重构而来，专为 SSH 终端和服务器环境设计。

- 仓库地址是 `https://github.com/wang4386/chksz-cli`。三个文件：`chksz`（主脚本，可执行）、`install.sh`（一键安装）、`README.md`（用户文档）。本文件是给 agent 看的操作指南。

## 安装

- 在目标机器上执行一键安装，把脚本装到 `~/.local/bin/chksz` 并配置 PATH。

```bash
curl -fsSL https://raw.githubusercontent.com/wang4386/chksz-cli/main/install.sh | bash
source ~/.bashrc
```

- 安装依赖。必需 `curl` 和 `jq`，可选 `ffmpeg`（封面嵌入回退方案）和 `python3 + mutagen`（标准歌词帧嵌入）。

```bash
chksz deps
```

## 非交互命令（agent 优先使用）

- 直接运行 `chksz` 会进入交互菜单，需要 TTY。agent 操作时一律使用下面的非交互子命令，不要进菜单。

```bash
chksz search "关键词"        # 搜索歌曲，输出编号列表（仍需交互选序号，见下）
chksz playlist <ID或链接>   # 解析歌单，输出歌曲列表（仍需交互确认，见下）
chksz song <歌曲ID>         # 直接下载单曲，无需交互
chksz key <apikey>          # 设置 API Key，自动校验有效性后保存
chksz dir <下载目录>        # 设置下载位置
chksz quality <音质>        # 设置首选音质：jymaster|hires|lossless|exhigh|standard
chksz config                # 查看当前配置（Key 打码显示）
chksz deps                  # 安装依赖
chksz install               # 安装 chksz 快捷命令
chksz help                  # 帮助
```

- `search` 和 `playlist` 的选择步骤从 `/dev/tty` 读输入，没有 TTY 时会失败。agent 需要走完整交互流程时，用 `script` 提供伪终端并通过管道喂输入。

```bash
printf '1\n' | script -qec "chksz search '海阔天空'" /dev/null
printf 'all\n' | script -qec "chksz playlist 5202687076" /dev/null
```

- 序号支持 `1 3 5-8` 和 `all` 两种写法。

## 配置

- 配置文件在 `~/.config/chksz/config`，权限 600，格式为 `KEY="value"`。五个键：`APIKEY`、`SAVE_DIR`、`QUALITY`、`SAVE_LRC`（1 保存 .lrc）、`EMBED_META`（1 嵌入元数据）。

- `APIKEY` 是 ChKSz API 的个人密钥，在 https://api.chksz.com 登录后获取。所有 `163_*` 接口都必须带 `apikey` 参数，否则返回 401。不要在对话里索取或复述 Key，用 `chksz key` 让用户自己设置。

## 音质与回退

- 音质从高到低是 `jymaster`（超清母带 FLAC）、`hires`（Hi-Res FLAC）、`lossless`（无损 FLAC）、`exhigh`（极高 MP3 320k）、`standard`（标准 MP3 128k）。

- 解析时从首选音质开始逐级向下回退，第一个返回有效 URL 的音质即被采用。API 也可能在服务端降级（例如请求 `hires` 实际返回 `lossless`），脚本会如实提示实际音质。读返回 JSON 的 `data.level` 字段可以确认实际音质。

## 下载产物

- 文件名格式为 `歌手 - 歌名.扩展名`，非法字符替换为下划线，重名自动加 `(2)` 编号。下载支持断点续传（`.downloading` 临时文件）。

- 开启 `EMBED_META` 时自动嵌入元数据，播放器无需联网刮削。优先 `python3 + mutagen`：MP3 写入标准 USLT 歌词帧（去时间轴纯文本）、APIC 封面、TIT2/TPE1/TALB 标签；FLAC 写入 LYRICS 字段、内嵌封面、Vorbis 标签。没有 mutagen 时回退到 `ffmpeg`（封面加基础标签，歌词只能进 TXXX）。

- 歌词原文同时保存为同名的 `.lrc` 文件（`SAVE_LRC=0` 可关闭）。

## 注意事项

- 下载是真实的写操作，会产生音频文件和网络流量。批量下载歌单前先向用户确认曲目数量和预计体积。

- 旧域名 `api.chksz.top` 已停止服务，不要使用。所有接口走 `https://api.chksz.com/api`。

- 高音质取决于 Key 背后账号的 SVIP 权限，无权限会自动降级，这是正常行为不是故障。

- 已验证过的内容：搜索、歌单解析、单曲解析、歌词获取、四档音质解析、jymaster 真实返回 FLAC 24bit/192kHz、下载、断点续传、歌词落盘、mutagen USLT/APIC 嵌入、假 Key 401 拒绝、一键安装直链。均在 2026-10-19 用真实 Key 测过。

## Available connectors

- [Chksz](~/workspace/custom-connectors/custom.chksz/CONNECTOR.md) for 直接调用 ChKSz API（搜索、解析、歌词、歌单），不经过 CLI。

- Use `muse.connector_search` to find other connectors and `muse.skill_search` to find related skills.
