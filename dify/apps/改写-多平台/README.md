# Dify 多平台改写 · 应用目录

> 4 个 Dify 应用，1 个母稿 → 4 平台风格改写。

## 包含的应用

| 应用 | 平台 | 字数 | 调性 | 链接 |
|---|---|---|---|---|
| [`公众号.md`](公众号.md) | 微信公众号 | 1800-2500 | 深度 + 行动建议 | [配置](公众号.md#dify-应用配置) |
| [`小红书.md`](小红书.md) | 小红书 | ≤800 | 视觉 + 现场感 | [配置](小红书.md#dify-应用配置) |
| [`掘金.md`](掘金.md) | 掘金 | 1500-3000 | 技术 + 代码 | [配置](掘金.md#dify-应用配置) |
| [`知乎.md`](知乎.md) | 知乎 | 800-4000 | 克制 + 深度 | [配置](知乎.md#dify-应用配置) |

## 部署步骤

### 1. 启动 Dify（已有）

```bash
# dify/ 目录里已有 docker-compose
cd /Users/masterlinc/Desktop/新媒体一键发布平台/dify/docker
docker compose up -d
```

访问 http://localhost 完成初始化。

### 2. 创建 4 个应用

Dify 控制台 → 「工作室」 → 「创建空白应用」 → 选「Chatflow」类型：

- **应用名**：`改写-公众号` / `改写-小红书` / `改写-掘金` / `改写-知乎`
- **模型**：`MiniMax-M2`（或你用的 LLM）
- **System Prompt**：复制对应 `xxx.md` 文件里的 System Prompt
- **用户输入**：从 Inputs 区块加 `input` / `topic` 等
- **温度 / Top P / Max tokens**：见各文件的"Dify 应用配置"段

### 3. 拿到 API Key

每个应用 → 「API 访问」 → 复制 `API Key` → 填到 `.env` 的 `DIFY_API_KEY_<平台>`：

```bash
DIFY_APP_KEY_GONGZHONGHAO=app-xxxxx  # 公众号
DIFY_APP_KEY_XIAOHONGSHU=app-xxxxx    # 小红书
DIFY_APP_KEY_JUEJIN=app-xxxxx         # 掘金
DIFY_APP_KEY_ZHIHU=app-xxxxx          # 知乎
```

> 注意：每个平台**单独一个 API Key**（虽然我们推荐统一用 `DIFY_API_KEY` 单一 key 配 4 个应用，但分开配置更灵活）

### 4. 验证

```bash
# 任意一个应用做一次手动测试，确认 Dify 改写 OK
curl -X POST "https://api.dify.ai/v1/chat-messages" \
  -H "Authorization: Bearer $DIFY_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "inputs": {"input": "你的母稿", "topic": "AI 时代管理"},
    "user": "test",
    "response_mode": "blocking"
  }'
```

## 关联

- 这些 prompt 模板与 `pipeline/publish.py` 配合使用
- `n8n` workflow（`workflows/n8n/multi-platform-publish.json`）会自动调这些应用
- `web/` 控制台也可手动触发改写（v0.4 加入）
