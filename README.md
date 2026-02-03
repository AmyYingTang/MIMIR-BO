# MIMIR-BO (Build Orchestrator)

> 人类与 AI 协作开发的催化剂  
> A catalyst for human-AI collaborative development

⚠️ **实验阶段** — 这是一个正在演进中的工具，当前处于 v1 阶段。

---

## 它是什么

MIMIR-BO 是 [MIMIR](https://github.com/your-username/MIMIR) 方法论的运行时平台。

MIMIR 定义了人类与 AI 协作的方法论（菜谱），BO 是让这套方法论能被执行的环境（厨房）。

**BO 读取 MIMIR 的 Skill 来执行，但 BO 不是 MIMIR 的一部分。**

---

## 当前能力 (v1)

### Agent — 自动化 Prompt 执行器

`agent/agent.py` — 调用 Claude Code CLI 顺序执行 Prompt 文件。

```bash
# 单个文件
python agent/agent.py run ./01-init.md --project ~/my-project

# 多个文件（按文件名排序执行）
python agent/agent.py run ./prompts/*.md --project ~/my-project
```

核心特性：
- 模板变量 `{{variable:default}}` 预收集
- MySQL 连接预测试（Validate Inputs Early）
- 交互模式标记 `<!-- agent:interactive -->`
- Fail-fast：任何步骤失败立即停止
- stream-json 实时输出

### Dashboard — 项目状态管理界面

`dashboard/mimir-bo.html` — 单文件 HTML，浏览器打开即用。

核心特性：
- Phase / Step 状态追踪
- Pipeline 进度可视化
- 内嵌 AI Chat（项目上下文自动注入）
- localStorage 持久化 + 自动备份 JSON
- 导入/导出项目数据

---

## 项目结构

```
mimir-bo/
├── README.md                 # 本文件
├── ROADMAP.md                # 演进路线图
├── agent/
│   ├── agent.py              # Prompt 执行器 (v0.6)
│   └── README.md             # Agent 使用说明
├── dashboard/
│   ├── mimir-bo.html         # 管理界面（单文件）
│   └── README.md             # Dashboard 使用说明
└── docs/
    └── architecture.md       # 架构说明与设计决策
```

---

## 演进路线

```
v1 (当前)          v2 (进行中)           v3 (愿景)
人工管理状态    →   AI chat 感知上下文  →  多 Agent 协作
agent.py CLI        内嵌 Claude chat       自动分解 + 执行 + 审核
```

详见 [ROADMAP.md](./ROADMAP.md)

---

## 前置依赖

- **Python 3.10+**
- **Claude Code CLI** — `npm install -g @anthropic-ai/claude-code`
- **现代浏览器**（Dashboard 用）

---

## 与 MIMIR 的关系

| MIMIR | MIMIR-BO |
|-------|----------|
| 方法论知识库 | 运行时执行平台 |
| 定义"怎么做" | 实现"做起来" |
| Layer 2 方法论 → | BO 主循环的驱动逻辑 |
| Layer 3 Skills → | Agent 执行 Prompt 时的指导 |
| Layer 4 自提取 ← | BO 执行过程中产生的经验回流 |

---

## 备注

这个工具（包括它的名字）仍在演进中。当前叫 "Build Orchestrator"，但随着它的角色从"编排器"演变为"人机协作催化剂"，未来可能会改名。详见 ROADMAP.md 中的相关讨论。

---

## License

MIT
