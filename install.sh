#!/usr/bin/env bash
#
# chksz 一键安装脚本
# 用法:
#   ./install.sh                 # 使用同目录下的 chksz 文件安装
#   curl -fsSL <install.sh地址> | bash   # 远程安装 (需配合 CHKSZ_RAW_URL)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CHKSZ_RAW_URL="${CHKSZ_RAW_URL:-https://raw.githubusercontent.com/wang4386/chksz-cli/main/chksz}"
# GitHub 加速源: 直连下载失败时经此代理重试 (与 chksz 的 GH_PROXY 同一约定)。
# 可用环境变量 CHKSZ_GH_PROXY 覆盖, 设为空字符串则禁用加速回退。
CHKSZ_GH_PROXY="${CHKSZ_GH_PROXY-https://gh.qninq.cn}"
SRC_FILE=""
if [ -f "$SCRIPT_DIR/chksz" ]; then
  SRC_FILE="$SCRIPT_DIR/chksz"
else
  echo "[*] 从远程下载 chksz ..."
  tmp="$(mktemp)"
  if ! curl -fsSL "$CHKSZ_RAW_URL" -o "$tmp"; then
    if [ -n "$CHKSZ_GH_PROXY" ] && \
       curl -fsSL "${CHKSZ_GH_PROXY%/}/$CHKSZ_RAW_URL" -o "$tmp"; then
      echo "[*] 直连失败, 已通过加速源 $CHKSZ_GH_PROXY 下载"
    else
      echo "[✗] 下载失败 (直连与加速源均不可达): $CHKSZ_RAW_URL"
      rm -f "$tmp"
      exit 1
    fi
  fi
  SRC_FILE="$tmp"
fi

[ -f "$SRC_FILE" ] || { echo "[✗] 找不到 chksz 脚本: $SRC_FILE"; exit 1; }
bash -n "$SRC_FILE" || { echo "[✗] 脚本语法检查失败"; exit 1; }

mkdir -p "$HOME/.local/bin"
cp -f "$SRC_FILE" "$HOME/.local/bin/chksz"
chmod +x "$HOME/.local/bin/chksz"
echo "[✓] 已安装到 $HOME/.local/bin/chksz"

if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  {
    echo ''
    echo '# chksz 快捷命令'
    echo 'export PATH="$HOME/.local/bin:$PATH"'
  } >> "$HOME/.bashrc"
  echo "[!] 已将 ~/.local/bin 写入 ~/.bashrc, 请执行 source ~/.bashrc 或重新登录"
fi

export PATH="$HOME/.local/bin:$PATH"
echo "[✓] 安装完成, 输入 chksz 进入交互菜单"
