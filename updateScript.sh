#!/usr/bin/env bash
set -euo pipefail

# 作用：自更新本仓库（/var/www/service-deploy-scripts）
# 使用场景：当你想通过远程触发更新部署脚本本身。

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 本仓库目录（默认：脚本所在目录）
REPO_DIR="${REPO_DIR:-$SCRIPT_DIR}"

# 远端分支：不设置则自动读取 origin/HEAD
BRANCH="${BRANCH:-}"

LOGFILE="${LOGFILE:-${SCRIPT_DIR}/updateScript.log}"

# 更新后可选执行的钩子（例如重载某个服务）：留空则不执行
POST_UPDATE_CMD="${POST_UPDATE_CMD:-}"

timestamp() { date '+%Y-%m-%d %H:%M:%S'; }

log() {
  echo "[$(timestamp)] $*" | tee -a "$LOGFILE"
}

fail() {
  echo "[$(timestamp)] ERROR: $*" | tee -a "$LOGFILE" >&2
  exit 1
}

trap 'fail "Script interrupted or failed"' INT TERM

log "=== updateScript.sh start ==="
log "Script dir: $SCRIPT_DIR"
log "Repo dir: $REPO_DIR"
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

if [ -z "$BRANCH" ]; then
  BRANCH="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')" || true
fi
if [ -z "$BRANCH" ]; then
  BRANCH="master"
fi
log "Branch: $BRANCH"

log "Resetting to origin/$BRANCH ..."
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  git checkout "$BRANCH" >>"$LOGFILE" 2>&1 || fail "git checkout $BRANCH failed"
else
  git checkout -B "$BRANCH" "origin/$BRANCH" >>"$LOGFILE" 2>&1 || fail "git checkout -B $BRANCH origin/$BRANCH failed"
fi

git reset --hard "origin/$BRANCH" >>"$LOGFILE" 2>&1 || fail "git reset --hard origin/$BRANCH failed"

git status --porcelain=v1 >>"$LOGFILE" 2>&1 || true

if [ -n "$POST_UPDATE_CMD" ]; then
  log "Running POST_UPDATE_CMD: $POST_UPDATE_CMD"
  bash -lc "$POST_UPDATE_CMD" >>"$LOGFILE" 2>&1 || fail "POST_UPDATE_CMD failed"
fi

log "=== updateScript.sh finished successfully ==="
exit 0
