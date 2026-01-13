#!/usr/bin/env bash
set -euo pipefail

# -------------------- 配置区 (可通过环境变量覆盖) --------------------
# 说明：把常用的可定制参数集中放在文件顶部，便于运维/CI 覆盖与阅读
# - 若希望用不同值运行脚本，可在运行时导出环境变量覆盖（例如：export REPO_DIR=/path && ./updateBlog.sh）
# - 变量含义见每行注释

# 脚本所在目录（默认：脚本文件所在目录），用于拼接相对路径和日志位置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 待更新项目仓库目录（默认项目路径）。可用环境变量 REPO_DIR 覆盖。
REPO_DIR="${REPO_DIR:-/var/www/next-react-ts-tailwind2026}"

# 要切换并重置到的远端分支（默认 master）。可用 BRANCH 覆盖。
BRANCH="${BRANCH:-master}"

# 日志文件路径（默认写到脚本目录下的 updateBlog.log）。可用 LOGFILE 覆盖。
LOGFILE="${LOGFILE:-${SCRIPT_DIR}/updateBlog.log}"

# PM2 进程名（若为空则不使用 pm2）。可用 PM2_APP_NAME 覆盖。
PM2_APP_NAME="${PM2_APP_NAME:-blog}"

# 自定义构建命令（优先级高于自动检测 pnpm/npm）。例如：BUILD_CMD="pnpm build --filter ..."
BUILD_CMD="${BUILD_CMD:-}"

# systemd 服务名（若使用 systemd 重启，这里设置；可用 SERVICE_NAME 覆盖）。
SERVICE_NAME="${SERVICE_NAME:-}"
# ----------------------------------------------------------------------

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
  # 读取 packageManager 优先级（若存在，优先使用 pnpm）
  PKG_MANAGER=""
  if grep -q '"packageManager"' package.json 2>/dev/null; then
    if grep -q 'pnpm' package.json 2>/dev/null; then
      PKG_MANAGER="pnpm"
    else
      PKG_MANAGER="npm"
    fi
  fi

  # 确保日志文件目录存在
  mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null || true

  if command -v pnpm >/dev/null 2>&1; then
    log "Installing node dependencies with pnpm (pnpm install --frozen-lockfile)..."
    pnpm install --frozen-lockfile >>"$LOGFILE" 2>&1 || fail "pnpm install failed"
    # 构建项目（优先使用自定义 BUILD_CMD，其次 pnpm）
    if [ -n "$BUILD_CMD" ]; then
      log "Building project with custom BUILD_CMD: $BUILD_CMD"
      eval "$BUILD_CMD" >>"$LOGFILE" 2>&1 || fail "BUILD_CMD failed"
    else
      log "Building project with pnpm (pnpm run build)..."
      pnpm run build >>"$LOGFILE" 2>&1 || fail "pnpm build failed"
    fi
  elif command -v npm >/dev/null 2>&1; then
    log "pnpm not found; falling back to npm (npm ci)..."
    npm ci >>"$LOGFILE" 2>&1 || fail "npm ci failed"
    # 构建项目（优先使用自定义 BUILD_CMD，其次 npm）
    if [ -n "$BUILD_CMD" ]; then
      log "Building project with custom BUILD_CMD: $BUILD_CMD"
      eval "$BUILD_CMD" >>"$LOGFILE" 2>&1 || fail "BUILD_CMD failed"
    else
      log "Building project with npm (npm run build)..."
      npm run build >>"$LOGFILE" 2>&1 || fail "npm run build failed"
    fi
  else
    log "No pnpm or npm found, skipping dependency install"
  fi
else
  log "No package.json found, skipping npm/pnpm install/build"
fi


# 重启服务：优先使用 pm2（适用于 Node.js 应用），其次尝试 systemd（适用于 Linux 服务）
# - 若同时未提供 PM2_APP_NAME 和 SERVICE_NAME，则脚本仅完成代码同步与构建，不会重启服务
if [ -n "$PM2_APP_NAME" ] && command -v pm2 >/dev/null 2>&1; then
  log "PM2 available. Preparing to reload/restart PM2 app: $PM2_APP_NAME"
  # 如果仓库包含 ecosystem 文件，优先使用它进行 reload/start
  if [ -f ecosystem.config.js ] || [ -f ecosystem.config.cjs ] || [ -f ecosystem.config.mjs ]; then
    ECOSYS="ecosystem.config.js"
    if [ -f ecosystem.config.cjs ]; then ECOSYS="ecosystem.config.cjs"; fi
    if [ -f ecosystem.config.mjs ]; then ECOSYS="ecosystem.config.mjs"; fi
    log "Found $ECOSYS — reloading via pm2 $ECOSYS --env production"
    pm2 reload "$ECOSYS" --env production >>"$LOGFILE" 2>&1 || pm2 start "$ECOSYS" --env production >>"$LOGFILE" 2>&1 || log "pm2 reload/start with $ECOSYS returned non-zero"
  else
    log "No ecosystem file found — attempting pm2 reload/restart by app name: $PM2_APP_NAME"
    pm2 reload "$PM2_APP_NAME" >>"$LOGFILE" 2>&1 || pm2 restart "$PM2_APP_NAME" >>"$LOGFILE" 2>&1 || log "pm2 reload/restart returned non-zero"
  fi
  log "PM2 reload/restart attempted"
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
