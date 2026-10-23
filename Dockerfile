# ZCode Web 工作台（官方 CLI 发行包运行时，无 Electron / GUI 依赖）
# 构建上下文中必须存在 zcode-<version>.tar.gz（由 GitHub Actions 从官方源码构建产出）
ARG NODE_IMAGE=node:24.14.0-slim
FROM ${NODE_IMAGE}

COPY zcode-*.tar.gz /tmp/

# tar.gz 顶层目录为 zcode/，入口是 bin/zcode.mjs
RUN mkdir -p /opt/zcode /data /workspace \
    && tar -xzf /tmp/zcode-*.tar.gz -C /opt/zcode --strip-components=1 \
    && rm /tmp/zcode-*.tar.gz

ENV ZCODE_DATA_BASE_DIR=/data
# 登录态/凭据写入 $ZCODE_DATA_BASE_DIR/.zcode；setting.json 走 homedir()，
# 设 HOME=/data 使所有运行时数据（含 UI 设置）都落在 /data 卷。
ENV HOME=/data

EXPOSE 3030

# 不传 --no-token：host 为 0.0.0.0 时运行时自动生成访问令牌并打印到日志
CMD ["node", "/opt/zcode/bin/zcode.mjs", "--web", \
     "--host", "0.0.0.0", "--port", "3030", \
     "--workspace", "/workspace", "--no-open"]
