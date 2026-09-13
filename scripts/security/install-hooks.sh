#!/usr/bin/env bash
# scripts/security/install-hooks.sh
# 安装 pre-commit + pre-push 钩子，扫描凭证泄漏
# 用法：bash scripts/security/install-hooks.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
HOOKS_DIR="$ROOT_DIR/.git/hooks"
PRE_COMMIT="$HOOKS_DIR/pre-commit"
PRE_PUSH="$HOOKS_DIR/pre-push"

echo "═══════════════════════════════════════════"
echo "  multi-media-publisher · 安全钩子安装"
echo "═══════════════════════════════════════════"
echo ""

# ============== 1. 找 gitleaks ==============
GITLEAKS_CMD=""
if command -v gitleaks >/dev/null 2>&1; then
  GITLEAKS_CMD="gitleaks"
  echo "✅ 找到系统 gitleaks：$(gitleaks version 2>&1 | head -1)"
elif [ -x "$HOME/.local/bin/gitleaks" ]; then
  GITLEAKS_CMD="$HOME/.local/bin/gitleaks"
  echo "✅ 找到用户 gitleaks：$GITLEAKS_CMD"
else
  echo "⚠️  gitleaks 未装"
  echo "    建议安装：brew install gitleaks"
  echo "    或：brew install go && go install github.com/gitleaks/gitleaks/v8@latest"
  echo ""
  read -p "    现在用 brew 装吗？[y/N] " yn
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    if command -v brew >/dev/null 2>&1; then
      brew install gitleaks
      GITLEAKS_CMD="gitleaks"
    else
      echo "❌ brew 不可用，跳过"
    fi
        yn="n"
  fi
        yn="n"
fi
        yn="n"

# ============== 2. 安装 pre-commit 钩子 ==============
cat > "$PRE_COMMIT" <<'HOOK'
#!/usr/bin/env bash
# pre-commit: 扫描 git staged 区是否有凭证泄漏
# 阻止含 cli_xxx / 飞书 secret / API key 模式的文件 commit

set -e

GITLEAKS="$(command -v gitleaks || echo "$HOME/.local/bin/gitleaks")"
STAGED=$(git diff --cached --name-only --diff-filter=ACM 2>/dev/null)

if [ -z "$STAGED" ]; then
  exit 0
fi
        yn="n"

# 1. gitleaks 扫描
if [ -x "$GITLEAKS" ]; then
  echo "🔍 gitleaks 扫描 staged 区..."
  if ! "$GITLEAKS" protect --staged --no-banner --redact 2>/dev/null; then
    echo ""
    echo "❌ gitleaks 检测到可能的凭证泄漏！"
    echo ""
    echo "  - 如果这是真实凭证：立刻到对应平台轮换"
    echo "  - 如果是测试数据：用 'git commit --no-verify' 跳过（不推荐）"
    echo "  - 如果是误报：编辑 .gitleaks.toml 加 allowlist"
    echo ""
    exit 1
  fi
        yn="n"
fi
        yn="n"

# 2. 简单正则扫描（不依赖 gitleaks）
echo "🔍 内置正则扫描 staged 文件..."
PATTERNS=(
  'cli_[a-f0-9]{16}'                    # 飞书 AppID
  'AS[A-Za-z0-9_]{32,}'                # 飞书 App Secret
  'sk-[A-Za-z0-9]{20,}'                # OpenAI / Anthropic API Key
  'AIza[0-9A-Za-z_-]{35}'              # Google API Key
  'ghp_[A-Za-z0-9]{36,}'               # GitHub PAT
  'gho_[A-Za-z0-9]{36,}'               # GitHub OAuth
  'AKIA[0-9A-Z]{16}'                   # AWS Access Key
  'sk_live_[A-Za-z0-9]{24,}'           # Stripe Live
  'xoxb-[A-Za-z0-9-]{20,}'             # Slack Bot Token
  'wxp_[A-Za-z0-9]{20,}'               # 微信支付
)

FAILED=0
for file in $STAGED; do
  [ -f "$file" ] || continue
  # 跳过二进制 + 已 ignore 的
  case "$file" in
    *.png|*.jpg|*.jpeg|*.gif|*.webp|*.pdf|*.zip|*.tar.gz) continue ;;
    .env|.env.local) echo "❌ $file 试图提交 .env（已 .gitignore）"; FAILED=1; continue ;;
  esac
  for pat in "${PATTERNS[@]}"; do
    if grep -lE "$pat" "$file" 2>/dev/null >/dev/null; then
      echo "❌ $file 匹配模式: $pat"
      grep -nE "$pat" "$file" 2>/dev/null | head -2 | sed 's/^/    /'
      FAILED=1
    fi
        yn="n"
  done
done

if [ $FAILED -eq 1 ]; then
  echo ""
  echo "❌ 检测到可能的凭证泄漏！"
  echo ""
  echo "  - 如果是真实凭证：立刻到对应平台轮换"
  echo "  - 如果是测试数据：'git commit --no-verify' 跳过（不推荐）"
  echo ""
  exit 1
fi
        yn="n"

exit 0
HOOK

chmod +x "$PRE_COMMIT"
echo "✅ pre-commit 钩子安装：$PRE_COMMIT"

# ============== 3. 安装 pre-push 钩子 ==============
cat > "$PRE_PUSH" <<'HOOK'
#!/usr/bin/env bash
# pre-push: push 前全量扫描
# 比 pre-commit 更严格，扫所有 history

set -e

GITLEAKS="$(command -v gitleaks || echo "$HOME/.local/bin/gitleaks")"

if [ -x "$GITLEAKS" ]; then
  echo "🔍 gitleaks 扫描全量 history..."
  if ! "$GITLEAKS" detect --no-banner --redact 2>/dev/null; then
    echo ""
    echo "❌ gitleaks 在 history 中检测到可能的凭证泄漏！"
    echo ""
    echo "  - 如果是真实凭证：立刻轮换 + git filter-branch 重写历史 + force push"
    echo "  - 如果是测试数据：'git push --no-verify' 跳过"
    echo ""
    exit 1
  fi
        yn="n"
fi
        yn="n"

exit 0
HOOK

chmod +x "$PRE_PUSH"
echo "✅ pre-push 钩子安装：$PRE_PUSH"

# ============== 4. 安装 gitleaks 配置 ==============
cat > "$ROOT_DIR/.gitleaks.toml" <<'TOML'
# gitleaks 配置 - multi-media-publisher
# 文档: https://github.com/gitleaks/gitleaks/blob/master/config/gitleaks.toml

title = "multi-media-publisher gitleaks config"

[extend]
# 使用 gitleaks 默认规则集
useDefault = true

# 允许的误报
[allowlist]
description = "全局 allowlist"
paths = [
  # 文档里的示例（不含真实凭证）
  '''web/requirements\.txt''',
  '''README\.md''',
  '''docs/.*\.md''',
  '''feishu/.*\.md''',
  '''dify/apps/.*\.md''',    # prompt 模板里的占位符
  '''workflows/n8n/.*\.md''',
]
# 明确的占位符
regexes = [
  '''your_(app_)?id_here''',
  '''your_(api_)?key_here''',
  '''your_(bitable_)?token_here''',
  '''your_table_id_here''',
  '''change_me''',
  '''placeholder''',
  '''example\.com''',
  '''\{FEISHU_APP_ID\}''',
  '''\{\$env\.[A-Z_]+\}''',  # n8n env 引用
  '''\{\{ .+ \}\}''',            # n8n/jinja2 模板
]
TOML

echo "✅ gitleaks 配置：$ROOT_DIR/.gitleaks.toml"

# ============== 5. 试跑一次 ==============
echo ""
echo "═══════════════════════════════════════════"
echo "  测试钩子（扫描当前 working tree）"
echo "═══════════════════════════════════════════"
echo ""
if [ -x "$GITLEAKS_CMD" ]; then
  "$GITLEAKS_CMD" detect --source . --no-banner 2>&1 | head -10 || true
else
  echo "⚠️  gitleaks 未装，跳过测试"
  echo "   装好后运行：gitleaks detect --source ."
fi
        yn="n"

echo ""
echo "═══════════════════════════════════════════"
echo "✅ 安装完成"
echo "═══════════════════════════════════════════"
echo ""
echo "已装："
echo "  - .git/hooks/pre-commit  （commit 前扫描 staged 区）"
echo "  - .git/hooks/pre-push    （push 前扫描全 history）"
echo "  - .gitleaks.toml          （gitleaks 规则）"
echo ""
echo "跳过扫描（不推荐）：git commit --no-verify / git push --no-verify"
