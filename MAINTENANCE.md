# chksz-cli 长期维护文档（AI 接手手册）

本文档面向后续接手本项目的 AI（或人类维护者），记录架构、契约、踩过的坑和发布流程。
用户向说明见 `README.md`，agent 操作命令速查见 `SKILL.md`，本文档只讲「怎么安全地改这个项目」。

## 1. 项目速览

- `chksz` 是一个单文件 Bash 脚本（约 1600 行），通过 ChKSz API 下载网易云音乐，由 PyQt6 GUI 项目 [ChKSz/CDown](https://github.com/ChKSz/CDown) 重构而来，面向 SSH 终端和无图形界面的服务器。
- 仓库文件只有五个：`chksz`（主脚本）、`install.sh`（一键安装）、`README.md`、`SKILL.md`、本文件。没有构建步骤，没有测试框架，脚本本身就是交付物。
- 运行时依赖：必需 `curl` + `jq`；可选 `ffmpeg`、`python3 + mutagen`（元数据嵌入）。
- 用户数据全部在 `~/.config/chksz/`：`config`（设置，600 权限）和 `history.tsv`（下载记录）。

## 2. 版本现状（接手必读）

- 本地主本与 GitHub `wang4386/chksz-cli` 的 `main` 均为 **1.3.4**（2026-11-04 同步；1.3.2 commit `3ca9fab`，1.3.3 commit `384f6df`）。
- 后续推送与否仍由用户决定，不要默认已推送。推送方式见第 9 节。
- 脚本内置自更新（`chksz update`）拉的是 GitHub `main` 上的 `chksz` 原始文件，用户端现可自更新到 1.3.2。

## 3. 代码地图（按脚本内出现顺序）

| 区域 | 主要函数 | 职责 |
|---|---|---|
| 基础输出 | `info/ok/warn/err/hr/pause` | 彩色日志；非 TTY 自动去色 |
| 配置 | `load_config/save_config/show_config` | 配置读写，见第 4.1 节契约 |
| 音质 | `fallback_levels` | 从首选音质起生成回退序列 |
| API 层 | `api_get/api_code/check_api_resp` | 统一带 `apikey` 请求；401 单独提示 |
| 工具 | `sanitize/fmt_duration/unique_path/resolve_download_target/expand_selection` | 文件名清洗、时长格式化、重名与同名冲突处理、序号表达式展开 |
| 下载核心 | `download_song` | 解析（回退链）→ 下载（断点续传）→ 歌词 → 嵌入 → 记账 |
| 元数据嵌入 | `embed_metadata` | 封面/标签/歌词嵌入，见第 6 节 |
| 下载记录 | `escape_tsv/record_download/history_id_for_file/show_history/remove_history_for_file` | history.tsv 读写，见第 4.2 节 |
| 歌词检测修复 | `lyric_check_status/lrc_to_plain/embed_lyrics_only/fix_one_file/check_lyrics_cmd/fix_lyrics_cmd` | 检测标准歌词帧并修复 |
| 业务入口 | `do_search/do_playlist/do_song` | 搜索、歌单、单曲三条主流程 |
| 设置 | `set_apikey/set_savedir/set_quality/settings_menu` | Key 设置时自动用歌词接口验活（非 401 即有效） |
| 依赖 | `detect_pm/pkg_install/pkg_name/install_deps` | 跨发行版包管理抽象，见第 7 节 |
| 安装/卸载 | `install_shortcut/uninstall` | 快捷命令与安全卸载 |
| 自更新 | `extract_version/version_newer/check_update/update_self/update_menu` | 拉远程脚本比对 VERSION 后安全替换 |
| 界面 | `banner/main_menu/usage/main` | 交互菜单与子命令分发在 `main()` |

## 4. 核心契约（改动时不可破坏）

### 4.1 配置文件

- 路径 `~/.config/chksz/config`，格式 `KEY="value"`，权限 600。
- 五个键：`APIKEY`、`SAVE_DIR`、`QUALITY`、`SAVE_LRC`（0/1）、`EMBED_META`（0/1）。
- `load_config` 只按白名单逐行读取，**禁止改成 `source` 整个文件**（防注入，历史上就是为此这么写的）。

### 4.2 history.tsv

- 制表符分隔，表头 `#time id title artist album level file lrc lyric_status`，字段顺序被 `history_id_for_file`（按 $7 取 file、$2 取 id）和 `show_history` 依赖，**不要增删或调换列**。
- 空字段必须用 `-` 占位：bash 的 `read` 会吞掉空字段导致整行错位，所以 `record_download` 对每个可能为空的字段都做了占位处理，新增字段时照此办理。
- `escape_tsv` 把字段内的 tab/换行/回车替换为空格，写记录前必须过一遍。
- 覆盖下载同一文件时先 `remove_history_for_file` 删旧记录再记新账，避免一个文件多条记录。

### 4.3 嵌入状态 EMBED_STATUS

- `embed_metadata` 返回值恒为 0（嵌入失败不让下载失败），结果写全局变量 `EMBED_STATUS`，取值：`ok`（歌词已入标准帧）、`partial`（仅 ffmpeg 标签/封面）、`no-lyric`（无歌词可嵌）、`failed`。
- `download_song` 把它写进 history 的 `lyric_status` 列；`check-lyrics` 的判定与之对应。改嵌入逻辑时同步维护这组取值。

### 4.4 歌词检测状态

- `lyric_check_status` 输出单一状态词：`ok`（有非空 USLT/LYRICS）、`partial`（只有 TXXX 伪歌词帧）、`missing`、`missing-file`、`no-tool`（无 mutagen）、`unsupported`、`error`。`fix_one_file` 按此状态机分支，改检测逻辑先看它。

### 4.5 其他不变量

- 所有交互输入一律从 `/dev/tty` 读，不读 stdin。这样管道喂数据不会误触发交互；agent 自动化时需用 `script -qec` 提供伪终端。
- 下载先落 `.downloading` 临时文件，`curl -C -` 断点续传，成功后 `mv` 成正式文件，不要改成直写目标文件。
- 文件名规则：`歌手 - 歌名.扩展名`，`sanitize` 把 `/\:*?"<>|` 换成 `_` 并截断 100 字符；扩展名由实际音质决定（jymaster/hires/lossless → flac，exhigh/standard → mp3），不要按请求音质写死。
- 更新源约定：`chksz` 的 `UPDATE_URL` 与 `install.sh` 的默认值都取环境变量 `CHKSZ_RAW_URL`，缺省指向 GitHub 仓库 raw 地址，改一处必须同步另一处。下载统一走回退逻辑（chksz 内为 `fetch_update_script`，install.sh 内联同逻辑）：直连失败时经加速源 `GH_PROXY`（默认 `https://gh.qninq.cn`，环境变量 `CHKSZ_GH_PROXY` 覆盖、设空禁用）以「代理前缀 + 原始 URL」重试一次；改回退逻辑时两处仍须同步。

## 5. API 事实（https://api.chksz.com）

- 旧域名 `api.chksz.top` 已停服，返回弃用页，不要再引用。
- 全部 `163_*` 接口必带 `apikey` 查询参数。无参返回 `401 缺少 apikey 参数`；错参返回 `401 apikey 无效或已失效`。
- 端点：`163_search`（keyword/limit/offset）、`163_music`（id/level/type=json，返回 `data.url/level/br/size` 等）、`163_lyric`（id，返回 `data.lrc/tlyric` 等）、`163_playlist`（id，返回 `data.tracks[]`，每项含 `ar[].name`、`al.name/picUrl`）。
- 服务端会自行降级音质：请求 `hires` 可能实际返回 `lossless`。判断实际音质一律读返回的 `data.level`，脚本已按此显示和记账。
- 高音质取决于 Key 背后账号的 SVIP；`jymaster` 实测可达 FLAC 24bit/192kHz。
- 搜索接口偶发空响应或连接失败，`api_get` 已带 `--retry 2`；再失败就提示用户重试，不要在脚本里加无限重试。
- 本环境（Muse 侧）调用该 API 走 `custom.chksz` 连接器，测试助手在 `~/workspace/custom-connectors/custom.chksz/bin/chksz_api.py`（经凭证替身注入 Key，密钥永不落盘）。

## 6. 元数据嵌入设计

- 两条路径，优先级固定：`python3 + mutagen` > `ffmpeg` > 跳过。
- 只有 mutagen 能写标准歌词帧：MP3 用 ID3 `USLT`（去时间轴纯文本，同原版 CDown 的 `parse_lrc_to_uslt`），FLAC 用 Vorbis `LYRICS` 字段；封面分别用 `APIC` / `PICTURE`。
- ffmpeg 只能写封面和标题/歌手/专辑，其歌词会落到 `TXXX:USLT` 非标准帧，多数播放器不认。不要试图用 ffmpeg「修复」歌词，那正是 `partial` 状态存在的原因。
- 封面拉取失败不应连坐：mutagen 路径无封面时照常嵌歌词和标签；ffmpeg 路径无封面时照常写标签（1.3.1 修复，旧版此处会整体放弃）。
- 封面临时文件用无后缀 `mktemp`：busybox/Alpine/macOS 的 mktemp 不支持 `--suffix`，会静默失败（1.3.1 修复）。扩展名对识别无影响。
- 歌词原文除嵌入外还落盘同名 `.lrc`（`SAVE_LRC` 控制），它是 `fix-lyrics` 的第一歌词来源，不要取消。

## 7. 依赖与跨发行版

- `pkg_install` 是唯一的装包入口（自动识别 apt-get/dnf/yum/apk/pacman/pkg/brew 与 sudo，apt 只在首次调用时 update）。
- 包名差异走 `pkg_name` 映射：Alpine 的 pip 是 `py3-pip`，Arch 的 python 是 `python`、pip 是 `python-pip`，Termux 与 brew 的 python 自带 pip。新增系统包时先在这里加映射，不要在业务代码里写 `case`。
- mutagen 用 pip 装：先 `--user`，失败再 `--break-system-packages`（应对 PEP 668 的 externally-managed 拦截）。pip 或 python3 缺失时由 `install_deps` 自动补装，不要退回「提示用户手动装」。
- 体积参考（Ubuntu 24.04 实测）：curl 0.5MB、jq 0.1MB、ffmpeg 约 45MB（含编解码库）、mutagen 1.6MB。用户对磁盘敏感，最小完整方案是 curl+jq+mutagen 约 2.2MB。

## 8. 已知问题与陷阱

- 用户机器缺 mutagen/ffmpeg 时，下载会提示跳过元数据嵌入；排查第一步用 `chksz deps` 检查工具状态。
- `chksz deps` 里 ffmpeg 与 mutagen 都是 opt-in 询问，小磁盘机器常被跳过；沟通时先确认这两项。
- 封面 MIME 必须由图片字节签名识别，不得从 URL 后缀推断或固定写成 JPEG；无效/HTML 响应须跳过封面并继续写标签/歌词。
- 下载和 fix-lyrics 必须共用 `lrc_text_to_plain`，覆盖重复时间戳、增强 LRC 行内时间标记以及与时间戳相邻的 LRC 元数据。
- ffmpeg 回退结果：MP3 歌词是非标准 TXXX:USLT（partial）；FLAC `lyrics` Vorbis Comment 可被 Mutagen 检出为标准字段。提示与 history 状态应保持一致。
- 歌单接口对超大歌单一次返回全部 tracks，没有分页处理；上千首的歌单会慢且吃内存，目前接受此限制。
- `do_song` 按 ID 直下时拿不到歌名/歌手信息，文件名退化为歌曲 ID，这是接口限制（歌词接口不返回元信息），不是 bug。
- 卸载只清理本脚本写过的东西：`~/.local/bin/chksz`、配置目录、`.bashrc` 里带 `# chksz 快捷命令` 注释的那组 PATH 行。用户自己写的同名 PATH 行不在清理范围，实现上靠注释行锚定，不要改成按 export 行全文匹配删除。

## 9. 发布流程

1. 改版本号：脚本头 `VERSION` 常量，遵循语义化（修复 patch、功能 minor）。
2. 同步文档：功能变化改 `README.md`（用户向）和 `SKILL.md`（agent 操作）；架构、契约、坑点变化改本文件。
3. 本地自测：至少 `bash -n chksz`，再按第 10 节跑相关路径。
4. 推送 GitHub（经用户确认后）：本维护环境用 GitHub 连接器的快照推送（`github push-files`，源目录 `~/workspace/chksz-cli`，NUL 分隔的路径清单在源目录外），推送成功后把 `{owner, repo, branch, source_dir, commit_sha, paths}` 追加到 `~/workspace/chksz-cli.muse-github-snapshot-sync.json`。无此环境的维护者用普通 git 提交推送即可。
5. 推送后验证 raw 直链可达：`https://raw.githubusercontent.com/wang4386/chksz-cli/main/chksz`，这同时是用户端自更新的来源。

## 10. 测试方法

- 语法门：`bash -n chksz`，有 shellcheck 时再跑一遍。
- 无真实 Key 的端到端测试法（本维护环境专用）：复制脚本为测试副本，把副本里 `api_get` 的 curl 行替换为调用 `~/workspace/custom-connectors/custom.chksz/bin/chksz_api.py "$endpoint" "$@"`，再用测试用 `XDG_CONFIG_HOME` 跑流程；交互步骤用 `printf '1\n' | script -qec "..." /dev/null` 喂输入。
- 嵌入验证：下载后用 `python3 -c` + mutagen 读帧（数 USLT/APIC 个数），或 `ffprobe` 看 mjpeg 流与 format_tags。只看脚本输出的「已嵌入」字样不算验证通过。
- 嵌入回归至少覆盖：Mutagen MP3/FLAC + PNG/JPEG、Mutagen + 无效图片响应、ffmpeg MP3 TXXX 与 FLAC LYRICS、ffmpeg 封面写入失败回退、普通/重复/增强 LRC 清理。测试需检查实际帧/字段，不只看日志。
- 卸载测试必须在沙盒 HOME 里做（`HOME=/tmp/fakehomeN`），不要在真实 HOME 里试。

## 11. 变更日志

| 版本 | 日期 | 内容 |
|---|---|---|
| 1.0.0 | 2026-10-19 | 首发：搜索/歌单/单曲下载、音质回退、配置持久化、依赖安装、快捷命令、安全卸载、mutagen 标准帧嵌入。已推送 GitHub |
| 1.1.0 | 2026-10-23 | 下载记录 history.tsv；`check-lyrics` / `fix-lyrics` 检测与修复歌词嵌入。2026-11-04 已推送 |
| 1.2.x | 2026-10 下旬 | 同名文件覆盖/副本/跳过询问等下载细节完善。2026-11-04 已推送 |
| 1.3.0 | 2026-10 下旬 | `check-update` / `update` 自更新（校验远程脚本后安全替换）。2026-11-04 已推送 |
| 1.3.1 | 2026-11-04 | 修复 ffmpeg 路径封面失败连坐放弃嵌入；封面 mktemp 去 `--suffix` 兼容 busybox/macOS。2026-11-04 已推送 |
| 1.3.2 | 2026-11-04 | 全量审核修复四处：卸载删歌目录先规范化路径再校验（拒 `HOME/` 尾斜杠、相对路径、一级绝对路径）；下载歌词剥时间戳改为重复剥离（多时间戳行不残留）；配置读取容忍 CRLF；API 空响应给明确提示。审核记录在 QA 副本 REVIEW.md。2026-11-04 已推送 |
| 1.3.3 | 2026-11-04 | 封面按文件签名识别 MIME、拒绝无效图片响应且不误报嵌入；下载/修复共用 LRC 清理（含增强时间戳）；ffmpeg 回退写入歌词并区分 MP3 非标准 TXXX 与 FLAC LYRICS 状态。已推送 (commit 384f6df) |
| 1.3.4 | 2026-11-04 | 更新下载增加 GitHub 加速源回退：直连 raw 失败时自动经 gh.qninq.cn 代理重试 (chksz 的 check-update/update 与 install.sh 同步)，可用 CHKSZ_GH_PROXY 覆盖、设空禁用。已推送 |
