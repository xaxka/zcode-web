// zcode 3.16.2 Web 模式（zcode --web，standalone-server）两处官方缺陷的构建期补丁。
// 任何一处锚点在上游消失时构建失败，提醒重新适配。
const fs = require("fs");
const F = "/opt/zcode/server/entry-http.js";
let s = fs.readFileSync(F, "utf8");
let changed = 0;

// 补丁一：宿主身份固定为 "local"。
// 官方实现从容器 ID 派生 remote:server:<容器ID>，与 Web UI 的 "local" 寻址不一致，
// 导致 project.host-offline / project.host-immutable / task-group.created-task-unavailable，
// 且容器重建后身份漂移使历史任务/项目全部失联。
const identityRe = /const projectStorageHostId = remoteHostIdFromWorkspaceIdentity\(\s*buildServerRemoteWorkspaceIdentity\(\{ serverId: options2\.sourceServerId, workspacePath: "\/" \}\)\s*\);/;
if (identityRe.test(s)) {
  s = s.replace(identityRe, 'const projectStorageHostId = "local";');
  changed++;
} else if (!s.includes('const projectStorageHostId = "local";')) {
  console.error("identity patch: anchor not found");
  process.exit(1);
}

// 补丁二：补注册桌面版专有的 window-controller 通道。
// Web UI 的任务归档/置顶/重命名/删除/已读走 window-controller.mutateTask，
// 无头服务端没有该通道（Unknown channel），所有任务列表操作静默失败；
// 且客户端启动时订阅 onDynamicControllerFrame 等事件，缺失会导致页面白屏。
const wcAnchor = "  services.exposeOnChannelServer(server, overrides);";
if (s.includes('server.registerChannel("window-controller"')) {
  // 已打过补丁（幂等）
} else if (s.includes(wcAnchor)) {
  const block = [
    "",
    "  try {",
    "    const __wcMutate = async (params) => {",
    "      const taskService = services.get(IZCodeTaskService);",
    "      const a = (params && params.address) || {};",
    "      const i = { taskId: a.taskId, workspacePath: a.workspacePath, ...(a.workspaceIdentity ? { workspaceIdentity: a.workspaceIdentity } : {}) };",
    "      const m = (params && params.mutation) || {};",
    "      switch (m.kind) {",
    '        case "archive": return m.archived ? taskService.archiveTask(i) : taskService.unarchiveTask(i);',
    '        case "delete": await taskService.deleteTask(i); return null;',
    '        case "rename": return taskService.renameTask({ ...i, title: m.title });',
    '        case "pin": return taskService.setTaskPinned({ ...i, pinned: m.pinned });',
    '        case "mark-read": return taskService.setTaskUnread({ ...i, unread: false, ...(typeof m.expectedUnreadAt === "number" ? { expectedUnreadAt: m.expectedUnreadAt } : {}) });',
    '        case "mark-unread": return taskService.setTaskUnread({ ...i, unread: true });',
    '        default: throw new Error("window-controller.mutateTask: unsupported mutation " + m.kind);',
    "      }",
    "    };",
    '    server.registerChannel("window-controller", ProxyChannel.fromService(new Proxy({ mutateTask: __wcMutate }, {',
    "      get(t, prop) {",
    '        if (typeof prop !== "string") return void 0;',
    '        if (prop === "mutateTask") return t.mutateTask;',
    '        if (/^onDynamic[A-Z]/.test(prop)) return () => (listener) => ({ dispose() {} });',
    '        if (/^on[A-Z]/.test(prop)) return (listener) => ({ dispose() {} });',
    "        return async () => {};",
    "      }",
    "    })));",
    '  } catch (e) { console.error("window-controller patch failed:", e && e.message); }',
    ""
  ].join("\n");
  s = s.replace(wcAnchor, wcAnchor + "\n" + block);
  changed++;
} else {
  console.error("window-controller patch: anchor not found");
  process.exit(1);
}

if (changed > 0) fs.writeFileSync(F, s);
console.log("fix-web-server: applied", changed, "patch(es)");
