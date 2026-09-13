# multi-media-publisher

> **AI Native 多平台内容自动发布系统** · 自托管 · v0.1.0
> 一篇母稿 → AI 改写 → 一键发布到 6 个平台

[![GitHub](https://img.shields.io/badge/GitHub-masterlinc%2Fmulti--media--publisher-blue)](https://github.com/masterlinc/multi-media-publisher)
[![License](https://img.shields.io/badge/license-MIT-green)](LICENSE)
[![Docker](https://img.shields.io/badge/docker-compose-blue)](docker-compose.yml)

---

## 这是什么

把"内容创作 → 多平台分发"做成端到端自动化：

```
你的母稿（vault 草稿 / 飞书多维表格）
        ↓
   n8n 触发（事件订阅 / 定时 / 手动）
        ↓
   Dify AI 改写（4 套风格模板：公众号/网红/极客/dankoe）
        ↓
   Playwright RPA（小红书/掘金/知乎/微博/少数派）
   公众号 API（官方接口）
        ↓
   飞书机器人推送结果 + 写回多维表格状态
```

**对标产品**：壹伴助手 / 新榜矩阵通 / 蚁小二
**差异化**：开源 + 自托管 + AI 改写强 + 完整工作流 + 数据不出门

---

## 快速开始

### 1. 克隆 + 启动

```bash
git clone https://github.com/masterlinc/multi-media-publisher.git
cd multi-media-publisher
docker compose up -d
```

服务启动后（等 30-60 秒）：

| 服务 | 端口 | 用途 |
|---|---|---|
| **n8n** | http://localhost:5678 | 工作流引擎（调度核心） |
| **Dify** | http://localhost | AI 改写引擎 |
| **MinIO** | http://localhost:9001 | 素材存储（封面/配图/视频） |
| **Uptime Kuma** | http://localhost:3001 | 服务监控 |
| **Playwright** | http://localhost:3000 | 浏览器自动化 |
| **飞书 WS Bridge** | - | 飞书事件订阅 + WS 桥接 |

### 2. 配置凭证

```bash
bash scripts/setup_credentials.sh
```

按提示填入：
- 飞书 AppID / AppSecret / 多维表格 Token
- Dify API URL / API Key
- 公众号 AppID / AppSecret
- 各平台 cookie（可选）

### 3. 验证连通

```bash
bash scripts/verify_credentials.sh
```

### 4. 创建飞书多维表格

按 `feishu/多维表格设计.md` 建表，参考 `feishu/飞书配置指南.md` 配置。

### 5. 在 n8n 创建 publish workflow

新建一个 Workflow：
- **Webhook 节点**：Path = `multi-media-publish`，Method = POST
- 接收 JSON payload（title / body / tags / platform / cover_url）
- 根据 `platform` 字段走不同分支：
  - `gongzhonghao` → HTTP Request 调公众号 API
  - `xiaohongshu/juejin/sspai/zhihu/weibo` → Playwright 节点
- 写回飞书多维表格的"状态"字段
- 飞书机器人发通知

详细 workflow JSON 见 `workflows/n8n/multi-platform-publish.json`（v0.2 即将提供）

### 6. 跑一次发布

```bash
# 通过 pipeline CLI（适合本地草稿）
python3 pipeline/publish.py <draft_id> --platforms=xiaohongshu,juejin,gongzhonghao

# 通过飞书多维表格触发（在 n8n workflow 配好后）
# 改状态字段为"待发布"，n8n 自动监听 bitable.record.changed_v1 事件
```

---

## 架构

```
飞书 (前端)                        self-hosted 后端
┌──────────────┐    Webhook    ┌──────────────────────┐
│ 多维表格      │ ◄──────────► │  n8n (5678)            │
│ (内容库)      │              │  - 调度/触发/分发      │
├──────────────┤              └──────┬───────────────┘
│ 飞书文档      │    API调用         │
│ (母稿创作)    │ ◄──────────► ┌─────▼────────────┐
├──────────────┤              │  Dify            │
│ 飞书机器人    │    HTTP        │  - AI 改写 4 风格 │
│ (通知)        │ ◄──────────► └───────────────┘
└──────────────┘              ┌───────────────┐
                              │  Playwright    │
                              │  - RPA 多平台  │
                              └───────┬───────┘
                                      │
                              ┌───────▼───────┐
                              │  MinIO         │
                              │  - 素材存储    │
                              └───────────────┘
```

---

## 仓库结构

```
multi-media-publisher/
├── README.md                 # 本文档
├── docker-compose.yml        # 核心服务编排
├── .env.example              # 凭证模板
├── .gitignore
├── LICENSE                   # MIT
│
├── pipeline/                 # 内容打磨 + 发布 CLI（auto-content-pipeline v0.1）
│   └── publish.py            # 多平台分发：4 个走 n8n webhook，1 个本地直发
│
├── feishu/                  # 飞书配置文档
│   ├── 飞书配置指南.md
│   ├── 多维表格设计.md
│   └── 事件订阅配置.md
│
├── scripts/                  # 辅助脚本
│   ├── setup_credentials.sh  # 引导式填凭证
│   ├── verify_credentials.sh # 凭证连通性检查
│   ├── deploy.sh             # 一键部署
│   └── backup.sh             # 数据备份
│
├── workflows/                # 工作流配置
│   └── n8n/                  # n8n workflow 导出（v0.2 提供）
│
├── dify/                     # Dify 配置（v0.2 提供）
│   └── apps/                 # Dify 应用导出
│
├── docker/                   # Dockerfile 集合
│   ├── n8n/
│   ├── dify/
│   └── feishu-ws-bridge/
│
├── n8n/                      # n8n 数据（gitignore）
├── minio/                    # MinIO 数据（gitignore）
├── uptime-kuma/              # 监控数据（gitignore）
│
├── docs/                     # 用户文档
│   ├── quickstart.md
│   ├── feishu-setup.md
│   ├── platform-cookies.md
│   └── api.md
│
└── README-assets/            # README 图片素材
    └── architecture.png
```

---

## 路线图

| 版本 | 目标 | 状态 |
|---|---|---|
| **v0.1.0**（当前）| docker 一键启 + 凭证配置 + publish.py 调 n8n + 5 平台骨架 | ✅ |
| v0.2 | 完整 n8n workflow 模板 + Dify 4 风格改写应用 + 飞书多维表格触发 | 🚧 |
| v0.3 | Web 控制台（平台配置/发布控制/用量查看）+ 多租户 | 📋 |
| v0.4 | 计费系统（微信/支付宝）+ 订阅管理 | 📋 |
| v1.0 | 公开 SaaS 版本 | 📋 |

完整路线图见 `docs/product-roadmap.md`

---

## 核心依赖

| 组件 | 用途 | 端口 |
|---|---|---|
| [n8n](https://n8n.io/) | 工作流引擎 | 5678 |
| [Dify](https://dify.ai/) | AI 应用平台（4 风格改写） | 80 / 3002 |
| [MinIO](https://min.io/) | 对象存储（素材） | 9000-9001 |
| [Playwright](https://playwright.dev/) | 浏览器自动化（RPA） | 3000 |
| [Uptime Kuma](https://uptime.kuma.pet/) | 服务监控 | 3001 |
| [PostgreSQL](https://www.postgresql.org/) | 数据库 | 5432 |
| [Redis](https://redis.io/) | 缓存/队列 | 6379 |

---

## 安全

- `.env` 不要提交到 git（已在 .gitignore）
- `setup_credentials.sh` 写入后建议 `chmod 600 .env`
- 飞书 / 公众号 / 各平台 AppID 是租户级 —— **不要共享**
- 启用 HTTPS（生产环境用 nginx + Let's Encrypt）
- 飞书机器人 Webhook 建议开"签名校验"

---

## 贡献

欢迎 PR！特别需要：
- 更多平台的 publish handler（LinkedIn / Medium / X）
- Dify 改写 prompt 模板
- n8n workflow 模板
- 文档改进

---

## 许可

MIT — 详见 [LICENSE](LICENSE)

---

## 相关资源

- [auto-content-pipeline](https://github.com/masterlinc/auto-content-pipeline) — 上游单机版内容打磨 CLI
- [产品路线图文档](https://dcnzcdpxknwp.feishu.cn/docx/HDN2dzFpWoVTNcxy1qUcrET2nBb) — 飞书云文档
- [Issue Tracker](https://github.com/masterlinc/multi-media-publisher/issues) — 反馈 bug
- [Discussions](https://github.com/masterlinc/multi-media-publisher/discussions) — 讨论

---

**Built with ❤️ for the open-source content creator community.**
