#!/usr/bin/env bash
# web/start.sh — 启动 multi-media-publisher Web UI
# 用法：bash web/start.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# 检查 Python 依赖
if ! python3 -c "import fastapi, uvicorn, jinja2" 2>/dev/null; then
  echo "📦 装依赖..."
  pip3 install -r "$SCRIPT_DIR/requirements.txt"
fi

# 检查 .env
if [ ! -f "$ROOT_DIR/.env" ]; then
  echo "⚠️  .env 不存在，复制 .env.example → .env"
  cp "$ROOT_DIR/.env.example" "$ROOT_DIR/.env"
  chmod 600 "$ROOT_DIR/.env"
  echo "请运行 bash scripts/setup_credentials.sh 填凭证"
fi

# 启动 uvicorn
echo "🚀 启动 Web UI: http://localhost:8090"
echo "   (Ctrl+C 停止)"
echo ""
cd "$ROOT_DIR"
exec python3 -m uvicorn web.server:app --host 0.0.0.0 --port 8090 --log-level info
