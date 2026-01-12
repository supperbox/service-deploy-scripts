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


log "=== updateImageVue.sh finished successfully ==="
exit 0