#!/bin/bash
# MIMIR-BO Dashboard 停止脚本
# 用法: ./stop.sh

killed=0

for port in 3001 5173; do
  pid=$(lsof -ti ":$port" -sTCP:LISTEN 2>/dev/null)
  if [ -n "$pid" ]; then
    kill $pid 2>/dev/null
    echo "✅ 已关闭端口 $port 上的进程 (PID: $pid)"
    killed=1
  fi
done

if [ "$killed" = "0" ]; then
  echo "ℹ️  没有正在运行的进程"
fi
