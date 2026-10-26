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
chksz uninstall             # 安全卸载：删脚本/配置（含下载记录）/快捷命令，依赖逐个询问（默认不删），歌曲默认保留
chksz history [N|all]       # 查看下载记录（默认最近 50 条）
chksz check-update          # 检查更新（只报告版本对比，不改动）
chksz update [--force]      # 更新脚本本身（见下，代跑前先向用户确认）
chksz check-lyrics [--fix] [文件]  # 检测歌词嵌入：无参数扫描全部下载记录；--fix 自动修复
chksz fix-lyrics <文件> [--id ID]  # 修复单个文件；fix-lyrics --all 修复记录中全部缺失项
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

- 下载记录在 `~/.config/chksz/history.tsv`（TSV，不含 API Key），每次成功下载写一条：
  时间、歌曲 ID、歌名、歌手、专辑、实际音质、文件路径、`.lrc` 路径、下载时歌词状态
  （`ok` / `partial` / `failed` / `no-lyric` / `skipped`）。历史是日志，修复后不改写；
  当前嵌入状态以 `check-lyrics` 实测为准。卸载时会随配置目录一起删除。

- `APIKEY` 是 ChKSz API 的个人密钥，在 https://api.chksz.com 登录后获取。所有 `163_*` 接口都必须带 `apikey` 参数，否则返回 401。不要在对话里索取或复述 Key，用 `chksz key` 让用户自己设置。

## 音质与回退

- 音质从高到低是 `jymaster`（超清母带 FLAC）、`hires`（Hi-Res FLAC）、`lossless`（无损 FLAC）、`exhigh`（极高 MP3 320k）、`standard`（标准 MP3 128k）。

- 解析时从首选音质开始逐级向下回退，第一个返回有效 URL 的音质即被采用。API 也可能在服务端降级（例如请求 `hires` 实际返回 `lossless`），脚本会如实提示实际音质。读返回 JSON 的 `data.level` 字段可以确认实际音质。

## 下载产物

- 文件名格式为 `歌手 - 歌名.扩展名`，非法字符替换为下划线。下载支持断点续传（`.downloading` 临时文件）。

- 检查更新/自更新（v1.3.0）：更新源是 GitHub 仓库的 `chksz` 原文件，
  环境变量 `CHKSZ_RAW_URL` 可覆盖（与 install.sh 同一约定）。
  `chksz update` 非交互运行时不询问、直接更新——命令本身即确认，
  所以 agent 代跑前必须先向用户说明并得到同意，不要自行升级用户机器上的脚本。
  更新会先下载到同目录临时文件并校验（非空/bash shebang/有版本号/`bash -n` 通过），
  默认不降级、不重装同版本（`--force` 才允许）；替换前自动备份到脚本旁的
  `chksz.bak`，替换后跑新版 `version` 复核，失败自动回滚。
  脚本不做启动时自动检查，日常命令不联网检查更新。

- 同名文件处理（v1.2.0）：解析成功、下载之前，若下载目录已有同名文件，
  有 TTY 时询问 `1 覆盖 / 2 创建副本（默认）/ 3 跳过`；无 TTY 时默认创建副本，
  绝不默认覆盖。agent 非交互调用会走默认副本，旧文件不会被动。
  覆盖时旧同名 `.lrc` 会被清掉（防新歌无歌词时残留旧歌词），
  且 `history.tsv` 中该路径的旧记录会被新记录替换；副本走新路径，记录另加一条。
  跳过时 `download_song` 返回 3，搜索/歌单统计单列跳过数，`chksz song` 跳过后正常返回 0。

- 开启 `EMBED_META` 时自动嵌入元数据，播放器无需联网刮削。优先 `python3 + mutagen`：MP3 写入标准 USLT 歌词帧（去时间轴纯文本）、APIC 封面、TIT2/TPE1/TALB 标签；FLAC 写入 LYRICS 字段、内嵌封面、Vorbis 标签。没有 mutagen 时回退到 `ffmpeg`（封面加基础标签，歌词只能进 TXXX）。

- 歌词原文同时保存为同名的 `.lrc` 文件（`SAVE_LRC=0` 可关闭）。

- 歌词检测/修复（v1.1.0，需 `python3 + mutagen`，`chksz deps` 可装）：
  检测标准是 MP3 的标准 USLT 帧（非空才算）、FLAC 的 LYRICS 字段；
  旧版 ffmpeg 遗留的 TXXX 歌词只算 partial，不算成功。
  修复只动歌词（MP3 删旧 USLT/歌词类 TXXX 后加 USLT，FLAC 只写 LYRICS），
  封面和标题/歌手/专辑原样保留。
  歌词来源优先级：同名 `.lrc` > 按记录/`--id` 的歌曲 ID 走 API 取歌词；
  既无 `.lrc` 又无 ID 时无法修复（纯音乐/接口无歌词会报 `no-lyric`，不是失败）。
  非交互场景用 `check-lyrics --fix` 或 `fix-lyrics --all`，不要等交互询问。

## 注意事项

- 下载是真实的写操作，会产生音频文件和网络流量。批量下载歌单前先向用户确认曲目数量和预计体积。

- 旧域名 `api.chksz.top` 已停止服务，不要使用。所有接口走 `https://api.chksz.com/api`。

- 高音质取决于 Key 背后账号的 SVIP 权限，无权限会自动降级，这是正常行为不是故障。

- 已验证过的内容：搜索、歌单解析、单曲解析、歌词获取、四档音质解析、jymaster 真实返回 FLAC 24bit/192kHz、下载、断点续传、歌词落盘、mutagen USLT/APIC 嵌入、假 Key 401 拒绝、一键安装直链。均在 2026-10-19 用真实 Key 测过。

## Available connectors

- [Chksz](~/workspace/custom-connectors/custom.chksz/CONNECTOR.md) for 直接调用 ChKSz API（搜索、解析、歌词、歌单），不经过 CLI。

- Use `muse.connector_search` to find other connectors and `muse.skill_search` to find related skills.
