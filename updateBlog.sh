#!/usr/bin/env bash
set -euo pipefail

#
# update.sh - 自动化部署/更新脚本（安全保守型）
#
# 功能概述：
# - 在脚本所在仓库或指定仓库目录下执行 git fetch、checkout、reset，使工作树与远程分支一致。
# - 可选安装 Node 依赖并执行构建（如果仓库包含 package.json 且系统存在 npm）。
# - 可选重启服务：优先使用 pm2（通过环境变量 `PM2_APP_NAME` 指定应用名），
#   否则使用 systemd（通过环境变量 `SERVICE_NAME` 指定服务名）。
#
# 设计原则与安全说明：
# - 脚本使用 `set -euo pipefail` 开启严格模式，任何命令失败都会导致脚本退出，从而避免部分执行留下不一致状态。
# - 脚本尽量不执行来自外部的任意命令或参数；仅使用已定义的环境变量与固定子命令。
# - 在 CI / webhook 场景中，请确保限制触发来源并保护好执行该脚本账户的权限。
#
# 可配置环境变量（示例与含义）：
# - REPO_DIR        : 仓库根路径；默认 `scripts` 目录的上级（即项目根）。
# - BRANCH          : 要同步的分支，默认 `main`。
# - LOGFILE         : 日志文件路径，默认 `${SCRIPT_DIR}/update.log`。
# - PM2_APP_NAME    : 如果指定且系统存在 pm2，则尝试 pm2 reload/restart <PM2_APP_NAME>。默认值为 `ei`。
# - SERVICE_NAME    : 备用：如果指定且存在 systemctl，则尝试重启 systemd 服务。
#
# 使用示例：
#  # 在项目根通过默认参数运行
#  ./scripts/update.sh
#
#  # 指定仓库目录和分支并进行更新（示例）
#  REPO_DIR=/var/www/myapp BRANCH=release ./scripts/update.sh
#
#  # 与 pm2 配合：
#  PM2_APP_NAME=myapp ./scripts/update.sh
#
# 注意：在 Windows 环境下该脚本不可直接运行（bash 脚本）。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 待更新项目库所在文件夹（默认更新 /var/www/personBlogSite）
# 允许通过环境变量 REPO_DIR 覆盖
REPO_DIR="${REPO_DIR:-/var/www/personBlogSite}"

# 要更新的分支，默认 master BRANCH 覆盖
BRANCH="${BRANCH:-master}"

# 日志文件：默认写到脚本目录下；允许通过 LOGFILE 覆盖
LOGFILE="${LOGFILE:-${SCRIPT_DIR}/updateBlog.log}"

# 可选的服务控制参数：pm2 或 systemd
PM2_APP_NAME="${PM2_APP_NAME:-ei}"
SERVICE_NAME="${SERVICE_NAME:-}"

# 时间戳函数，统一日志时间格式
timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

# 简单日志函数：把消息写到 stdout 同时追加到日志文件
log() {
  echo "[$(timestamp)] $*" | tee -a "$LOGFILE"
}

# 错误退出函数：写错误到 stderr 并退出（供 trap 与手动调用）
fail() {
  echo "[$(timestamp)] ERROR: $*" | tee -a "$LOGFILE" >&2
  exit 1
}

# 捕获中断与终止信号，确保记录日志并以非零退出
trap 'fail "Script interrupted or failed"' INT TERM

# 开始记录基本信息，便于后续排查
log "=== updateBlog.sh start ==="
log "Script dir: $SCRIPT_DIR"
log "Repo dir: $REPO_DIR"
log "Branch: $BRANCH"
log "Logfile: $LOGFILE"

# 检查 git 是否可用（这是必须工具）
if ! command -v git >/dev/null 2>&1; then
  fail "git is not installed or not in PATH"
fi

if [ ! -d "$REPO_DIR" ]; then
  fail "Repo dir does not exist: $REPO_DIR"
fi

# 切换到仓库目录并确保存在 .git（防止误在错误目录执行）
cd "$REPO_DIR"

if [ ! -d ".git" ]; then
  fail "No .git directory found in $REPO_DIR"
fi

# 拉取远程变更并重置到远端分支的最新提交
# 使用 fetch + reset --hard 可以保证工作树精确匹配远端（注意：会丢弃本地未提交改动）
log "Fetching remote..."
git fetch --all --prune >>"$LOGFILE" 2>&1 || fail "git fetch failed"

log "Resetting to origin/$BRANCH ..."
# 兼容：本地没有该分支或分支名不同导致 checkout 失败
# - 优先：切到本地分支
# - 失败：从 origin/$BRANCH 创建/覆盖本地分支
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git checkout "$BRANCH" >>"$LOGFILE" 2>&1 || fail "git checkout $BRANCH failed"
else
  git checkout -B "$BRANCH" "origin/$BRANCH" >>"$LOGFILE" 2>&1 || fail "git checkout -B $BRANCH origin/$BRANCH failed"
fi
git reset --hard "origin/$BRANCH" >>"$LOGFILE" 2>&1 || fail "git reset --hard origin/$BRANCH failed"

# 如果仓库包含 package.json，则尝试安装依赖并构建
# 优先使用 pnpm（推荐用于 monorepo / 更快且锁文件可确定性），如果 pnpm 不可用再回退到 npm
if [ -f package.json ]; then
  if command -v pnpm >/dev/null 2>&1; then
    log "Installing node dependencies with pnpm (pnpm install --frozen-lockfile)..."
    pnpm install --frozen-lockfile >>"$LOGFILE" 2>&1 || fail "pnpm install failed"
  elif command -v npm >/dev/null 2>&1; then
    log "pnpm not found; falling back to npm (npm ci)..."
    npm ci >>"$LOGFILE" 2>&1 || fail "npm ci failed"
  else
    log "No pnpm or npm found, skipping dependency install"
  fi
else
  log "No package.json found, skipping npm/pnpm install/build"
fi


# 重启服务：优先使用 pm2（适用于 Node.js 应用），其次尝试 systemd（适用于 Linux 服务）
# - 若同时未提供 PM2_APP_NAME 和 SERVICE_NAME，则脚本仅完成代码同步与构建，不会重启服务
if [ -n "$PM2_APP_NAME" ] && command -v pm2 >/dev/null 2>&1; then
  log "Restarting PM2 app: $PM2_APP_NAME"
  # 先尝试平滑重载（reload），若失败再尝试 restart
  pm2 reload "$PM2_APP_NAME" >>"$LOGFILE" 2>&1 || pm2 restart "$PM2_APP_NAME" >>"$LOGFILE" 2>&1 || log "pm2 reload/restart returned non-zero"
  log "PM2 restart attempted"
elif [ -n "$SERVICE_NAME" ] && command -v systemctl >/dev/null 2>&1; then
  log "Restarting systemd service: $SERVICE_NAME"
  # 先刷新 systemd 配置（安全无害），然后重启服务（可能需要 sudo）
  sudo systemctl daemon-reload >>"$LOGFILE" 2>&1 || true
  sudo systemctl restart "$SERVICE_NAME" >>"$LOGFILE" 2>&1 || fail "systemctl restart $SERVICE_NAME failed"
  log "systemd service restarted"
else
  log "No PM2_APP_NAME or SERVICE_NAME provided (or pm2/systemctl not available). Skipping restart."
fi

log "=== updateBlog.sh finished successfully ==="
exit 0
