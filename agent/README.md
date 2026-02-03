# Agent — Prompt 执行器

自动化调用 Claude Code CLI 顺序执行 Prompt 文件。

## 快速开始

```bash
# 前置条件
npm install -g @anthropic-ai/claude-code

# 单个文件
python agent.py run ./prompt.md --project ~/my-project

# 多个文件（通配符，按文件名排序执行）
python agent.py run ./prompts/*.md --project ~/my-project
```

## 特性

| 特性 | 说明 |
|------|------|
| 模板变量 | `{{variable:default}}` 格式，执行前一次性收集 |
| 连接测试 | 检测到 MySQL 变量时自动测试连接 |
| 交互模式 | `<!-- agent:interactive -->` 标记的 Prompt 允许用户在执行中交互 |
| Fail-fast | 任何步骤 exit code != 0 立即停止，报告进度 |
| 实时输出 | stream-json 格式，显示工具调用、文本、费用统计 |

## 批量执行建议

对于大量 Prompt（如 10 个），建议按依赖链分批执行，每批之间人工验收：

```bash
# 第 1 批：基础设施
python agent.py run ./s-1-2-p0[1-3]*.md --project ~/my-project

# 验收后 → 第 2 批：业务逻辑
python agent.py run ./s-1-2-p0[4-7]*.md --project ~/my-project

# 验收后 → 第 3 批：前端 + 测试
python agent.py run ./s-1-2-p0[8-9]*.md ./s-1-2-p10*.md --project ~/my-project
```

## 已知限制

- 无法检测"假成功"（Claude Code exit code = 0 但实际未完成）
- 无断点续跑（中断后需手动指定起点）
- 模板变量 `{{}}` 可能误匹配 Prompt 内容中的占位符

详见 [ROADMAP.md](../ROADMAP.md) v1.1 改进计划。

## 版本

当前：v0.6
