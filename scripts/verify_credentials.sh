#!/usr/bin/env bash
# verify_credentials.sh — 验证各服务凭证连通性
# 用法：bash scripts/verify_credentials.sh

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

if [ ! -f "$ENV_FILE" ]; then
  echo -e "${RED}❌ .env 不存在：$ENV_FILE${NC}"
  exit 1
fi

# 加载 .env
set -a
. "$ENV_FILE"
set +a

PASS=0
FAIL=0
WARN=0

check() {
  local name="$1"
  local cmd="$2"
  printf "%-40s " "$name"
  if eval "$cmd" > /tmp/check_out 2>&1; then
    echo -e "${GREEN}✅ PASS${NC}"
    PASS=$((PASS+1))
  else
    echo -e "${RED}❌ FAIL${NC}"
    FAIL=$((FAIL+1))
    [ -s /tmp/check_out ] && head -2 /tmp/check_out | sed 's/^/    /'
  fi
}

warn() {
  local name="$1"
  local cmd="$2"
  printf "%-40s " "$name"
  if eval "$cmd" > /tmp/check_out 2>&1; then
    echo -e "${GREEN}✅ PASS${NC}"
    PASS=$((PASS+1))
  else
    echo -e "${YELLOW}⚠️  WARN${NC}"
    WARN=$((WARN+1))
  fi
}

echo ""
echo "═══════════════════════════════════════════"
echo "  multi-media-publisher · 凭证验证"
echo "═══════════════════════════════════════════"
echo ""

# ===== 一、Docker 服务 =====
echo "━━━ 一、Docker 服务状态 ━━━"
check "n8n 健康检查" "[ -n \"\${N8N_HOST:-}\" ] && curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://\${N8N_HOST}:5678/healthz | grep -qE '^[12]'"
check "MinIO 健康检查" "curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:9000/minio/health/live | grep -qE '^200'"
check "Dify 健康检查" "curl -sS -o /dev/null -w '%{http_code}' --max-time 5 \${DIFY_API_URL%/v1}/health | grep -qE '^200'"
check "Uptime Kuma" "curl -sS -o /dev/null -w '%{http_code}' --max-time 5 http://localhost:3001 | grep -qE '^[12]'"

echo ""
echo "━━━ 二、飞书凭证 ━━━"
check "飞书 AppID 格式" "[ -n \"\${FEISHU_APP_ID:-}\" ] && [ \${#FEISHU_APP_ID} -ge 14 ]"
check "飞书 AppSecret 非空" "[ -n \"\${FEISHU_APP_SECRET:-}\" ] && [ \${#FEISHU_APP_SECRET} -ge 20 ]"
check "多维表格 Token 非空" "[ -n \"\${FEISHU_BITABLE_TOKEN:-}\" ]"
check "飞书 token 验证 (tenant_access_token)" "
  [ -n \"\${FEISHU_APP_ID:-}\" ] && [ -n \"\${FEISHU_APP_SECRET:-}\" ] && {
    resp=\$(curl -sS --max-time 8 -X POST \
      'https://open.feishu.cn/open-apis/auth/v3/tenant_access_token/internal' \
      -H 'Content-Type: application/json' \
      -d \"{\\\"app_id\\\":\\\"\${FEISHU_APP_ID}\\\",\\\"app_secret\\\":\\\"\${FEISHU_APP_SECRET}\\\"}\")
    echo \"\$resp\" | grep -q '\"code\":0'
  }
"

echo ""
echo "━━━ 三、Dify 凭证 ━━━"
check "Dify API Key 非空" "[ -n \"\${DIFY_API_KEY:-}\" ]"
check "Dify 应用连通" "
  [ -n \"\${DIFY_API_KEY:-}\" ] && {
    curl -sS --max-time 5 \${DIFY_API_URL}/parameters 2>&1 | head -1
  } | grep -qE 'opens\\u002F|parameters|error'
"

echo ""
echo "━━━ 四、平台凭证 ━━━"
check "公众号 AppID 格式" "[ -n \"\${WECHAT_APP_ID:-}\" ] && [[ \${WECHAT_APP_ID} =~ ^wx[0-9a-f]{16}\$ ]] || [ -z \"\${WECHAT_APP_ID:-}\" ]"
warn "微博 Access Token" "[ -n \"\${WEIBO_ACCESS_TOKEN:-}\" ]"
check "MiniMax API Key" "[ -n \"\${MINIMAX_API_KEY:-}\" ]"

echo ""
echo "━━━ 五、n8n 工作流配置 ━━━"
check "n8n publish webhook 可达" "
  curl -sS -o /dev/null -w '%{http_code}' --max-time 5 \
    \${N8N_PUBLISH_URL:-http://localhost:5678}/webhook/multi-media-publish
"

echo ""
echo "═══════════════════════════════════════════"
echo -e "  ${GREEN}通过 ${PASS}${NC}  ${YELLOW}告警 ${WARN}${NC}  ${RED}失败 ${FAIL}${NC}"
echo "═══════════════════════════════════════════"

exit $FAIL
