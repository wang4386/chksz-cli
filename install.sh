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
SRC_FILE=""
if [ -f "$SCRIPT_DIR/chksz" ]; then
  SRC_FILE="$SCRIPT_DIR/chksz"
else
  echo "[*] 从远程下载 chksz ..."
  tmp="$(mktemp)"
  curl -fsSL "$CHKSZ_RAW_URL" -o "$tmp"
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
