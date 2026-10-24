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
COPY docker-entrypoint.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-entrypoint.sh

# ---- Web 模式宿主身份补丁（3.16.2）----
# zcode --web（standalone-server）把项目宿主 ID 从容器 ID 派生（remote:server:<容器ID>），
# 与 Web UI 的 "local" 寻址不一致：创建项目报 project.host-offline / host-immutable，
# 新建任务报 task-group.created-task-unavailable；且每次容器重建身份都会变，
# 历史任务/项目全部失联。固定为 "local" 一次解决三类问题。
# 上游若修改此处代码，本步骤构建失败以提醒重新适配。
RUN node -e 'const fs=require("fs");const F="/opt/zcode/server/entry-http.js";let s=fs.readFileSync(F,"utf8");const re=/const projectStorageHostId = remoteHostIdFromWorkspaceIdentity\(\s*buildServerRemoteWorkspaceIdentity\(\{ serverId: options2\.sourceServerId, workspacePath: "\/" \}\)\s*\);/;if(!re.test(s)){console.error("host identity patch site not found - upstream changed");process.exit(1)}fs.writeFileSync(F,s.replace(re,"const projectStorageHostId = \"local\";"))'

ENV ZCODE_DATA_BASE_DIR=/data
# 登录态/凭据写入 $ZCODE_DATA_BASE_DIR/.zcode；setting.json 走 homedir()，
# 设 HOME=/data 使所有运行时数据（含 UI 设置）都落在 /data 卷。
ENV HOME=/data

EXPOSE 3030

# 入口脚本：首次启动生成 telemetry deviceMid（官方 bug #681 的 workaround），再拉起服务
ENTRYPOINT ["docker-entrypoint.sh"]

# 不传 --no-token：host 为 0.0.0.0 时运行时自动生成访问令牌并打印到日志；
# 设 ZCODE_WEB_TOKEN 环境变量可固定令牌（重启不变，URL 稳定）
CMD ["sh", "-c", "exec node /opt/zcode/bin/zcode.mjs --web --host 0.0.0.0 --port 3030 --workspace /workspace --no-open $(if [ -n \"$ZCODE_WEB_TOKEN\" ]; then printf -- '--token %s' \"$ZCODE_WEB_TOKEN\"; fi)"]
