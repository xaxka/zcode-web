# ZCode Web（智谱 AI 编程工作台）路由器部署

在无图形界面的 ARM64 路由器上，通过 Docker 运行 ZCode 官方命令行发行包（`zcode --web`，纯 Node 服务，无 Electron / GUI 依赖），浏览器访问 `http://<路由器IP>:3030`。

镜像 `ghcr.io/xixka/zcode-web` 由 GitHub Actions 从 [zai-org/ZCode](https://github.com/zai-org/ZCode) 官方源码构建（amd64 / arm64 双架构），包含完整 Web 工作台与 Agent 运行时。

## 镜像

| Tag | 说明 |
| --- | --- |
| `ghcr.io/xixka/zcode-web:latest` | 多架构（amd64 + arm64），路由器直接拉取 |
| `ghcr.io/xixka/zcode-web:<version>` | 指定 ZCode 版本 |
| `ghcr.io/xixka/zcode-web:latest-arm64` | 仅 ARM64 |

## 路由器部署步骤

### 1. 预检（任一不满足则停止）

```bash
uname -m        # 必须输出 aarch64/arm64（armv7/32 位 ARM 不支持）
docker version  # 确认可用
df -h           # 数据分区剩余空间 ≥ 1.5GB
free -m         # 总内存 ≥ 1GB（低于 512MB 停止）
```

### 2. 部署

```bash
mkdir -p /opt/zcode && cd /opt/zcode
# 下载本仓库的 docker-compose.yml（或直接创建）
cat > docker-compose.yml <<'EOF'
services:
  zcode:
    image: ghcr.io/xixka/zcode-web:latest
    ports:
      - "3030:3030"
    volumes:
      - zcode-data:/data
      - /mnt/usb/project:/workspace   # 改为你的外接盘代码目录
    restart: unless-stopped
volumes:
  zcode-data:
EOF

docker compose up -d
```

### 3. 获取访问令牌并打开

```bash
docker compose logs | grep -o 'http://[^ ]*token=[^ ]*' | head -1
```

浏览器打开输出的 `http://<路由器IP>:3030/?token=...`。

### 4. 登录模型

界面左下角「连接使用」→ 选 **连接 Z.ai** 或 **连接 BigModel**（国内推荐）完成 OAuth，或填 API Key。需订阅 GLM Coding Plan 才有可用额度。

> OAuth 登录后不跳转：检查容器内时间是否正确（NTP），token 校验与时间相关。

## 验收

1. `docker compose ps` 显示运行，无重启循环
2. 日志无 EACCES / Cannot find module 报错
3. 浏览器打开 token URL 能看到 ZCode 工作台界面
4. 新建任务让 Agent「列出当前目录的文件」，收到正常响应
5. `docker compose restart` 后登录态仍在（`/data` 卷持久化生效）

## 硬性要求

- **禁止** `--no-token` 裸奔 —— 该端口等于开放一个可执行命令的 AI Agent
- **禁止**把工作区数据放在路由器 flash 分区，一律用 USB / NAS 分区
- 令牌丢失：`docker compose logs | grep token` 重新获取

## 升级

ZCode 发新版后，手动触发 [Build 工作流](../../actions/workflows/docker.yml)（`Run workflow`）重新构建镜像，然后在路由器上：

```bash
docker compose pull && docker compose up -d
```

数据卷不动，登录态保留。

## 排错

| 现象 | 处理 |
| --- | --- |
| 启动报 lib 丢失 | 镜像基于 `node:24.14.0-slim`（glibc），勿换 alpine |
| 内存不足被 OOM kill | compose 中加 `mem_limit`，关闭路由器不必要的服务 |
| 拉取镜像慢 | 路由器侧可配置镜像加速，或从 Actions Artifact 下载 tar.gz 自行构建 |
