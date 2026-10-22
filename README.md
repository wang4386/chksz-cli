# chksz — ChKSz API 交互式音乐下载脚本

根据 [ChKSz/CDown](https://github.com/ChKSz/CDown) (PyQt6 网易云音乐下载器)
重构的纯 Shell 交互式版本，专为 SSH 终端 / 服务器环境设计，无需图形界面。

## 重要: API 已迁移

- CDown 文档中的旧域名 `api.chksz.top` **已停止服务**。
- 新地址: `https://api.chksz.com`。
- 新版所有 `163_*` 接口(搜索/解析/歌词/歌单)**均需 `apikey` 参数**，
  未携带返回 `401 缺少 apikey 参数`。Key 在 https://api.chksz.com 登录后获取。

## 功能

| 需求 | 实现 |
|---|---|
| 交互式搜索下载歌曲 | 菜单 1 / `chksz search "关键词"`，序号多选 `1 3 5-8` / `all` |
| 解析歌单 | 菜单 2 / `chksz playlist <ID或链接>`，批量下载 |
| 设定下载位置 | 菜单 4 / `chksz dir <路径>`，持久化 |
| 依赖安装 | 菜单 5 / `chksz deps`，自动识别 apt/dnf/yum/apk/pacman/pkg/brew |
| 音质依次回退 | `jymaster → hires → lossless → exhigh → standard`，从首选音质开始向下试 |
| 快捷命令 `chksz` | `chksz install` 安装到 `~/.local/bin` 并配置 PATH |
| Key 持久化 | 菜单 4 / `chksz key <apikey>`，保存到 `~/.config/chksz/config` (600 权限)，设置时自动校验 |
| 下载记录 | 每次成功下载自动记入 `~/.config/chksz/history.tsv`（时间/歌曲 ID/歌名/歌手/专辑/实际音质/文件路径/.lrc 路径/下载时歌词状态），不含 API Key |
| 歌词检测/修复 | 菜单 9 / `chksz check-lyrics`，按下载记录扫描已下载歌曲，实测文件里的歌词嵌入状态，发现缺失时可询问修复或用 `--fix` 自动修复 |

附加: 断点续传、歌词 `.lrc` 落盘、元数据嵌入(可选)、文件名清洗与重名自动编号。

## 元数据嵌入 (免网络刮削)

与原版 CDown 一致，下载完成后自动把以下信息写入音频文件，
本地播放器 (Foobar2000 / MusicBee / 海贝 / 网易云本地导入等) 无需联网刮削：

| 内容 | MP3 | FLAC |
|---|---|---|
| 标题/歌手/专辑 | ID3 TIT2/TPE1/TALB | Vorbis Comment |
| 封面 | APIC 内嵌 | PICTURE 内嵌 |
| 歌词(去时间轴纯文本) | 标准 **USLT** 帧 | **LYRICS** 字段 |

实现优先级: `python3 + mutagen` (标准帧) > `ffmpeg` (封面+标签; 歌词只能进 TXXX，
部分播放器不识别) > 跳过。`chksz deps` 可一键安装 mutagen。
歌词原文 `.lrc` 文件也会一并保存 (可用设置关闭)。

## 下载记录与歌词检测/修复 (v1.1.0)

- 每次成功下载都会写一条记录到 `~/.config/chksz/history.tsv`，字段为时间、歌曲 ID、
  歌名、歌手、专辑、实际音质、文件路径、`.lrc` 路径、下载时歌词状态
  （`ok` / `partial` / `failed` / `no-lyric` / `skipped`）。历史是日志，修复后不会改写，
  当前状态以检测实测为准。
- 检测标准：MP3 看标准 USLT 帧（非空才算成功），FLAC 看 LYRICS 字段。
  旧版 ffmpeg 遗留的 TXXX 歌词不算成功，只算“非标准帧”，修复时会换成标准帧。
- 修复只动歌词：MP3 删旧 USLT/歌词类 TXXX 后加 USLT，FLAC 只写 LYRICS，
  封面、标题/歌手/专辑等其他标签原样保留。
- 歌词来源优先级：同名 `.lrc`（离线最可靠）> 按下载记录/ `--id` 给出的歌曲 ID
  走 API 取歌词。既无同名 `.lrc` 又找不到 ID 时无法修复，会提示手动放同名 `.lrc`
  或用 `--id` 指定。
- 检测/修复都需要 `python3 + mutagen`（`chksz deps` 可装）；没有它会直接提示，
  不会误报。

```bash
chksz history                 # 最近 50 条记录
chksz history all             # 全部记录
chksz check-lyrics            # 扫描全部下载记录, 发现缺失时询问是否修复
chksz check-lyrics --fix      # 扫描并自动修复全部缺失/非标准帧
chksz check-lyrics ~/Music/xx.mp3        # 只检测单个文件
chksz fix-lyrics ~/Music/xx.mp3          # 修复单个文件
chksz fix-lyrics ~/Music/xx.mp3 --id 123456
chksz fix-lyrics --all         # 等同于 check-lyrics --fix
```

## 在服务器上安装 (SSH)

```bash
# 一键安装 (推荐)
curl -fsSL https://raw.githubusercontent.com/wang4386/chksz-cli/main/install.sh | bash
source ~/.bashrc   # 或重新登录

# 安装依赖
chksz deps

# 设置 Key 与下载目录
chksz key <你的apikey>
chksz dir ~/Music

# 进入交互菜单
chksz
```

手动安装:

```bash
scp chksz user@host:/tmp/chksz
ssh user@host
chmod +x /tmp/chksz && /tmp/chksz install
source ~/.bashrc
```

也可以用同目录的 `install.sh` 一键安装:
```bash
./install.sh            # 使用同目录的 chksz 文件
```

## 命令行用法

```
chksz                          进入交互菜单
chksz search "七里香"           搜索并选择下载
chksz playlist 5202687076      解析歌单批量下载 (也支持完整链接)
chksz song 1315196858          直接下载单曲
chksz key <apikey>             设置 API Key
chksz dir ~/Music              设置下载目录
chksz quality lossless         设置首选音质
chksz deps / install / config  依赖安装 / 安装快捷命令 / 查看配置
chksz history [N|all]        查看下载记录 (默认最近 50 条)
chksz check-lyrics [--fix] [文件]  检测歌词嵌入, --fix 自动修复
chksz fix-lyrics <文件> [--id ID] / fix-lyrics --all  修复歌词嵌入
chksz uninstall              安全卸载：删除脚本、配置 (含下载记录) / 快捷命令，
                             依赖逐个询问（默认不删），歌曲文件默认保留
```

## 配置文件

`~/.config/chksz/config` (权限 600):

```
APIKEY="..."
SAVE_DIR="/root/Music/chksz"
QUALITY="jymaster"
SAVE_LRC="1"
EMBED_META="1"
```

下载记录在 `~/.config/chksz/history.tsv`（TSV，空字段用 `-` 占位），卸载时会随配置目录一起删除。

## 音质说明

| level | 名称 | 格式 |
|---|---|---|
| jymaster | 超清母带 | FLAC |
| hires | Hi-Res | FLAC 24bit |
| lossless | 无损 | FLAC |
| exhigh | 极高 | MP3 320k |
| standard | 标准 | MP3 128k |

解析时从首选音质开始逐级回退；若 API 实际返回更低音质会在输出中提示。
SVIP 相关高音质取决于 Key 背后账号权限，无权限会自动降级。

## 许可证

仅供学习交流，请勿用于商业用途。音乐版权归网易云音乐及版权方所有。
