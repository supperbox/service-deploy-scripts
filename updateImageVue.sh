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

if [ -f package.json ]; then
  case "$INSTALL_DEPS" in
    skip)
      log "INSTALL_DEPS=skip; skipping dependency install"
      ;;
    pnpm)
      command -v pnpm >/dev/null 2>&1 || fail "pnpm not found"
      log "Installing dependencies with pnpm (pnpm install --frozen-lockfile)..."
      pnpm install --frozen-lockfile >>"$LOGFILE" 2>&1 || fail "pnpm install failed"
      ;;
    npm)
      command -v npm >/dev/null 2>&1 || fail "npm not found"
      log "Installing dependencies with npm (npm ci)..."
      npm ci >>"$LOGFILE" 2>&1 || fail "npm ci failed"
      ;;
    auto|*)
      if command -v pnpm >/dev/null 2>&1; then
        log "Installing dependencies with pnpm (pnpm install --frozen-lockfile)..."
        pnpm install --frozen-lockfile >>"$LOGFILE" 2>&1 || fail "pnpm install failed"
      elif command -v npm >/dev/null 2>&1; then
        log "pnpm not found; falling back to npm (npm ci)..."
        npm ci >>"$LOGFILE" 2>&1 || fail "npm ci failed"
      else
        log "No pnpm or npm found; skipping dependency install"
      fi
      ;;
  esac
else
  log "No package.json found; skipping dependency install"
fi

log "Building project..."
if [ -f package.json ]; then
  if command -v pnpm >/dev/null 2>&1; then
    pnpm run build >>"$LOGFILE" 2>&1 || fail "pnpm build failed"
  elif command -v npm >/dev/null 2>&1; then
    npm run build >>"$LOGFILE" 2>&1 || fail "npm build failed"
  else
    fail "No pnpm or npm found; cannot build project"
  fi
else
  log "No package.json found; skipping build"
fi

log "=== updateImageVue.sh finished successfully ==="
exit 0