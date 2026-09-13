"""
web/server.py — multi-media-publisher Web 入口

跑在宿主机（不是 docker 容器）端口 8090，提供：
  - GET  /                  单页 UI
  - GET  /api/credentials   读取 .env 当前凭证（脱敏）
  - POST /api/credentials   更新 .env
  - GET  /api/drafts        列出 vault 价值文章区
  - POST /api/publish       触发 publish.py（多平台分发）
  - GET  /api/services      各 docker 服务健康状态
  - GET  /api/health        web 服务自身健康

启动：uvicorn web.server:app --host 0.0.0.0 --port 8090
或：  python3 web/server.py
"""

import os
import sys
import json
import shutil
import subprocess
import re
import secrets
from pathlib import Path
from typing import Optional

try:
    from fastapi import FastAPI, HTTPException, Request, Form
    from fastapi.responses import HTMLResponse, JSONResponse
    from fastapi.staticfiles import StaticFiles
    from fastapi.templating import Jinja2Templates
    import uvicorn
except ImportError:
    print("❌ 缺少依赖：fastapi / uvicorn / jinja2")
    print("   pip install -r web/requirements.txt")
    sys.exit(1)

# ============== 路径 ==============
ROOT_DIR = Path(__file__).resolve().parent.parent
WEB_DIR = Path(__file__).resolve().parent
TEMPLATES_DIR = WEB_DIR / "templates"
STATIC_DIR = WEB_DIR / "static"
ENV_FILE = ROOT_DIR / ".env"
ENV_EXAMPLE = ROOT_DIR / ".env.example"
PUBLISH_PY = ROOT_DIR / "pipeline" / "publish.py"

VAULT_PATH = Path.home() / "Documents" / "Obsidian Vault" / "00-转型·一人事业" / "04-原创写作专区" / "价值文章"

# ============== 凭证定义（哪些 key 在 Web UI 里可编辑）==============
# 每个 key 显示中文名、是否脱敏（敏感字段）
EDITABLE_CREDENTIALS = [
    # 飞书
    {"key": "FEISHU_APP_ID",        "name": "飞书 App ID",       "secret": False, "category": "feishu"},
    {"key": "FEISHU_APP_SECRET",    "name": "飞书 App Secret",   "secret": True,  "category": "feishu"},
    {"key": "FEISHU_BITABLE_TOKEN", "name": "多维表格 Token",    "secret": True,  "category": "feishu"},
    {"key": "FEISHU_TABLE_ID",      "name": "多维表格 Table ID", "secret": False, "category": "feishu"},
    {"key": "FEISHU_BOT_WEBHOOK",   "name": "飞书机器人 Webhook", "secret": True, "category": "feishu"},

    # Dify
    {"key": "DIFY_API_URL",         "name": "Dify API URL",      "secret": False, "category": "dify"},
    {"key": "DIFY_API_KEY",         "name": "Dify API Key",      "secret": True,  "category": "dify"},

    # 公众号
    {"key": "WECHAT_APP_ID",        "name": "公众号 AppID",      "secret": False, "category": "wechat"},
    {"key": "WECHAT_APP_SECRET",    "name": "公众号 AppSecret",  "secret": True,  "category": "wechat"},

    # 微博
    {"key": "WEIBO_ACCESS_TOKEN",   "name": "微博 Access Token", "secret": True,  "category": "weibo"},

    # AI
    {"key": "MINIMAX_API_KEY",      "name": "MiniMax API Key",  "secret": True,  "category": "ai"},
    {"key": "MINIMAX_MODEL",        "name": "AI 模型",           "secret": False, "category": "ai"},

    # n8n
    {"key": "N8N_PUBLISH_URL",      "name": "n8n Publish URL",   "secret": False, "category": "n8n"},
]

# ============== App ==============
app = FastAPI(
    title="multi-media-publisher",
    description="多平台 AI 内容自动发布系统 — Web 入口",
    version="0.2.0",
    docs_url="/api/docs",
    redoc_url=None,
)

app.mount("/static", StaticFiles(directory=str(STATIC_DIR)), name="static")
templates = Jinja2Templates(directory=str(TEMPLATES_DIR))


# ============== 工具函数 ==============

def _read_env() -> dict:
    """读取 .env，返回 {key: value} 字典（保留注释和空行）。"""
    if not ENV_FILE.exists():
        return {}
    env = {}
    for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")
    return env


def _write_env(env: dict) -> None:
    """把 {key: value} 字典写回 .env（保留注释和格式）。"""
    # 先读现有文件保留注释
    if ENV_FILE.exists():
        existing_lines = ENV_FILE.read_text(encoding="utf-8").splitlines()
    else:
        existing_lines = []

    # 构建新的 env 行：每个 key 一行
    new_lines = []
    keys_written = set()
    for line in existing_lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            new_lines.append(line)
            continue
        k = stripped.split("=", 1)[0].strip()
        if k in env:
            new_lines.append(f"{k}={env[k]}")
            keys_written.add(k)
        else:
            new_lines.append(line)

    # 添加新 key
    for k, v in env.items():
        if k not in keys_written:
            new_lines.append(f"{k}={v}")

    ENV_FILE.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
    ENV_FILE.chmod(0o600)


def _mask(value: str) -> str:
    """凭证脱敏（保留前 4 + 后 4 字符）。"""
    if not value or len(value) < 8:
        return "***"
    return f"{value[:4]}***{value[-4:]}"


def _list_drafts() -> list:
    """列出 vault 价值文章区的所有文章。"""
    if not VAULT_PATH.exists():
        return []
    drafts = []
    for d in sorted(VAULT_PATH.iterdir(), key=lambda x: x.name, reverse=True):
        if not d.is_dir() or d.name.startswith("."):
            continue
        article = d / "article.md"
        meta = d / "meta.json"
        title = d.name
        size = 0
        publish_status = "unknown"
        if article.exists():
            size = article.stat().st_size
            text = article.read_text(encoding="utf-8", errors="ignore")
            # 提取第一个 # 标题
            for line in text.splitlines():
                if line.startswith("# "):
                    title = line[2:].strip()
                    break
        if meta.exists():
            try:
                m = json.loads(meta.read_text(encoding="utf-8"))
                publish_status = m.get("publish_status", "unknown")
            except Exception:
                pass
        drafts.append({
            "draft_id": d.name,
            "title": title,
            "size_bytes": size,
            "publish_status": publish_status,
            "has_article": article.exists(),
            "has_meta": meta.exists(),
            "modified": d.stat().st_mtime,
        })
    return drafts


def _check_services() -> dict:
    """检查各 docker 服务健康。"""
    import urllib.request
    import urllib.error
    services = {
        "n8n":     "http://localhost:5678/healthz",
        "dify":     "http://localhost/v1/health",
        "minio":   "http://localhost:9000/minio/health/live",
        "uptime":  "http://localhost:3001",
        "playwright": "http://localhost:3000",
    }
    results = {}
    for name, url in services.items():
        try:
            req = urllib.request.Request(url, method="GET")
            with urllib.request.urlopen(req, timeout=3) as resp:
                results[name] = {"ok": resp.status < 500, "status": resp.status, "url": url}
        except Exception as e:
            results[name] = {"ok": False, "error": str(e)[:80], "url": url}
    return results


# ============== 路由 ==============

@app.get("/", response_class=HTMLResponse)
async def index(request: Request):
    """主页面：单页 UI。"""
    return templates.TemplateResponse("index.html", {
        "request": request,
        "credentials": [
            {**c, "current": _mask(_read_env().get(c["key"], "")) if c["secret"]
                       else _read_env().get(c["key"], "")}
            for c in EDITABLE_CREDENTIALS
        ],
        "version": "0.2.0",
    })


@app.get("/api/health")
async def health():
    return {"ok": True, "service": "web", "version": "0.2.0"}


@app.get("/api/credentials")
async def get_credentials():
    """读取当前 .env 凭证（敏感字段脱敏）。"""
    env = _read_env()
    return {
        "credentials": [
            {
                **c,
                "value": (
                    _mask(env[c["key"]])
                    if c["secret"] and env.get(c["key"])
                    else env.get(c["key"], "")
                ),
            }
            for c in EDITABLE_CREDENTIALS
        ],
        "env_exists": ENV_FILE.exists(),
        "example_exists": ENV_EXAMPLE.exists(),
        "ts": __import__("datetime").datetime.now().isoformat(),
    }


@app.post("/api/credentials")
async def update_credentials(request: Request):
    """批量更新 .env 凭证。"""
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="invalid JSON body")

    env = _read_env()
    updated = []
    for item in body.get("credentials", []):
        key = item.get("key")
        value = item.get("value", "").strip()
        if not key or not value:
            continue
        env[key] = value
        updated.append(key)

    if updated:
        _write_env(env)

    return {"ok": True, "updated": updated, "count": len(updated)}


@app.get("/api/drafts")
async def list_drafts():
    """列出 vault 价值文章。"""
    return {"drafts": _list_drafts(), "vault": str(VAULT_PATH)}


@app.get("/api/services")
async def get_services():
    """检查各服务健康。"""
    return {"services": _check_services()}


@app.post("/api/publish")
async def trigger_publish(request: Request):
    """触发多平台发布。"""
    try:
        body = await request.json()
    except Exception:
        raise HTTPException(status_code=400, detail="invalid JSON body")

    draft_id = body.get("draft_id", "").strip()
    platforms = body.get("platforms", ["xiaohongshu"])

    if not draft_id:
        raise HTTPException(status_code=400, detail="draft_id required")
    if not platforms:
        raise HTTPException(status_code=400, detail="platforms required")

    # 检查 draft 是否存在
    stored_dir = VAULT_PATH / draft_id
    if not stored_dir.exists():
        raise HTTPException(status_code=404, detail=f"draft {draft_id} not found in vault")

    # 调用 publish.py
    if not PUBLISH_PY.exists():
        raise HTTPException(status_code=500, detail=f"publish.py not found: {PUBLISH_PY}")

    cmd = ["python3", str(PUBLISH_PY), draft_id, f"--platforms={','.join(platforms)}"]
    try:
        result = subprocess.run(
            cmd,
            cwd=str(ROOT_DIR),
            capture_output=True,
            text=True,
            timeout=120,
        )
        return {
            "ok": result.returncode == 0,
            "returncode": result.returncode,
            "stdout": result.stdout,
            "stderr": result.stderr,
            "cmd": " ".join(cmd),
        }
    except subprocess.TimeoutExpired:
        raise HTTPException(status_code=504, detail="publish timeout after 120s")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# ============== 启动 ==============

if __name__ == "__main__":
    print("=" * 60)
    print(" multi-media-publisher Web UI")
    print(" http://localhost:8090")
    print("=" * 60)
    print(f" Vault: {VAULT_PATH}")
    print(f" Env:   {ENV_FILE}")
    print()
    uvicorn.run(app, host="0.0.0.0", port=8090, log_level="info")
