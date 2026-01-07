# service-deploy-scripts

一组用于“拉取代码并（可选）重启服务”的部署/更新脚本，以及用于本地/联调的测试脚本。

> 重要：`update.sh` / `updateBlog.sh` 会执行 `git reset --hard`，会丢弃仓库内所有未提交改动。请只在部署机/受控环境使用。

## 目录结构

- `update.sh`：更新一个 Node/服务项目（含可选 pm2/systemd 重启）
- `updateBlog.sh`：更新博客项目（含可选 pm2/systemd 重启；支持通过环境变量覆盖更多参数）
- `test-update.sh`：使用 `curl` 触发 webhook（POST 请求）
- `test-update.ps1`：Windows 下的本地“打印信息”测试桩（不发网络请求）

## 环境要求

- `bash`（Linux/macOS/WSL/Git Bash）
- `git`（必需）
- 可选：`pnpm` 或 `npm`（如果目标仓库有 `package.json`，脚本会尝试安装依赖）
- 可选：`pm2`（Node 服务进程管理）
- 可选：`systemctl` + `sudo`（Linux systemd 服务重启）

Windows 直接运行 `*.sh` 需要 WSL 或 Git Bash；`test-update.ps1` 可在 PowerShell 里直接运行。

## 脚本说明

### updateBlog.sh

用于更新某个仓库目录到远端分支最新提交，并按需重启服务。

默认行为（来自脚本当前实现）：

- 默认仓库目录：`/var/www/personBlogSite`
- 默认分支：`master`
- 默认日志：脚本同目录 `updateBlog.log`
- 默认 pm2 应用名：`ei`
- 会执行：`git fetch --all --prune` → `git checkout`（必要时 `-B` 创建分支）→ `git reset --hard origin/<branch>`
- 若检测到 `package.json`：优先 `pnpm install --frozen-lockfile`，否则 `npm ci`
- 重启逻辑：优先 `pm2 reload|restart`；否则（若设置了 `SERVICE_NAME`）尝试 `systemctl restart`

可用环境变量：

- `REPO_DIR`：目标仓库目录（默认 `/var/www/personBlogSite`）
- `BRANCH`：要同步的分支（默认 `master`）
- `LOGFILE`：日志文件路径（默认 `./updateBlog.log`，即脚本同目录）
- `PM2_APP_NAME`：pm2 应用名（默认 `ei`）
- `SERVICE_NAME`：systemd 服务名（默认空；仅在没有 pm2 或未设置 pm2 时使用）

示例：

```bash
# 使用默认值
bash ./updateBlog.sh

# 指定仓库目录与分支
REPO_DIR=/var/www/personBlogSite BRANCH=master bash ./updateBlog.sh

# 指定 pm2 应用名
PM2_APP_NAME=my-blog bash ./updateBlog.sh

# 使用 systemd（可能需要 sudo 权限）
SERVICE_NAME=my-blog.service bash ./updateBlog.sh
```

### update.sh

用于更新某个项目目录到远端分支最新提交，并按需重启服务。

注意：该脚本目前是“固定路径/固定分支”的写法（没有像 `updateBlog.sh` 那样通过环境变量覆盖）。当前默认值为：

- `SCRIPT_DIR`：`/var/www/express/Ts-mongoDb-express/scripts`
- `REPO_DIR`：`/var/www/express/Ts-mongoDb-express`
- `BRANCH`：`main`
- `LOGFILE`：`/var/www/express/Ts-mongoDb-express/scripts/update.log`
- `PM2_APP_NAME`：`ei`

其余行为与 `updateBlog.sh` 类似（同样会 `reset --hard`，并在有 `package.json` 时尝试安装依赖）。

运行：

```bash
bash ./update.sh
```

如果你希望把 `update.sh` 也改成可配置（`REPO_DIR/BRANCH/LOGFILE` 可通过环境变量覆盖），我也可以顺手帮你改掉。

### test-update.sh

用于用 `curl` 触发一个 webhook（默认 POST 到 `http://localhost:3008/updateExpress`），并携带 token 头。

- 第 1 个参数：URL（可选）
- 第 2 个参数：TOKEN（可选；不传则读取环境变量 `WEBHOOK_SECRET`）
- Header：`x-webhook-token: <TOKEN>`

示例：

```bash
# 默认 URL（本机 3008），token 从环境变量取
export WEBHOOK_SECRET="your_token"
bash ./test-update.sh

# 指定 URL + token
bash ./test-update.sh http://localhost:3008/updateExpress "your_token"
```

### test-update.ps1

Windows 下的本地测试脚本：打印当前时间、工作目录、用户名、`WEBHOOK_SECRET` 环境变量等信息。

> 该脚本不会发起任何网络请求。

示例：

```powershell
# 直接运行
powershell -ExecutionPolicy Bypass -File .\test-update.ps1

# 带参数运行（仅用于打印 args）
powershell -ExecutionPolicy Bypass -File .\test-update.ps1 http://localhost:3008/updateExpress your_token
```

## 安全与运维注意事项

- `git reset --hard` 会删除未提交变更；部署机上不要在目标仓库里做手工修改。
- webhook 触发更新时，务必在服务端校验 token（`x-webhook-token`），并限制来源（IP allowlist / 网关鉴权等）。
- 若使用 `systemctl` 重启服务，请确保执行用户具备对应 sudo 权限，或通过更安全的方式（如限定 sudoers 规则）授予最小权限。
- 日志文件会持续追加（`tee -a`），建议结合 logrotate 或定期清理。
