#!/bin/bash
# MIMIR-BO Dashboard 安装脚本
# 用法: ./install.sh

set -e
cd "$(dirname "$0")"

echo "📦 安装 MIMIR-BO Dashboard 依赖..."
echo ""

# 检查 Node.js
if ! command -v node &> /dev/null; then
  echo "❌ 未找到 Node.js，请先安装: https://nodejs.org"
  exit 1
fi

echo "  Node.js $(node -v)"
echo ""

npm install --silent
cd client && npm install --silent && cd ..

echo ""
echo "✅ 安装完成！运行 ./start.sh 启动"
