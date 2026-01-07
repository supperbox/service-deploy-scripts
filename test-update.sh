#!/usr/bin/env bash
# 简单的 Unix/Mac/Linux 下测试脚本，使用 curl 触发 /updateExpress
# 用法：
#   ./scripts/test-update.sh [URL] [TOKEN]
# 示例：
#   ./scripts/test-update.sh http://localhost:3008 "your_token"

URL=${1:-http://localhost:3008/updateExpress}
TOKEN=${2:-$WEBHOOK_SECRET}

if [ -z "$TOKEN" ]; then
  echo "Warning: no token provided (use second arg or set WEBHOOK_SECRET env var). The request may be rejected."
fi

curl -s -X POST \
  -H "Content-Type: application/json" \
  -H "x-webhook-token: $TOKEN" \
  -d '{}' \
  "$URL" \
  -w "\nHTTP_CODE:%{http_code}\n"
