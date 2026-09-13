FROM python:3.11-slim

WORKDIR /app

# 系统依赖
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*

# 装依赖
COPY web/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt

# 复制整个项目（需要 pipeline/ + vault 等）
COPY . /app/

# v0.5 默认端口
ENV WEB_PORT=8090
ENV PYTHONUNBUFFERED=1

# 健康检查
HEALTHCHECK --interval=30s --timeout=5s \
    CMD curl -f http://localhost:${WEB_PORT}/api/health || exit 1

EXPOSE 8090

# 启动 web 服务
CMD ["python3", "-m", "uvicorn", "web.server:app", "--host", "0.0.0.0", "--port", "8090", "--log-level", "info"]
