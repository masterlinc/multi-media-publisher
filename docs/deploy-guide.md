# 部署指南 · v0.5 端到端

> 从零启动 multi-media-publisher 完整链路，预计 30-45 分钟。

## 一、准备

| 资源 | 用途 | 怎么拿 |
|---|---|---|
| Mac mini / Linux 服务器 | 跑 docker compose | — |
| 域名 + 公网 IP（可选） | 飞书事件订阅回调 | 阿里云 / 腾讯云 |
| 飞书企业管理员账号 | 创建飞书应用 | open.feishu.cn |
| 飞书多维表格 | 内容库 | 飞书 → 新建多维表格 |
| 各平台账号 | 发布用 | 公众号 / 小红书 / 微博等 |

## 二、30 分钟快速启动

### 1. 克隆 + 配置

```bash
git clone https://github.com/masterlinc/multi-media-publisher.git
cd multi-media-publisher
cp .env.example .env
chmod 600 .env
```

### 2. 填凭证

```bash
bash scripts/setup_credentials.sh
```

按提示填：
- 飞书 AppID / AppSecret / 多维表格 Token / Table ID / 机器人 Webhook
- Dify API URL / API Key
- 公众号 AppID / AppSecret
- 微博 Access Token
- MiniMax API Key
- n8n Publish URL

或者手动编辑 `.env`。

### 3. 启动 docker compose

```bash
docker compose up -d
```

启动后（等 60 秒）：

| 服务 | URL | 凭证 |
|---|---|---|
| **Web 控制台** | http://localhost:8090 | （无） |
| n8n | http://localhost:5678 | `N8N_USER` / `N8N_PASSWORD` |
| MinIO | http://localhost:9001 | `MINIO_USER` / `MINIO_PASSWORD` |
| Uptime Kuma | http://localhost:3001 | 首次访问设置 |
| Playwright | http://localhost:3000 | （无） |

### 4. 安装安全钩子

```bash
bash scripts/security/install-hooks.sh
```

### 5. 验证连通

```bash
bash scripts/verify_credentials.sh
```

## 三、配置 Dify（10 分钟）

### 1. 启动 Dify（如果还没跑）

```bash
# 单独部署 Dify
git clone https://github.com/langgenius/dify.git
cd dify/docker
cp .env.example .env
docker compose up -d
```

访问 http://localhost 完成初始化。

### 2. 创建 4 个改写应用

按 `dify/apps/改写-多平台/` 里的 4 个 prompt 创建应用：

| 应用名 | prompt 文件 | 模型建议 |
|---|---|---|
| `改写-公众号` | `公众号.md` | MiniMax-M2 / GPT-4 / Claude |
| `改写-小红书` | `小红书.md` | 同上 |
| `改写-掘金` | `掘金.md` | 同上 |
| `改写-知乎` | `知乎.md` | 同上 |

每应用配置：
- Inputs: `input` / `topic` / `title_hint` 等（按 prompt 模板）
- Temperature: 0.5-0.8
- Max tokens: 1500-5000

### 3. 拿 API Key

每应用 → API 访问 → 复制 Key → 填到 `.env`：

```bash
DIFY_API_KEY=app-xxxxx
```

## 四、配置 n8n（10 分钟）

### 1. 访问 n8n

http://localhost:5678 → 用 `.env` 里的 N8N_USER / N8N_PASSWORD 登录

### 2. 导入 workflow

顶部菜单 → Workflows → Import from File → 选 `workflows/n8n/multi-platform-publish.json`

会看到 8 节点工作流：
1. Webhook 触发
2. 提取变量
3. 按平台分支
4. 公众号：调微信 API 建草稿
5. Playwright RPA
6. 飞书回调（写回多维表格）
7. 飞书机器人通知
8. 返回 JSON 结果

### 3. 配凭证

在 n8n → Credentials → 加：
- **WECHAT_ACCESS_TOKEN** — 公众号 access_token（每 2 小时过期，配定时刷新）
- **FEISHU_BOT_WEBHOOK** — 飞书群机器人 webhook

在 n8n → Settings → Variables：
- `FEISHU_APP_ID` / `FEISHU_APP_SECRET`（公众号）
- `FEISHU_BITABLE_TOKEN` / `FEISHU_TABLE_ID`（多维表格）

### 4. 激活 workflow

右上角「Active」开关打开。

### 5. 测试

```bash
curl -X POST http://localhost:5678/webhook/multi-media-publish \
  -H "Content-Type: application/json" \
  -d '{
    "platform": "gongzhonghao",
    "title": "测试标题",
    "body": "# 测试\n\n这是测试正文。",
    "tags": ["测试"],
    "draft_id": "test-001"
  }'
```

## 五、配置飞书（10 分钟）

### 1. 创建飞书应用

1. https://open.feishu.cn/app → 创建企业自建应用
2. 拿 AppID / AppSecret → 填到 `.env` 的 `FEISHU_APP_ID` / `FEISHU_APP_SECRET`
3. 权限管理 → 勾选：
   - `bitable:app`（多维表格读写）
   - `im:message` / `im:message:send_as_bot`（发消息）
   - `docx:document`（云文档）
4. 「添加应用能力」→ 启用「机器人」
5. 应用发布 → 审核通过

### 2. 创建多维表格

按 `feishu/多维表格设计.md` 建表，20 个字段。

把表链接复制出来：
```
https://<tenant>.feishu.cn/base/<FEISHU_BITABLE_TOKEN>?table=<FEISHU_TABLE_ID>
```

填到 `.env`：
- `FEISHU_BITABLE_TOKEN` = `bseXXX` 那段
- `FEISHU_TABLE_ID` = `tblXXX` 那段

### 3. 加应用为协作者

打开多维表格 → 分享 → 添加协作者 → 搜你刚创建的应用 → 「可编辑」

### 4. 创建群机器人

飞书群 → 设置 → 群机器人 → 添加 → 自定义机器人 → 拿 Webhook URL

填到 `.env` 的 `FEISHU_BOT_WEBHOOK`

## 六、创建 n8n 定时任务

让飞书多维表格变更自动触发 n8n：

### 1. 飞书侧

1. 应用后台 → 事件订阅
2. 请求 URL：`http://<你的IP>:5678/webhook/feishu-trigger`
3. 添加事件：`drive.file.bitable_record_changed_v1`
4. 飞书会发验证请求，n8n 工作流要返回 challenge

### 2. n8n 侧

新建一个 Workflow：
- 触发：Webhook
- 节点：HTTP Request → 调 feishu-ws-bridge → 自动触发 multi-platform-publish

## 七、端到端测试

### 1. 在多维表格里新建一条

填字段：
- 标题：测试文章
- 母稿：（任意 markdown 内容）
- 主题标签：测试
- 状态：待改写

### 2. 触发工作流

- 飞书侧：n8n 自动监听，1-3 秒触发
- n8n 侧：执行 multi-platform-publish
- 发布：1-5 分钟完成

### 3. 验证

- 飞书多维表格：状态字段变成「已发布」
- 飞书群：收到「✅ [平台] 发布成功」通知
- 各平台：能看到发布的内容

## 八、生产部署建议

### HTTPS + 反向代理

用 nginx + Let's Encrypt：

```nginx
server {
    listen 443 ssl;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain/privkey.pem;

    location / {
        proxy_pass http://127.0.0.1:8090;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
```

### 备份

```bash
# 加进 crontab，每天 3am
0 3 * * * cd /path/to/multi-media-publisher && bash scripts/backup.sh
```

### 监控

Uptime Kuma 加：
- http://localhost:8090/api/health
- http://localhost:5678/healthz
- http://localhost/v1/health (Dify)
- 各平台 API 状态

## 九、常见问题

| 问题 | 原因 | 解决 |
|---|---|---|
| 飞书 API 报 99992361 | AppID 跨 app 串了 | 用 lark-cli 当前 app 下的真实 open_id |
| 公众号发布失败 access_token invalid | token 过期 | 配 cron 定时刷新（每 2 小时） |
| 小红书 Playwright 失败 | cookie 过期 | `python3 ~/.openclaw/workspace/xiaohongshu_poster.py login` 重新登录 |
| n8n 收不到飞书事件 | 公网访问不到 | 用 ngrok / frp / 云服务器 |
| Dify 改写慢 | 模型响应慢 | 换更快的模型（DeepSeek-V3） |

## 十、相关资源

- [README.md](../README.md) — 项目概览
- [SECURITY.md](SECURITY.md) — 安全最佳实践
- [Dify 改写模板](../dify/apps/改写-多平台/) — 4 套 prompt
- [n8n workflow](../workflows/n8n/multi-platform-publish.json) — 多平台发布工作流
- [飞书配置指南](../feishu/飞书配置指南.md) — 飞书开发者后台配置
- [产品路线图](https://dcnzcdpxknwp.feishu.cn/docx/HDN2dzFpWoVTNcxy1qUcrET2nBb) — 飞书云文档
