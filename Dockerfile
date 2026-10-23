# ZCode Web 工作台（官方 CLI 发行包运行时，无 Electron / GUI 依赖）
# 构建上下文中必须存在 zcode-<version>.tar.gz（由 GitHub Actions 从官方源码构建产出）
ARG NODE_IMAGE=node:24.14.0-slim

# ---- 解包与剪裁层 ----
# 多阶段构建：tar.gz 与剪裁残片只存在于本层，最终镜像不含 81MB 压缩包
FROM ${NODE_IMAGE} AS unpack
COPY zcode-*.tar.gz /tmp/
# tar.gz 顶层目录为 zcode/，入口是 bin/zcode.mjs
RUN mkdir -p /opt/zcode \
    && tar -xzf /tmp/zcode-*.tar.gz -C /opt/zcode --strip-components=1 \
    # 剪裁（本地实测 400MB → 304MB，服务/Agent 运行时验证通过）：
    && find /opt/zcode -name '*.map' -delete \
    # sourcemap 仅浏览器 devtools 使用，92.5MB
    && rm -rf /opt/zcode/node_modules/node-pty/prebuilds/darwin-arm64 \
              /opt/zcode/node_modules/node-pty/prebuilds/darwin-x64 \
              /opt/zcode/node_modules/node-pty/third_party/conpty \
              /opt/zcode/node_modules/node-pty/deps/winpty
    # conpty/winpty 仅 Windows 运行时使用，darwin prebuilds 仅 macOS 使用

# ---- 运行层 ----
FROM ${NODE_IMAGE}
RUN mkdir -p /data /workspace
COPY --from=unpack /opt/zcode /opt/zcode

ENV ZCODE_DATA_BASE_DIR=/data
# 登录态/凭据写入 $ZCODE_DATA_BASE_DIR/.zcode；setting.json 走 homedir()，
# 设 HOME=/data 使所有运行时数据（含 UI 设置）都落在 /data 卷。
ENV HOME=/data

EXPOSE 3030

# 不传 --no-token：host 为 0.0.0.0 时运行时自动生成访问令牌并打印到日志
CMD ["node", "/opt/zcode/bin/zcode.mjs", "--web", \
     "--host", "0.0.0.0", "--port", "3030", \
     "--workspace", "/workspace", "--no-open"]
