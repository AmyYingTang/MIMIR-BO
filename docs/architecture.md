# MIMIR-BO 架构说明

> 版本: v0.1  
> 最后更新: 2025-02-03

---

## 核心定位

MIMIR-BO 是 MIMIR 方法论的**运行时平台**，不是 MIMIR 的子模块。

两者的关系：MIMIR 是知识库（菜谱），BO 是执行环境（厨房）。BO 读取 MIMIR 的 Skill 来执行，MIMIR 从 BO 的执行经验中提炼新知识。

```
MIMIR (知识)                    MIMIR-BO (执行)
┌──────────────────┐           ┌──────────────────┐
│ Layer 2: 方法论   │ ────→    │ 主循环驱动逻辑     │
│ Layer 3: Skills  │ ────→    │ Agent 执行指导     │
│ Layer 4: 自提取   │ ←────    │ 执行经验回流       │
└──────────────────┘           └──────────────────┘
```

---

## 当前架构 (v1)

```
┌──────────────────────────────────────────────────────────┐
│                     用户 (人类)                            │
│                                                          │
│   ┌─── CLI ──────────────┐    ┌─── 浏览器 ───┐           │
│   │                      │    │              │           │
│   ▼                      │    ▼              │           │
│ runprompt-agent          │  dashboard.html   │           │
│ (Prompt 执行)             │  (状态管理+Chat)  │           │
│   │                      │    │              │           │
│   ▼                      │    ▼              │           │
│ Claude Code CLI          │  Claude API      │           │
│   │                      │  (内嵌 chat)     │           │
│   ▼                      │                  │           │
│ review-agent    ◄────────┘                  │           │
│ (独立代码审查)                                │           │
│   │                                         │           │
│   ▼                                         │           │
│ Claude Code CLI                             │           │
│ (只读: 生成 review report)                   │           │
└──────────────────────────────────────────────────────────┘
```

v1 的三个组件目前是**独立运行**的：
- runprompt-agent 通过 CLI 执行 Prompt，生成代码
- review-agent 通过 CLI 对照设计文档审查代码，生成 review report
- dashboard 通过浏览器管理状态和 chat
- 三者之间没有自动化的数据流，靠人工协调

工作流位置：
```
runprompt-agent 执行 → review-agent 检查 → 人工验收
```

---

## 设计决策记录

| 决策 | 原因 |
|------|------|
| 独立 repo（不放在 MIMIR 内部） | BO 是运行时平台，MIMIR 是知识库，职责不同 |
| 单文件 HTML dashboard | 零依赖，双击即用，降低使用门槛 |
| agent.py 纯 Python 无第三方依赖 | 只需 Python + Claude Code CLI |
| localStorage 持久化 | 最简方案，配合自动备份 JSON 降低数据丢失风险 |
| stream-json 输出 | 需要结构化解析工具调用和统计信息 |
| `--dangerously-skip-permissions` | 自动化执行需要，Prompt 已经过人类审核 |

---

## 未来演进方向

详见 [ROADMAP.md](../ROADMAP.md)。

关键架构演进：
- **v2**：agent 与 dashboard 之间建立数据流（执行状态自动同步到 dashboard）
- **v3**：多 Agent 架构——主线程协调多个专职 Agent（Chat、Doc Generator、Prompt Executor、Knowledge Extractor）
