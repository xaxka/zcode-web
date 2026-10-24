#!/bin/sh
# 官方 bug（zai-org/feedback #681 / #1181）：全新安装的远程主机上 ZCode 不会自行创建
# telemetry-state.json（deviceMid），套餐校验请求（zcode.z.ai /billing/balance）缺少
# X-Device-Mid 头，被服务端拒为 400 parameter error，Start Plan/编程套餐显示「未就绪」。
# 首次启动生成稳定的 deviceMid 并落盘 /data 卷，之后重启沿用同一 ID。
set -e

DATA_DIR="${ZCODE_DATA_BASE_DIR:-/data}"
mkdir -p "$DATA_DIR/.zcode/v2"

if [ ! -s "$DATA_DIR/.zcode/v2/telemetry-state.json" ]; then
    MID=$(cat /proc/sys/kernel/random/uuid 2>/dev/null || node -e "console.log(crypto.randomUUID())")
    printf '{"deviceMid":"%s"}' "$MID" > "$DATA_DIR/.zcode/v2/telemetry-state.json"
    echo "[entrypoint] generated deviceMid: $MID"
fi

exec "$@"
