# n8n workflow 模板

> n8n 工作流导出（JSON），开箱即用。

## 包含的 workflow

| 文件 | 触发 | 功能 |
|---|---|---|
| [`multi-platform-publish.json`](multi-platform-publish.json) | Webhook POST /multi-media-publish | 接收发布请求 → 按平台分支 → 调微信 API / Playwright RPA → 飞书回写 + 机器人通知 |

## 部署步骤

### 1. 启动 n8n（已有）

```bash
# media-n8n 在 docker compose 里已经跑
docker ps | grep media-n8n
```

访问 http://localhost:5678 完成初始化。

### 2. 导入 workflow

1. 登录 n8n
2. 顶部菜单「Workflows」→「Import from File...」
3. 选 `multi-platform-publish.json`
4. 导入成功后会看到 8 个节点：
   - Webhook 触发
   - 提取变量
   - 按平台分支
   - 公众号：调微信 API
   - Playwright RPA（小红书/掘金/知乎/微博）
   - 飞书回调（写回多维表格）
   - 飞书机器人通知
   - 返回 JSON 结果

### 3. 配置凭证

在 n8n 凭证管理加：
- **WECHAT_ACCESS_TOKEN** — 公众号 access_token（每 2 小时过期，需要定时刷新）
- **FEISHU_BOT_WEBHOOK** — 飞书群机器人 webhook URL

在 n8n 环境变量加（或写到 .env）：
- `WECHAT_APP_ID` / `WECHAT_APP_SECRET`（公众号）
- `FEISHU_BITABLE_TOKEN` / `FEISHU_TABLE_ID`（多维表格）

### 4. 测试

```bash
curl -X POST http://localhost:5678/webhook/multi-media-publish \
  -H "Content-Type: application/json" \
  -d '{
    "platform": "gongzhonghao",
    "title": "测试文章标题",
    "body": "# 测试\n\n这是测试正文。",
    "tags": ["测试"],
    "draft_id": "test-001",
    "cover_url": ""
  }'
```

## Webhook 接口规范

### 请求

```json
POST /webhook/multi-media-publish
Content-Type: application/json

{
  "platform": "gongzhonghao | xiaohongshu | juejin | sspai | zhihu | weibo",
  "title": "文章标题",
  "body": "Markdown 正文",
  "tags": ["标签1", "标签2"],
  "draft_id": "draft-2026-09-XX_xxx",
  "cover_url": "https://..."  // 可选
}
```

### 响应

```json
{
  "ok": true,
  "platform": "gongzhonghao",
  "url": "https://mp.weixin.qq.com/...",
  "media_id": "draft_xxx",
  "via": "wechat-api",
  "published_at": "2026-09-08T10:30:00Z"
}
```

## 扩展

### 加新平台

1. 在 n8n workflow 「按平台分支」加一个新 case
2. 节点用 `n8n-nodes-base.httpRequest` 调对应 API
3. 在 Web UI 的 `<input class="platform-cb">` 加新 checkbox

### 失败重试

n8n 的 `Settings → Error Workflow` 设重试：
- 立即重试 1 次
- 失败后 1 分钟再试
- 最多 3 次
- 终失败 → 飞书机器人告警
