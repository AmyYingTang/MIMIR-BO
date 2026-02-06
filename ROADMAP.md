# MIMIR Build Orchestrator — Roadmap

> **版本**: v0.3  
> **创建日期**: 2026-02-03  
> **最后更新**: 2026-02-05  
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
| 6 | **Fix prompt 文件定位规范** | 🟡 中 | fix prompt 不得假设文件名/路径，必须先 `grep/find` 定位实际文件再写修改代码。s-2-2 实例：prompt 写 `PermissionManagement.vue`，实际文件是 `PermissionAssignment.vue`，排查时浪费大量时间 |

---

## v1.2 — 多报告 Triage 流程（初步设计，有实例支撑）

> 核心目标：报告与修复解耦，人类决定修什么、不修什么

**当前问题：**
review-agent 和 convention-extraction 各自产出报告，但 report → fix prompt 之间缺少人工判断环节。所有 finding 被无差别地转为 fix prompt，实际上部分应 defer 或 wontfix。

**首个实例：**
`fix-p2-2-frontend-validation.md` 是 Phase 2 review 报告转化为 fix prompt 的实证样例。6 个 finding（F5-F11），按严重度分 MEDIUM/LOW，每个包含：搜索关键词、修改前/后代码、验证清单。这个文档验证了以下 triage 模式可以工作：

```
review report finding → 严重度标签 → fix/defer/wontfix 分流
                                      ↓                 ↓
                               fix prompt           open-issues.md
                          (仅 fix 项，按文件分组)     (defer 项，带原因)
```

**从实例反推的初步设计：**

1. **Finding 标识**：每个 finding 用 `F{序号}` 编号 + 严重度标签（CRITICAL / HIGH / MEDIUM / LOW）
2. **Fix prompt 结构**（已验证可工作）：
   - 概述表格（#、严重度、文件、问题）
   - 每个 fix 项：搜索关键词 → 修改前代码 → 修改后代码 → 注意事项
   - 验证清单
   - 收尾 git commit + rebuild 命令
3. **fix prompt 中必须用 grep/find 先定位实际文件**（见 v1.1 #6），不假设文件名

**目标流程：**
```
review-report.md ─┐
                  ├→ 人工 triage (fix / defer / wontfix) → fix prompt (仅 fix 项)
extraction.md ────┘                                      → open-issues.md (defer 项)
```

**待设计项：**

| # | 项 | 状态 | 说明 |
|---|-----|:----:|------|
| 1 | Triage 标记格式 | ⬜ | 在 report 中如何标记 fix/defer/wontfix（inline annotation? 独立 triage 文件?） |
| 2 | open-issues.md 结构 | ⬜ | defer 项如何组织（按模块? 按严重度? 按类型?），如何跟踪生命周期 |
| 3 | 多报告汇聚规则 | ⬜ | 多份报告中重复/冲突的 finding 如何合并为一个 fix prompt |
| 4 | 未来报告类型扩展点 | ⬜ | 除 review 和 extraction 外，未来可能有 security-scan、performance-audit 等报告源 |
| 5 | fix prompt 生成自动化 | ⬜ | 人工 triage 后，是否可以 AI 辅助生成 fix prompt（以 fix-p2-2 为模板） |

---

## v1.3 — Decompose 跨模块依赖控制（待设计）

> 核心目标：decompose 发现跨模块依赖时，必须显式决策而非静默吞并

**触发事件：**
s-2-2（权限分配）的 decompose 把 s-2-3（用户审核）的工作吞并了——技术上合理（审核是权限的前置），但造成两个问题：
1. s-2-3 没有被标记为"已吸收"，plan 与实际执行脱节
2. 吞并了但没做完（权限校验集成和前端权限页缺失），形成"半吞并"状态

**设计约束：**

decompose 阶段发现跨模块依赖时，必须走以下流程：

```
发现依赖 → 显式选择处理策略 → 反馈用户确认 → 更新 plan
```

| 策略 | 适用场景 | plan 更新动作 |
|------|----------|---------------|
| **声明依赖** | 被依赖模块复杂度高，不宜合并 | 当前模块 prompt 中注明"假设 X 模块已完成"，保持两模块独立 |
| **合并模块** | 被依赖模块简单，合并后 prompt 总量可控 | 被吸收模块标记为"已合并至 s-X-Y"，从待执行列表中移除 |
| **最小桩接口** | 需要依赖但不想完整实现 | 创建桩/mock，被依赖模块保持独立 |

**质量门禁：**
- 无论选择哪种策略，人类必须确认
- 合并后的模块必须在验收清单中覆盖被吸收模块的全部验收点
- plan 变更必须有 diff 记录（变更了什么、为什么）

**待设计项：**

| # | 项 | 说明 |
|---|-----|------|
| 1 | plan diff 格式 | plan 更新时的变更记录格式（纯文本 diff? 表格? changelog?） |
| 2 | 与 runprompt-agent 的集成 | agent 执行前是否校验 plan 一致性（prompt 存在性 vs plan 条目） |
| 3 | v3 自动化路径 | 未来 auto-decompose 时，这个流程如何变为规则而非人工判断 |

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
| 1 | **自动 Task Decompose** | 输入设计文档 → 自动生成 prompt 文件组，人类审核后执行。**前置约束**：必须满足 v1.3 跨模块依赖控制规则（显式声明依赖/合并，不得静默吞并） |
| 2 | **自动修复循环** | 执行失败 → AI 诊断 → 生成修复 patch → 重新执行 → 直到通过或请求人工介入 |
| 3 | **变更影响分析** | 设计文档变更时，自动识别受影响的 prompt 并生成 delta patch（关联 MIMIR-ISSUE-002） |
| 4 | **知识自提取** | 执行过程中识别可复用模式，自动提炼为 MIMIR Skill 候选（Layer 4） |
| 5 | **多 Context 协作** | 产品/方法论/工具三条线各自独立对话+状态，共享项目级知识层。类似人类团队各管一块但有共享文档和站会。解决当前单对话框中频繁切换 context 的认知开销问题。目前无现成方案，记录以待探索 |

---

## 决策记录

| 日期 | 决策 | 原因 |
|------|------|------|
| 2026-02-01 | agent.py 使用 `--dangerously-skip-permissions` | 自动化执行需要，prompt 本身已经过人类审核 |
| 2026-02-01 | stream-json 输出而非纯文本 | 需要结构化解析工具调用和统计信息 |
| 2026-02-03 | 10 个 prompt 分 3 批执行而非一次性 | 当前缺少"假成功"检测，分批+人工验收是临时方案 |
| 2026-02-05 | BO v2 选择"AI chat + 上下文"而非纯规则自动化 | s-2-1 实证：DependencyResolutionGate 拦不住"我以为存在但其实不存在"的认知盲区（如 admin 凭据问题）。规则处理已知模式，chat 兜底未知盲区。这验证了 v2 的 chat 环节设计方向 |
| 2026-02-05 | Review-agent ROI 首个定量数据点 | s-2-1 后跑 review-agent，~$1-2 成本发现 6 个修复点（含 role type 不匹配、过期枚举）。如留到后续模块，修复成本估计翻 3-5x |
| 2026-02-05 | 报告与修复必须解耦，需引入人工 triage 环节 | s-2-1 实践暴露：review report → 直接生成 fix prompt 跳过了人工判断。部分 finding 应 defer 或 wontfix，不应全部修复 |
| 2026-02-05 | Decompose 跨模块依赖必须显式决策 | s-2-2 decompose 静默吞并 s-2-3 导致：plan 与执行脱节 + 半吞并（吞了但没做完）。无论"声明依赖"还是"合并模块"，都必须反馈用户确认并更新 plan |
| 2026-02-05 | fix-p2-2 验证了 review→triage→fix prompt 模式 | 6 个 finding（F5-F11）按严重度标签 + 搜索关键词 + 修改前后代码 + 验证清单的结构可以工作。这是 v1.2 Triage 流程的首个实证样例 |
| 2026-02-05 | fix prompt 必须 grep/find 先定位文件 | s-2-2 fix prompt 假设文件名 `PermissionManagement.vue`，实际是 `PermissionAssignment.vue`。agent 不会质疑 prompt 给的文件名，直接创建新文件或报错。fix-s-2-2-permission-integration.md 已实践"先 grep 确认再写代码"模式 |

---

## 文档历史

| 版本 | 日期 | 说明 |
|------|------|------|
| v0.1 | 2026-02-03 | 初始版本，整合已知需求和 s-1-2 执行中发现的痛点 |
| v0.2 | 2026-02-05 | 新增 v1.2 Triage 流程章节；决策记录追加 s-2-1 验证数据（chat 价值验证、review-agent ROI、报告解耦） |
| v0.3 | 2026-02-05 | s-2-2/s-2-3 经验更新：v1.2 Triage 充实实例数据（fix-p2-2）；新增 v1.3 Decompose 跨模块依赖控制；v1.1 新增 fix prompt 文件定位规范；决策记录 +3 条 |
