#!/usr/bin/env python3
"""
Stage 6: publish — 多平台分发

支持的平台：
  - xiaohongshu:  ✅ xiaohongshu_poster.py（本地直发）
  - juejin:       📡 走 n8n webhook
  - sspai:        📡 走 n8n webhook
  - zhihu:        📡 走 n8n webhook
  - gongzhonghao: 📡 走 n8n webhook（走公众号官方 API）

v0.1.0 改造：4 个占位平台全部接入 n8n workflow，统一通过 webhook 触发
"新媒体一键发布平台"的 docker 部署，由 n8n 调 Dify 改写 + Playwright RPA
完成实际发布。
"""

import sys
import json
import shutil
import subprocess
import urllib.request
import urllib.parse
import urllib.error
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from state import (
    drafts_dir, read_draft, load_state, save_state, touch, now_iso, record_error,
    DEFAULT_VAULT,
)

HOME = Path.home()
POSTER = HOME / ".openclaw" / "workspace" / "xiaohongshu_poster.py"
ARTICLE_TXT = HOME / ".openclaw" / "workspace" / "article_to_post.txt"

VALUE_DIR = DEFAULT_VAULT / "00-转型·一人事业" / "04-原创写作专区" / "价值文章"


PLATFORM_STATUS = {
    "xiaohongshu": "✅",  # 本地直发
    "juejin": "📡",       # 走 n8n
    "sspai": "📡",        # 走 n8n
    "zhihu": "📡",        # 走 n8n
    "gongzhonghao": "📡", # 走 n8n
}


# ====== 本地直发（小红书）======

def publish_xiaohongshu(stored_dir: Path, meta: dict) -> dict:
    """包装 xiaohongshu_poster.py 发布。"""
    article = stored_dir / "article.md"
    if not article.exists():
        return {"ok": False, "error": "article.md 不存在"}

    text = article.read_text(encoding="utf-8")
    if text.startswith("---"):
        end = text.find("\n---\n", 4)
        if end > 0:
            text = text[end + 5:]

    title = meta.get("title", "未命名")
    body = text
    tags = meta.get("tags", [])

    parts = [f"# {title}", "---", body.strip()]
    if tags:
        parts.append("")
        parts.append(" ".join(f"#{t}" for t in tags))
    ARTICLE_TXT.write_text("\n".join(parts), encoding="utf-8")

    cover = stored_dir / "cover.png"
    if cover.exists():
        shutil.copy(cover, HOME / ".openclaw" / "workspace" / "article_cover.png")

    result = subprocess.run(["python3", str(POSTER), "post"], cwd=POSTER.parent, capture_output=True, text=True)
    return {
        "ok": result.returncode == 0,
        "returncode": result.returncode,
        "stdout": result.stdout[-500:] if result.stdout else "",
        "stderr": result.stderr[-500:] if result.stderr else "",
    }


# ====== n8n 触发（新媒体一键发布平台）======

# n8n webhook 路径
N8N_BASE_URL = "http://localhost:5678"  # docker 部署的 n8n
N8N_PUBLISH_WEBHOOK = "/webhook/multi-media-publish"  # n8n 工作流 webhook 路径

# 备选：从 .env 读
ENV_FILE = Path(__file__).resolve().parent.parent / ".env"


def _load_n8n_url() -> str:
    """从 .env 读 N8N_BASE_URL，没配就用默认。"""
    if not ENV_FILE.exists():
        return N8N_BASE_URL
    for line in ENV_FILE.read_text().splitlines():
        if line.startswith("N8N_PUBLISH_URL="):
            return line.split("=", 1)[1].strip().strip('"').strip("'")
    return N8N_BASE_URL


def _post_to_n8n(stored_dir: Path, meta: dict, platform: str) -> dict:
    """通过 n8n webhook 触发新媒体一键发布平台的工作流。"""
    article = stored_dir / "article.md"
    if not article.exists():
        return {"ok": False, "error": "article.md 不存在"}

    text = article.read_text(encoding="utf-8")
    if text.startswith("---"):
        end = text.find("\n---\n", 4)
        if end > 0:
            text = text[end + 5:]

    n8n_base = _load_n8n_url()
    webhook_url = f"{n8n_base}{N8N_PUBLISH_WEBHOOK}"

    payload = {
        "platform": platform,
        "title": meta.get("title", "未命名"),
        "body": text.strip(),
        "tags": meta.get("tags", []),
        "cover_url": meta.get("cover_url", ""),
        "draft_id": stored_dir.name,
        "callback_url": "",  # 后续加：发布完成回调
        "source": "auto-content-pipeline-publish",
        "ts": now_iso(),
    }

    try:
        req = urllib.request.Request(
            webhook_url,
            data=json.dumps(payload).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read().decode("utf-8"))
            return {
                "ok": result.get("ok", False),
                "via": "n8n",
                "execution_id": result.get("execution_id", ""),
                "url": result.get("url", ""),
                "error": result.get("error", ""),
            }
    except urllib.error.URLError as e:
        return {
            "ok": False,
            "via": "n8n",
            "error": f"n8n webhook 不可达 ({webhook_url}): {e}",
        }
    except Exception as e:
        return {
            "ok": False,
            "via": "n8n",
            "error": f"n8n 调用失败: {e}",
        }


def publish_juejin(stored_dir: Path, meta: dict) -> dict:
    """掘金：n8n workflow 调 Playwright RPA 或 API。"""
    return _post_to_n8n(stored_dir, meta, "juejin")


def publish_sspai(stored_dir: Path, meta: dict) -> dict:
    """少数派：n8n workflow 调 Playwright RPA。"""
    return _post_to_n8n(stored_dir, meta, "sspai")


def publish_zhihu(stored_dir: Path, meta: dict) -> dict:
    """知乎：n8n workflow 调 Playwright RPA 或 API。"""
    return _post_to_n8n(stored_dir, meta, "zhihu")


def publish_gongzhonghao(stored_dir: Path, meta: dict) -> dict:
    """公众号：n8n workflow 调公众号官方 API（稳定 + 合规）。"""
    return _post_to_n8n(stored_dir, meta, "gongzhonghao")


def main() -> int:
    if len(sys.argv) < 2:
        print("用法: pipeline.py publish <draft_id> [--platforms xiaohongshu,juejin,...]")
        print()
        print("可用平台：")
        for p, s in PLATFORM_STATUS.items():
            print(f"  {p:20s}  {s}  ({'本地直发' if s == '✅' else 'n8n workflow'})")
        sys.exit(1)

    draft_id = sys.argv[1]

    platforms = ["xiaohongshu"]
    for arg in sys.argv[2:]:
        if arg.startswith("--platforms="):
            platforms = arg.split("=", 1)[1].split(",")

    stored_dir = VALUE_DIR / draft_id
    if not stored_dir.exists():
        print(f"❌ vault 价值文章区不存在: {stored_dir}")
        print(f"   先跑 store stage")
        return 1

    meta_path = stored_dir / "meta.json"
    meta = {}
    if meta_path.exists():
        meta = json.loads(meta_path.read_text(encoding="utf-8"))

    print(f"\n=== publish stage: {draft_id} ===")
    print(f"title: {meta.get('title', '?')}")
    print(f"platforms: {platforms}")
    print()

    publish_handlers = {
        "xiaohongshu": publish_xiaohongshu,
        "juejin": publish_juejin,
        "sspai": publish_sspai,
        "zhihu": publish_zhihu,
        "gongzhonghao": publish_gongzhonghao,
    }

    results = {}
    for p in platforms:
        status = PLATFORM_STATUS.get(p, "?")
        print(f"  [{status}] {p} ...", end=" ", flush=True)
        handler = publish_handlers.get(p)
        if not handler:
            print(f"❌ 未知平台")
            results[p] = {"ok": False, "error": "未知平台"}
            continue
        r = handler(stored_dir, meta)
        results[p] = r
        if r.get("ok"):
            url = r.get("url", "")
            extra = f" → {url}" if url else ""
            print(f"✅{extra}")
        else:
            err = r.get("error") or r.get("stderr", "失败")
            print(f"❌ {err}")

    # 更新 meta.json
    published = meta.get("published_platforms", [])
    for p, r in results.items():
        if r.get("ok"):
            published.append({
                "platform": p,
                "url": r.get("url", ""),
                "published_at": now_iso(),
                "via": r.get("via", "local"),
                "execution_id": r.get("execution_id", ""),
            })
    meta["published_platforms"] = published
    meta["publish_status"] = "published" if all(r.get("ok") for r in results.values()) else "partially_published" if any(r.get("ok") for r in results.values()) else "failed"
    meta_path.write_text(json.dumps(meta, ensure_ascii=False, indent=2), encoding="utf-8")

    print(f"\n📊 结果汇总：")
    for p, r in results.items():
        icon = "✅" if r.get("ok") else "❌"
        detail = r.get("error") or r.get("url") or "OK"
        print(f"  {icon} {p}: {detail}")

    state = load_state()
    touch("publish", state)
    if any(r.get("ok") for r in results.values()):
        state["counters"]["published_total"] = state["counters"].get("published_total", 0) + 1
    save_state(state)
    return 0


if __name__ == "__main__":
    sys.exit(main())
