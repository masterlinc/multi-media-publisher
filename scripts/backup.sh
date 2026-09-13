#!/bin/bash
# ============================================================
# 新媒体一键发布平台 - 备份脚本
# 用法: ./scripts/backup.sh
# ============================================================

set -e

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

BACKUP_DIR="$PROJECT_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="backup_${TIMESTAMP}.tar.gz"

# 颜色输出
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info() { echo -e "${GREEN}[INFO]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

mkdir -p "$BACKUP_DIR"

info "开始备份..."
info "备份目录: $PROJECT_DIR"
info "备份文件: $BACKUP_FILE"

# 需要备份的目录
BACKUP_TARGETS=(
    "n8n"
    "minio"
    "uptime-kuma"
    ".env"
    "docker-compose.yml"
    "feishu"
    "workflows"
)

# 检查目录是否存在
TARGETS_TO_BACKUP=()
for target in "${BACKUP_TARGETS[@]}"; do
    if [ -e "$target" ]; then
        TARGETS_TO_BACKUP+=("$target")
    else
        warn "跳过不存在的: $target"
    fi
done

# 执行备份
tar -czf "$BACKUP_DIR/$BACKUP_FILE" "${TARGETS_TO_BACKUP[@]}" 2>/dev/null || true

# 计算文件大小
FILE_SIZE=$(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)

info "备份完成!"
info "文件: $BACKUP_DIR/$BACKUP_FILE"
info "大小: $FILE_SIZE"

# 清理7天前的备份
info "清理7天前的旧备份..."
find "$BACKUP_DIR" -name "backup_*.tar.gz" -mtime +7 -delete 2>/dev/null || true

info "备份任务完成!"
echo ""
info "恢复备份命令:"
echo "  tar -xzf $BACKUP_DIR/$BACKUP_FILE -C $PROJECT_DIR"
