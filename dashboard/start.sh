#!/bin/bash
# MIMIR-BO Dashboard 启动脚本
# 用法: ./start.sh

set -e
cd "$(dirname "$0")"

# 检查依赖
if [ ! -d "node_modules" ] || [ ! -d "client/node_modules" ]; then
  echo "⚠️  依赖未安装，先运行 ./install.sh"
  exit 1
fi

# 检查端口占用
check_port() {
  local port=$1
  if lsof -i ":$port" -sTCP:LISTEN &>/dev/null; then
    local pid=$(lsof -ti ":$port" -sTCP:LISTEN)
    echo "❌ 端口 $port 已被占用 (PID: $pid)"
    echo "   运行 ./stop.sh 关闭上次的进程，或手动执行: kill $pid"
    exit 1
  fi
}

check_port 3001
check_port 5173

# 确保 Ctrl+C 时杀掉所有子进程
cleanup() {
  echo ""
  echo "🛑 正在关闭..."
  kill 0 2>/dev/null
  wait 2>/dev/null
  echo "✅ 已关闭"
}
trap cleanup EXIT INT TERM

echo ""
echo "🚀 MIMIR-BO Dashboard"
echo "   浏览器访问: http://localhost:5173"
echo "   按 Ctrl+C 停止"
echo ""

npm run dev
