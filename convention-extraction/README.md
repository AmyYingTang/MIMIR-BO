# Convention Extraction — 跨模块约定提取

模块完成后、下一个模块 prompt 生成前，从已有代码中提取隐式约定为结构化快照。

**核心洞察：设计文档定义契约（做什么），代码建立约定（怎么做）。契约有显式文档，约定没有——直到现在。**

## 为什么需要它

| 问题 | 根因 | Convention Extraction 如何解决 |
|------|------|-------------------------------|
| 模块2的命名风格与模块1不一致 | 不同 prompt 各自做决策，无全局参照 | 从模块1代码提取约定，嵌入模块2的 prompt |
| 错误处理方式前后模块不统一 | 设计文档不规定实现细节 | 提取已建立的模式作为后续约束 |
| 前端组件结构在不同模块间各异 | 架构层面一致但实现层面发散 | 快照记录实际的组织方式 |
| Review agent 反复报同类问题 | 问题在生成时就存在，review 只是事后发现 | 在 prompt 生成前就注入一致性约束 |

## 快速开始

```bash
# 模块1完成后，提取初始快照
cd ~/voice-platform
~/mimir-bo/convention-extraction/extract.sh auth

# 模块2完成后，更新快照（自动检测已有版本并递增）
~/mimir-bo/convention-extraction/extract.sh training

# 指定输出路径和项目名
./extract.sh auth ~/voice-platform ~/voice-platform/docs/project-conventions.md "Voice Platform"
```

## 提取维度

| # | 维度 | 提取什么 |
|---|------|----------|
| 1 | 结构约定 | 后端分层、前端组织、共享类型位置、测试文件结构 |
| 2 | 命名约定 | Router 函数名、Store 命名、Task 命名、路由路径模式 |
| 3 | 模式约定 | 错误处理、认证注入、分页、API 客户端、表单验证 |
| 4 | 共享接口约定 | 日期格式、ID 格式、响应结构、状态枚举 |
| 5 | 基础设施约定 | Docker 命名、环境变量、端口、迁移、日志 |

## 输出

生成 `project-conventions.md` 到指定路径（默认 `docs/`），包含：

- 5 个维度的结构化约定（YAML 格式）
- 不一致标记（如果发现同一代码库内有冲突模式）
- 暂定标记（仅在一处出现的模式）
- 变更日志（跟踪每个模块的增量更新）

体积目标：200 行以内。

## 在工作流中的位置

```
模块N完成 → review-agent 检查 → 人工验收
                                      ↓
                          ★ convention extraction ★  ← 你在这里
                                      ↓
                          快照嵌入模块N+1的 prompt → 下一个模块开发
```

## 如何嵌入 Prompt

在为下一个模块生成 prompt 时，添加：

```markdown
## 项目约定

本项目在之前的模块中已建立以下约定。
你必须遵循这些约定以保持跨模块一致性。

[粘贴 project-conventions.md 内容]
```

## 前置依赖

- Claude Code CLI (`npm install -g @anthropic-ai/claude-code`)
- Python 3（用于解析 stream-json 输出）
- 至少已有一个已完成的模块（模块1没有约定问题）

## 版本

当前：v0.1

## MIMIR Skill 对应

本 agent 的设计知识和提取维度定义在 MIMIR 的 `skills/convention-extraction/SKILL.md` 中。
BO 中的实现（本目录）是 MIMIR skill 的运行时版本。
两者应保持一致。
