#!/usr/bin/env bash
# setup_credentials.sh — 引导式填入多平台凭证到 .env
# 用法：bash scripts/setup_credentials.sh
#
# 适用平台：
#   - 飞书 (AppID / AppSecret / Bitable Token)
#   - Dify (API URL / API Key)
#   - 公众号 (AppID / AppSecret)
#   - 微博 (Access Token)
#   - 小红书 (Cookie) — 通过 xiaohongshu_poster.py 单独登录
#   - 掘金 / 少数派 / 知乎 (Cookie) — 未来 n8n 走 Playwright

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENV_FILE="$ROOT_DIR/.env"

# 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}  multi-media-publisher · 凭证配置向导${NC}"
echo -e "${GREEN}  v0.1.0${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""
echo "📁 配置文件：$ENV_FILE"
echo ""

# 检查 .env 存在
if [ ! -f "$ENV_FILE" ]; then
  if [ -f "$ROOT_DIR/.env.example" ]; then
    echo -e "${YELLOW}⚠️  .env 不存在，从 .env.example 复制${NC}"
    cp "$ROOT_DIR/.env.example" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
  else
    echo -e "${RED}❌ .env 和 .env.example 都不存在${NC}"
    exit 1
  fi
fi

# 备份
BACKUP="$ENV_FILE.bak.$(date +%Y%m%d_%H%M%S)"
cp "$ENV_FILE" "$BACKUP"
echo -e "${YELLOW}📦 备份：$BACKUP${NC}"
echo ""

# 通用函数
read_secret() {
  local key="$1"
  local desc="$2"
  local current
  current=$(grep "^${key}=" "$ENV_FILE" 2>/dev/null | head -1 | cut -d'=' -f2-)
  local masked="(未设置)"
  if [ -n "$current" ] && [ "$current" != "your_${key,,}_here" ]; then
    masked="${current:0:4}***"
  fi

  echo -e "  ${YELLOW}${desc}${NC}"
  echo -e "  当前: ${masked}"
  read -p "  新值（回车跳过）: " value
  if [ -n "$value" ]; then
    # 删除旧行，写新行
    sed -i.bak "/^${key}=/d" "$ENV_FILE"
    echo "${key}=${value}" >> "$ENV_FILE"
    echo -e "  ${GREEN}✅ ${key} 已更新${NC}"
  else
    echo -e "  ${YELLOW}⏭️  跳过${NC}"
  fi
  echo ""
}

echo -e "${GREEN}━━━ 一、飞书配置 ━━━${NC}"
read_secret "FEISHU_APP_ID" "飞书 App ID（飞书开发者后台 → 凭证与基础信息）"
read_secret "FEISHU_APP_SECRET" "飞书 App Secret"
read_secret "FEISHU_BITABLE_TOKEN" "多维表格 Token（URL 里 bseXXX 那段）"
read_secret "FEISHU_TABLE_ID" "多维表格 Table ID（tblXXX）"
read_secret "FEISHU_BOT_WEBHOOK" "飞书机器人 Webhook（群聊 → 设置 → 机器人）"

echo -e "${GREEN}━━━ 二、Dify 配置 ━━━${NC}"
read_secret "DIFY_API_URL" "Dify API 地址（如 http://localhost/v1）"
read_secret "DIFY_API_KEY" "Dify 应用 API Key"

echo -e "${GREEN}━━━ 三、公众号配置 ━━━${NC}"
read_secret "WECHAT_APP_ID" "公众号 AppID"
read_secret "WECHAT_APP_SECRET" "公众号 AppSecret"

echo -e "${GREEN}━━━ 四、微博配置 ━━━${NC}"
read_secret "WEIBO_ACCESS_TOKEN" "微博 Access Token"

echo -e "${GREEN}━━━ 五、AI 模型配置 ━━━${NC}"
read_secret "MINIMAX_API_KEY" "MiniMax API Key（或其它 LLM）"
read_secret "MINIMAX_MODEL" "模型名（如 MiniMax-M2）"

echo -e "${GREEN}━━━ 六、n8n 推送地址（多平台分发用）━━━${NC}"
read_secret "N8N_PUBLISH_URL" "n8n webhook base URL（默认 http://localhost:5678）"

echo ""
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}✅ 凭证配置完成${NC}"
echo -e "${GREEN}═══════════════════════════════════════════${NC}"
echo ""
echo "📁 已写入：$ENV_FILE"
echo "📦 备份在：$BACKUP"
echo ""
echo "下一步："
echo "  1. 重启 docker-compose 让新凭证生效："
echo "     cd $ROOT_DIR && docker compose restart"
echo "  2. 验证服务连通："
echo "     bash scripts/verify_credentials.sh"
echo "  3. 创建 n8n publish workflow（接收 /webhook/multi-media-publish）"
echo "  4. 跑一次端到端测试："
echo "     python3 pipeline/pipeline.py publish <draft_id> --platforms=xiaohongshu,juejin"
echo ""
