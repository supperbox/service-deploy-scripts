#!/usr/bin/env bash
set -euo pipefail

# -------------------- 配置区 --------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# vue-ts-image 项目目录
REPO_DIR="${REPO_DIR:-/var/www/vue-ts-image}"

# 要同步的远端分支
BRANCH="${BRANCH:-main}"

# 日志文件
LOGFILE="${LOGFILE:-${SCRIPT_DIR}/updateImageVue.log}"

# 安装依赖命令策略：auto|pnpm|npm|skip
INSTALL_DEPS="${INSTALL_DEPS:-pnpm}"

# pnpm install 参数（可选）
PNPM_INSTALL_ARGS="${PNPM_INSTALL_ARGS:-}"

# pnpm build 参数（可选）
PNPM_BUILD_ARGS="${PNPM_BUILD_ARGS:-}"
# ----------------------------------------------------------------------

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log() {
  echo "[$(timestamp)] $*" | tee -a "$LOGFILE"
}

fail() {
  echo "[$(timestamp)] ERROR: $*" | tee -a "$LOGFILE" >&2
  exit 1
}

trap 'fail "Script interrupted or failed"' INT TERM

log "=== updateImageVue.sh start ==="
log "Script dir: $SCRIPT_DIR"
log "Repo dir: $REPO_DIR"
log "Branch: $BRANCH"
log "Logfile: $LOGFILE"

if ! command -v git >/dev/null 2>&1; then
  fail "git is not installed or not in PATH"
fi

if [ ! -d "$REPO_DIR" ]; then
  fail "Repo dir does not exist: $REPO_DIR"
fi

cd "$REPO_DIR"

if [ ! -d ".git" ]; then
  fail "No .git directory found in $REPO_DIR"
fi

log "Fetching remote..."
git fetch --all --prune >>"$LOGFILE" 2>&1 || fail "git fetch failed"

log "Resetting to origin/$BRANCH ..."
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git checkout "$BRANCH" >>"$LOGFILE" 2>&1 || fail "git checkout $BRANCH failed"
else
  git checkout -B "$BRANCH" "origin/$BRANCH" >>"$LOGFILE" 2>&1 || fail "git checkout -B $BRANCH origin/$BRANCH failed"
fi

git reset --hard "origin/$BRANCH" >>"$LOGFILE" 2>&1 || fail "git reset --hard origin/$BRANCH failed"

log "Installing dependencies... (strategy: $INSTALL_DEPS)"
case "$INSTALL_DEPS" in
  skip)
    log "Skipping dependency installation"
    ;;
  auto|pnpm)
    if ! command -v pnpm >/dev/null 2>&1; then
      fail "pnpm is not installed or not in PATH"
    fi
    pnpm install ${PNPM_INSTALL_ARGS} >>"$LOGFILE" 2>&1 || fail "pnpm install failed"
    ;;
  npm)
    if ! command -v npm >/dev/null 2>&1; then
      fail "npm is not installed or not in PATH"
    fi
    npm install >>"$LOGFILE" 2>&1 || fail "npm install failed"
    ;;
  *)
    fail "Unknown INSTALL_DEPS strategy: $INSTALL_DEPS (expected: auto|pnpm|npm|skip)"
    ;;
esac

log "Building..."
if ! command -v pnpm >/dev/null 2>&1; then
  fail "pnpm is not installed or not in PATH"
fi
pnpm run build ${PNPM_BUILD_ARGS} >>"$LOGFILE" 2>&1 || fail "pnpm run build failed"


log "=== updateImageVue.sh finished successfully ==="
exit 0