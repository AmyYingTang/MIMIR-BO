# MIMIR Build Orchestrator — Roadmap

> **版本**: v0.2  
> **创建日期**: 2025-02-03  
> **最后更新**: 2025-02-05  
> **当前版本**: BO v1（agent.py v0.6 + localStorage 管理界面）

---

## 版本演进路线

```
v1 (当前)          v2 (进行中)           v3 (愿景)
人工管理状态    →   AI chat 感知上下文  →  多 Agent 协作主导全流程
agent.py CLI        内嵌 Claude chat       自动分解 + 自动执行 + 人类审核
```

---

## v1 — 当前能力

### ✅ 已实现

**RunPrompt Agent (agent.py v0.6):**
- 单/多 prompt 顺序执行（通配符支持）
- 模板变量 `{{variable:default}}` 预收集
- MySQL 连接预测试（Validate Inputs Early 原则）
- 交互模式标记 `<!-- agent:interactive -->`
- Fail-fast：exit code != 0 立即停止
- stream-json 实时输出（工具调用、文本、统计）

**Review Agent (review.sh v0.1):** 🆕
- 独立于写代码的 agent，对照设计文档审查代码
- 5 个检查维度：API 契约、共享数据、前后端字段、状态枚举、测试覆盖
- 输出结构化 review report（PASS/WARN/FAIL + 文件:行号）

**Dashboard:**
- 自动备份功能（localStorage 管理界面）

### 🔴 已知缺陷
- **无法检测"假成功"**：Claude Code exit code = 0 但实际未完成（测试没跑、文件没生成等）
- **无执行日志持久化**：执行记录只在终端，无法回溯
- **无断点续跑**：中断后必须从头或手动指定起点
- **模板变量误匹配**：prompt 内容中的 `{{}}` 占位符被当作用户输入变量（s-1-2 P03 实例）

---

## v1.1 — 近期改进（agent.py v0.7）

> 优先级基于 s-1-2 执行中暴露的实际痛点

| # | 功能 | 优先级 | 说明 |
|---|------|:------:|------|
| 1 | **执行结果智能检测** | 🔴 高 | 每个 prompt 执行完后，自动校验验收标准（检查文件是否存在、测试是否通过等）。即使 exit code = 0，验收不通过也应停止 |
| 2 | **断点续跑 (checkpoint)** | 🔴 高 | 记录已成功执行的 prompt，`--resume` 参数跳过已完成的步骤 |
| 3 | **执行日志** | 🟡 中 | 每次执行输出到 `logs/YYYY-MM-DD-HH-MM-{prompt_name}.log`，便于回溯和诊断 |
| 4 | **Dry-run 模式** | 🟡 中 | `--dry-run` 只扫描变量、检查文件依赖、展示执行计划，不实际执行 |
| 5 | **模板变量作用域** | 🟢 低 | 区分 agent 模板变量（用户输入）和 prompt 内容中的占位符（代码逻辑），避免误匹配 |

---

## v1.2 — 多报告 Triage 流程（待设计）

> 核心目标：报告与修复解耦，人类决定修什么、不修什么

**当前问题：**
review-agent 和 convention-extraction 各自产出报告，但 report → fix prompt 之间缺少人工判断环节。所有 finding 被无差别地转为 fix prompt，实际上部分应 defer 或 wontfix。

**目标流程：**
```
review-report.md ─┐
                  ├→ 人工 triage (fix / defer / wontfix) → fix prompt (仅 fix 项)
extraction.md ────┘                                      → open-issues.md (defer 项)
```

**待设计项：**

| # | 项 | 说明 |
|---|-----|------|
| 1 | Triage 标记格式 | 在 report 中如何标记 fix/defer/wontfix（inline annotation? 独立 triage 文件?） |
| 2 | open-issues.md 结构 | defer 项如何组织（按模块? 按严重度? 按类型?），如何跟踪生命周期 |
| 3 | 多报告汇聚规则 | 多份报告中重复/冲突的 finding 如何合并为一个 fix prompt |
| 4 | 未来报告类型扩展点 | 除 review 和 extraction 外，未来可能有 security-scan、performance-audit 等报告源 |

---

## v2 — 内嵌 AI Chat（BO 管理界面增强）

> 核心目标：执行异常时，人类不需要自己翻 context，AI chat 自动提供诊断

| # | 功能 | 说明 |
|---|------|------|
| 1 | **异常上下文推送** | agent 执行中断时，自动将 context（哪个 prompt、哪一步、错误信息、相关文件）推送到内嵌 chat |
| 2 | **项目全局感知** | chat 能访问项目 JSON 结构之外的上下文——设计文档、已执行的 prompt、执行日志 |
| 3 | **交互式修复建议** | 人类描述问题，AI 基于完整 context 给出修复方案（修改 prompt / 修改代码 / 跳过步骤） |
| 4 | **执行状态可视化** | 管理界面实时展示 prompt 执行进度、成功/失败/跳过状态 |
| 5 | **配置文件支持** | 项目级 `.mimir-bo.yaml` 配置（prompt 目录、项目路径、变量默认值等），减少 CLI 参数 |

---

## v3 — 多 Agent 自动化（愿景）

> 核心目标：人类从"执行者"变为"审核者"

| # | 功能 | 说明 |
|---|------|------|
| 1 | **自动 Task Decompose** | 输入设计文档 → 自动生成 prompt 文件组，人类审核后执行 |
| 2 | **自动修复循环** | 执行失败 → AI 诊断 → 生成修复 patch → 重新执行 → 直到通过或请求人工介入 |
| 3 | **变更影响分析** | 设计文档变更时，自动识别受影响的 prompt 并生成 delta patch（关联 MIMIR-ISSUE-002） |
| 4 | **知识自提取** | 执行过程中识别可复用模式，自动提炼为 MIMIR Skill 候选（Layer 4） |
| 5 | **多 Context 协作** | 产品/方法论/工具三条线各自独立对话+状态，共享项目级知识层。类似人类团队各管一块但有共享文档和站会。解决当前单对话框中频繁切换 context 的认知开销问题。目前无现成方案，记录以待探索 |

---

## 决策记录

| 日期 | 决策 | 原因 |
|------|------|------|
| 2025-02-01 | agent.py 使用 `--dangerously-skip-permissions` | 自动化执行需要，prompt 本身已经过人类审核 |
| 2025-02-01 | stream-json 输出而非纯文本 | 需要结构化解析工具调用和统计信息 |
| 2025-02-03 | 10 个 prompt 分 3 批执行而非一次性 | 当前缺少"假成功"检测，分批+人工验收是临时方案 |
| 2025-02-05 | BO v2 选择"AI chat + 上下文"而非纯规则自动化 | s-2-1 实证：DependencyResolutionGate 拦不住"我以为存在但其实不存在"的认知盲区（如 admin 凭据问题）。规则处理已知模式，chat 兜底未知盲区。这验证了 v2 的 chat 环节设计方向 |
| 2025-02-05 | Review-agent ROI 首个定量数据点 | s-2-1 后跑 review-agent，~$1-2 成本发现 6 个修复点（含 role type 不匹配、过期枚举）。如留到后续模块，修复成本估计翻 3-5x |
| 2025-02-05 | 报告与修复必须解耦，需引入人工 triage 环节 | s-2-1 实践暴露：review report → 直接生成 fix prompt 跳过了人工判断。部分 finding 应 defer 或 wontfix，不应全部修复 |

---

## 文档历史

| 版本 | 日期 | 说明 |
|------|------|------|
| v0.1 | 2025-02-03 | 初始版本，整合已知需求和 s-1-2 执行中发现的痛点 |
| v0.2 | 2025-02-05 | 新增 v1.2 Triage 流程章节；决策记录追加 s-2-1 验证数据（chat 价值验证、review-agent ROI、报告解耦） |
