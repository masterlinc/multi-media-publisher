#!/bin/bash
# ============================================================
# 新媒体一键发布平台 - 部署脚本
# 用法: ./scripts/deploy.sh [core|dify|all]
# ============================================================

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

# 检查 Docker
check_docker() {
    if ! command -v docker &> /dev/null; then
        error "Docker 未安装，请先安装 Docker Desktop"
        exit 1
    fi
    if ! docker info &> /dev/null; then
        error "Docker 未运行，请先启动 Docker Desktop"
        exit 1
    fi
    info "Docker 版本: $(docker --version)"
    info "Docker Compose 版本: $(docker compose version)"
}

# 检查 .env
check_env() {
    if [ ! -f .env ]; then
        error ".env 文件不存在，请先复制并配置"
        exit 1
    fi
    # 检查是否修改了默认密码
    if grep -q "ChangeMe" .env; then
        warn "检测到默认密码未修改，建议修改 .env 中的密码"
    fi
}

# 部署核心服务
deploy_core() {
    info "启动核心服务 (n8n + MinIO + Uptime Kuma + Playwright)..."
    docker compose up -d

    info "等待服务启动..."
    sleep 10

    # 检查服务状态
    echo ""
    info "服务状态:"
    docker compose ps

    echo ""
    info "=========================================="
    info "  核心服务部署完成！"
    info "=========================================="
    info "  n8n:          http://localhost:5678"
    info "  MinIO控制台:   http://localhost:9001"
    info "  Uptime Kuma:  http://localhost:3001"
    info "  Playwright:    http://localhost:3000"
    info "=========================================="
}

# 部署 Dify
deploy_dify() {
    if [ -d "dify" ]; then
        warn "dify 目录已存在，跳过克隆"
    else
        info "克隆 Dify 仓库..."
        git clone https://github.com/langgenius/dify.git
    fi

    cd dify/docker

    if [ ! -f .env ]; then
        info "复制 Dify 环境配置..."
        cp .env.example .env
        warn "请修改 dify/docker/.env 中的 SECRET_KEY 和密码"
    fi

    info "启动 Dify 服务..."
    docker compose up -d

    cd "$PROJECT_DIR"

    echo ""
    info "=========================================="
    info "  Dify 部署完成！"
    info "=========================================="
    info "  Dify: http://localhost"
    info "  首次访问请设置管理员账号"
    info "=========================================="
}

# 主逻辑
case "${1:-all}" in
    core)
        check_docker
        check_env
        deploy_core
        ;;
    dify)
        check_docker
        deploy_dify
        ;;
    all)
        check_docker
        check_env
        deploy_core
        echo ""
        deploy_dify
        ;;
    *)
        echo "用法: $0 [core|dify|all]"
        echo "  core  - 仅部署核心服务 (n8n + MinIO + 监控 + Playwright)"
        echo "  dify  - 仅部署 Dify (AI应用平台)"
        echo "  all   - 部署全部服务 (默认)"
        exit 1
        ;;
esac
