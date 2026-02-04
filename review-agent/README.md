# Review Agent — 独立代码审查

在模块开发完成后、人工验收前，独立对照设计文档检查代码实现的一致性。

**核心原则：它不看 prompt，只看设计文档和代码——视角与写代码的 agent 完全独立。**

## 为什么需要它

| 问题 | 根因 | Review Agent 如何解决 |
|------|------|----------------------|
| 26/26 测试全绿但前端不能用 | 写代码和写测试的是同一个 Agent，互相对齐但不与设计文档对齐 | 独立 Agent 以设计文档为唯一真相来源 |
| 后端字段名和前端不一致 | 单模块 prompt 无全局视角 | 跨前后端逐字段比对 |
| 测试凭据和 seed 数据不一致 | 不同 prompt 各自硬编码 | 扫描所有引用点，检查一致性 |
| 状态枚举 DDL 和代码不一致 | 文档更新后代码未同步 | 对比 DDL、状态机文档、代码常量 |

## 快速开始

```bash
# 最简用法（在项目根目录执行）
cd ~/voice-platform
~/mimir-bo/review-agent/review.sh auth

# 指定项目目录和文档目录
./review.sh training ~/voice-platform ~/voice-platform/docs

# 带 scope hint（告诉 reviewer 重点关注哪些文件）
./review.sh training ~/voice-platform ~/voice-platform/docs \
  "backend/app/api/v1/tasks.py frontend/src/views/training/"
```

## 检查维度

| # | 检查项 | 说明 |
|---|--------|------|
| 1 | API 契约对齐 | 设计文档 vs 后端路由 vs 前端调用，逐字段比对 |
| 2 | 共享数据一致性 | 端口、凭据、数据库名等在所有引用点的一致性 |
| 3 | 前后端字段对齐 | URL、请求体、响应体的字段名和嵌套结构 |
| 4 | 状态枚举一致性 | DDL ENUM vs 状态机文档 vs 后端常量 vs 前端显示 |
| 5 | 测试覆盖合理性 | 测试是否存在、fixture 是否与 seed 数据一致 |

## 输出

生成 `review-report-<module>.md` 到项目根目录，包含：

- 总览（PASS / WARN / FAIL 计数）
- 逐项发现（含文件路径、行号、期望值 vs 实际值）
- 优先级排序的修复建议

## 在工作流中的位置

```
设计文档 → task decompose → prompt 文件 → runprompt-agent 执行
                                                    ↓
                                        review-agent 检查  ← 你在这里
                                                    ↓
                                              人工验收
```

## 前置依赖

- Claude Code CLI (`npm install -g @anthropic-ai/claude-code`)
- Python 3 (用于解析 stream-json 输出)
- 项目中存在设计文档 (api-design.md, database-design.md 等)

## 版本

当前：v0.1

## MIMIR Skill 对应

本 agent 的设计知识和检查维度定义在 MIMIR 的 `skills/review-agent/SKILL.md` 中。
BO 中的实现（本目录）是 MIMIR skill 的运行时版本。
两者应保持一致——是的，这正是 review agent 自己应该检查的事情。
