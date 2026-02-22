# MIMIR-BO Dashboard

> MIMIR 方法论驱动的软件开发结构化工作台

## 快速开始

```bash
# 1. 安装依赖
npm install
cd client && npm install && cd ..

# 2. 启动开发服务器（同时启动 backend + frontend）
npm run dev

# 3. 浏览器访问
open http://localhost:5173
```

首次启动会显示初始化向导，引导你配置：
- Instance 名称
- 工具目录（MIMIR-BO 所在目录）
- 工作目录（prompts/reports 存放位置）
- 项目目录（代码目录）
- MIMIR Skill 绑定

## 项目结构

```
mimir-bo-dashboard/
├── server/
│   └── index.js          # Express 后端（API + WebSocket）
├── client/
│   ├── src/
│   │   ├── views/        # 页面（SetupWizard, Dashboard）
│   │   ├── components/   # 组件（Sidebar, TreeNav, ModulePanel...）
│   │   ├── composables/  # 组合函数（useApi, useWebSocket）
│   │   └── assets/       # 全局样式
│   └── vite.config.js    # Vite 配置（含 API 代理）
├── sample-workspace/     # 开发用示例工作目录
└── package.json          # 根 package.json（含并发启动脚本）
```

## 架构

```
浏览器 (Vue 3 + Vite)
    ↕ HTTP REST API + WebSocket
Node.js 后端 (Express)
    ↕ 文件系统
bo-config.yml + project-state.json + skill-manifest.md
```

## 配置文件

- `bo-config.yml` — 项目配置（路径、Skill 绑定、语言）
- `project-state.json` — 项目状态（阶段进度、模块状态）
- `skill-manifest.md` — Skill 清单（自动生成）

以上文件都存放在工作目录下。

## 环境变量

| 变量 | 说明 | 默认值 |
|------|------|--------|
| `BO_WORKSPACE` | 工作目录路径 | `./sample-workspace` |

## 实现阶段

- **Phase 1 (当前)**: 骨架 — 初始化向导、树导航、文件树、状态持久化
- Phase 2: BUILD 工作流 — 终端集成、模块执行
- Phase 3: Agent 集成 — Prompt→执行→Review 自动流转
- Phase 4: VERIFY/SHIP — 测试、文档、部署

## 技术栈

| 层 | 技术 |
|----|------|
| 前端 | Vue 3 + Vite + Vue Router |
| 后端 | Node.js + Express |
| 通信 | WebSocket (ws) |
| 持久化 | YAML + JSON 文件 |
