# MIMIR-BO Dashboard 设计文档

> 版本: v0.5 | 2026-02-22

---

## 变更记录

| 版本 | 日期 | 变更内容 |
|------|------|---------|
| v0.5 | 2026-02-22 | 终端集成确定为方案 B（混合模式）；新增 CLAUDE.md 自动注入机制（§4.4）；工作目录从 BO 下迁移到项目目录下的 `.mimir/`；初始化向导 Step 2 简化为三个目录；新增与 Claude Desktop App 关系说明（§1）；实现阶段重新划分（§9） |
| v0.4 | 2026-02-22 | 初始版本 |

---

## 1. 定位

MIMIR-BO Dashboard 是一个本地 Web 应用（localhost），作为 MIMIR 方法论驱动的软件开发项目的**结构化工作台**。

### 核心职责

Dashboard 是**编排层（Orchestration）**，Claude Code 是**执行层（Execution）**，文件系统是两者之间的**桥梁**。

```
┌─────────────────────────────────────────────────────────┐
│  DESIGN 阶段：Claude Desktop Chat 或 Claude.ai          │
│  - 需求讨论、技术选型、系统设计                            │
│  - 产出：设计文档 → 落盘到项目目录                         │
└──────────────────────┬──────────────────────────────────┘
                       │ 文件系统桥接
┌──────────────────────▼──────────────────────────────────┐
│  MIMIR-BO Dashboard（localhost）                         │
│                                                          │
│  ┌─ 导入检查 ──── DESIGN → BUILD 衔接点                 │
│  ┌─ BUILD ──── Task Decompose → Prompt → 执行 → Review  │
│  │             [内嵌终端: Claude Code CLI 桥接]            │
│  ┌─ VERIFY ── 测试 / 安全审计 / UAT                      │
│  ┌─ SHIP ──── 部署 / 文档同步 / 运维                     │
│                                                          │
│  核心机制:                                                │
│  - CLAUDE.md 自动注入（每个子步骤切换时更新）               │
│  - 内嵌终端（交互式 + headless 混合模式）                  │
│  - 状态持久化（project-state.json）                       │
└─────────────────────────────────────────────────────────┘
```

### 与 Claude Desktop App 的关系

Claude Desktop App 现在提供三个 tab：Chat、Code、Cowork。Dashboard **不替代**这些原生工具，而是在它们之上提供 MIMIR 方法论专用的结构化工作流。

| 维度 | Claude Desktop App | Dashboard |
|------|-------------------|-----------|
| 定位 | 通用 AI 工具 | MIMIR 方法论专用工作台 |
| 状态管理 | 无跨 session 状态 | 精确追踪 phase / module / sub_step |
| 工作流 | 自由对话 | 结构化步骤驱动 |
| Agent 编排 | 单次 session | 多 Agent 串联（runprompt → review → fix） |
| Context 传递 | tab 之间不共享 | 通过 CLAUDE.md 自动注入 |

**关键设计决策**：Chat ↔ Code ↔ Cowork 三个 tab 之间的 context 不共享。Dashboard 通过在每个执行节点自动更新项目根目录的 `CLAUDE.md` 来解决 context 传递问题——无论 Claude Code 从哪个 surface 启动（CLI、Desktop Code tab、Web），都能读到正确的上下文。

### DESIGN 阶段的工具选择

用户可以在以下任一环境完成 DESIGN 阶段的工作，Dashboard 不强制指定：

- **Claude Desktop Chat**（推荐）：结合 Cowork 可直接将设计文档落盘到项目目录
- **Claude.ai Web**：通过 Project 功能组织设计讨论，手动将文档保存到项目目录
- **Claude Desktop + Cowork**：适合需要操作本地文件的设计工作

Dashboard 在 DESIGN 阶段仅提供引导和文档到位检测（Checklist），不参与对话过程。

---

## 2. 多项目管理

### 核心概念

Dashboard 支持管理多个项目，每个项目在其项目目录下有独立的 `.mimir/` 工作目录。Dashboard 启动后首先进入**项目选择页**，而非直接进入某个项目。

```
Dashboard 启动
  ↓
项目选择页
  ├── 🆕 新建项目 → 初始化向导 → 在项目目录下创建 .mimir/
  ├── 📂 打开已有项目 → 选择含 .mimir/ 的项目目录 → 恢复状态
  └── 最近项目列表（自动记录，可固定/移除）
      ├── 🟢 voice-platform (BUILD) — 上次: 2026-02-22
      ├── 🟡 admin-portal (DESIGN) — 上次: 2026-02-15
      ├── ⬜ data-pipeline (暂停) — 上次: 2026-02-01
      └── ...
```

### 项目注册表（projects.yml）

存储位置：默认 `{BO工具目录}/projects.yml`，用户可在 Dashboard 全局设置中修改。

```yaml
# projects.yml — 项目注册表
# 存储路径可配置，默认: {BO工具目录}/projects.yml

projects:
  - name: "Voice Platform 语音平台"
    project_dir: /Users/amy/dev/voice-platform         # 项目目录（.mimir/ 在其下）
    phase: BUILD
    updated_at: "2026-02-22T10:30:00Z"
    pinned: true

  - name: "Admin Portal 管理后台"
    project_dir: /Users/amy/dev/admin-portal
    phase: DESIGN
    updated_at: "2026-02-15T14:00:00Z"
    pinned: false
```

每个项目的 `.mimir/` 内部结构：
```
{项目目录}/.mimir/
├── config.yml             # 项目配置
├── state.json             # 项目状态
├── skill-manifest.md      # MIMIR 内容清单（自动生成）
├── conventions/
│   └── latest.md          # Convention Snapshot
├── prompts/
│   ├── s-1-1/
│   ├── s-2-2/
│   └── ...
└── reports/
    ├── s-2-2/
    │   ├── review-report.md
    │   └── fix-prompt.md
    └── ...
```

### 项目选择页 UI

```
┌──────────────────────────────────────────────────────┐
│                                                      │
│  MIMIR-BO Dashboard                          ⚙️     │
│                                                      │
│  ┌──────────────────┐  ┌──────────────────────────┐ │
│  │  🆕 新建项目      │  │  📂 打开已有项目          │ │
│  │  开始初始化向导    │  │  选择含 .mimir/ 的目录    │ │
│  └──────────────────┘  └──────────────────────────┘ │
│                                                      │
│  最近项目                                            │
│  ┌──────────────────────────────────────────────────┐│
│  │ 📌 🟢 Voice Platform 语音平台                     ││
│  │    BUILD 阶段 · s-2-3 进行中 · 2 小时前           ││
│  ├──────────────────────────────────────────────────┤│
│  │    🟡 Admin Portal 管理后台                       ││
│  │    DESIGN 阶段 · 1 周前                           ││
│  ├──────────────────────────────────────────────────┤│
│  │    ⬜ Data Pipeline                               ││
│  │    VERIFY 阶段 · 3 周前                           ││
│  └──────────────────────────────────────────────────┘│
│                                                      │
└──────────────────────────────────────────────────────┘
```

操作：
- **点击项目卡片**：打开该项目，进入 Dashboard 主界面
- **🆕 新建项目**：进入初始化向导，完成后自动注册到 projects.yml
- **📂 打开已有项目**：OS 原生文件夹选择器，选中含 `.mimir/config.yml` 的项目目录即可
- **右键/长按项目卡片**：📌 固定 / 📤 从列表移除（不删文件）/ 🗑️ 删除项目（删 .mimir/ 目录，需确认）
- **⚙️ 全局设置**：修改 projects.yml 存储路径

### 项目生命周期

```
新建项目
  → 初始化向导（Step 1-3）
  → 在项目目录下创建 .mimir/config.yml + state.json
  → 在项目根目录创建 CLAUDE.md
  → 注册到 projects.yml
  → 进入 Dashboard 主界面

切换项目
  → 回到项目选择页
  → 选择另一个项目
  → Dashboard 加载新项目的 .mimir/ 下的 config + state

暂停项目
  → 直接切换到其他项目或关闭 Dashboard
  → .mimir/ 文件原样保留
  → 下次打开自动恢复到离开时的状态

归档/删除项目
  → 从 projects.yml 移除（归档 = 仅移除注册，文件保留）
  → 或删除 .mimir/ 目录 + CLAUDE.md（需二次确认）
```

---

## 3. 页面结构与导航

### 整体布局：左侧树导航 + 右侧主工作区

```
┌──────────────────────────────────────────────────────────────┐
│                                                              │
│  ┌── 左侧边栏（240px）──┐  ┌── 右侧主工作区 ────────────┐  │
│  │                       │  │                             │  │
│  │  MIMIR-BO             │  │                             │  │
│  │  [Instance 名称] ⚙️   │  │   根据左侧选中节点         │  │
│  │                       │  │   显示对应内容              │  │
│  │  ▼ 🎯 初始化设置  ✅ │  │                             │  │
│  │    📝 基本信息     ✅ │  │                             │  │
│  │    📂 目录配置     ✅ │  │                             │  │
│  │    🔧 Skill 绑定  ✅ │  │                             │  │
│  │  ▼ 📐 DESIGN 设计    │  │                             │  │
│  │    📋 文档 Checklist  │  │                             │  │
│  │  ▼ ⚙️ BUILD 构建     │  │                             │  │
│  │    🔍 导入检查        │  │                             │  │
│  │    ✂️ 任务分解        │  │                             │  │
│  │    ▼ 🔄 模块执行     │  │                             │  │
│  │      s-1-1 ✅         │  │                             │  │
│  │      s-1-2 ✅         │  │                             │  │
│  │      s-2-2 🔵 ●      │  │                             │  │
│  │      s-2-3 ⬜         │  │                             │  │
│  │      ...              │  │                             │  │
│  │    🏁 完成检查        │  │                             │  │
│  │  ▶ ✅ VERIFY 验证    │  │                             │  │
│  │  ▶ 🚢 SHIP 交付      │  │                             │  │
│  │                       │  │                             │  │
│  │  ─── 项目空间 ─────  │  │                             │  │
│  │  📦 MIMIR 目录        │  │                             │  │
│  │    /Users/.../mimir   │  │                             │  │
│  │  🔧 BO 工具目录       │  │                             │  │
│  │    /Users/.../mimir-bo│  │                             │  │
│  │  📁 项目目录          │  │                             │  │
│  │    /Users/.../voice.. │  │                             │  │
│  │    └─ .mimir/ (工作)  │  │                             │  │
│  │                       │  │                             │  │
│  └───────────────────────┘  └─────────────────────────────┘  │
│                                                              │
└──────────────────────────────────────────────────────────────┘
```

Dashboard 启动后立即显示完整 lifecycle 树。初始化设置是树中的第一个阶段节点（"第 0 步"），未完成时后续所有阶段节点显示为灰色/锁定状态。

### 导航层次：两层半结构

- **Layer 1**: 树导航中的阶段/步骤节点 → 右侧显示对应内容面板
- **Layer 2**: 点击模块节点 → 右侧显示模块执行面板（横向流水线 + 内容区 + 终端）
- **Layer 2.5**: 模块内子步骤（Prompt确认→执行→测试→Review→Fix）在模块面板内横向切换

### 左侧边栏分区

**上部：树状导航**
- 一级节点：初始化设置 / DESIGN / BUILD / VERIFY / SHIP（可展开/折叠）
- 初始化设置完成前，后续节点灰色锁定
- 二级节点：每个阶段内的步骤
- 三级节点：BUILD > 模块执行下的各模块（动态生成，来自任务分解结果）
- 当前活跃节点有脉动指示器
- 状态标记：✅ 完成 / 🔵 进行中 / ⬜ 待开始

**下部：项目空间（始终可见）**
- 📦 MIMIR 目录（紫色系）— MIMIR 方法论本体（skill set 来源），默认折叠
- 🔧 BO 工具目录（灰色系）— MIMIR-BO agent 本体，默认折叠
- 📁 项目目录（绿色系）— src / docs / tests + `.mimir/` 工作子目录，默认展开
  - `.mimir/` 子目录默认展开，显示 prompts / reports / conventions
  - 当前模块相关文件高亮标记
- 每个目录下显示**绝对路径**（来自项目配置）
- 文件树可展开/折叠
- 初始化未完成时，项目空间区域显示"待配置"占位

---

## 4. 模块执行面板（核心工作区）

选中左侧某个模块节点后，右侧显示该模块的执行面板：

```
┌──────────────────────────────────────────────────────────┐
│  [s-2-2] 权限管理模块                    [⌨ 终端]       │
├──────────────────────────────────────────────────────────┤
│                                                          │
│  ┌──────┐  ──▶  ┌──────┐  ──▶  ┌──────┐  ──▶  ┌─────┐ │
│  │Prompt│       │ 执行 │       │ 测试 │       │ Rev │  │
│  │  🧑  │       │  🤖  │       │  🤖  │       │  🧑 │  │
│  └──────┘       └──────┘       └──────┘       └─────┘  │
│                                           ↓             │
│                                     ┌──────────┐        │
│                                     │Fix Loop🤝│        │
│                                     └──────────┘        │
│  ──────────────────────────────────────────────────────  │
│                                                          │
│  [当前子步骤的内容区]                                     │
│                                                          │
│  🧑 等待你的操作                                         │
│  ┌─────────────────────────────────────────────┐        │
│  │ s-2-2-prompt.md                              │        │
│  │ ...prompt 内容...                            │        │
│  │                                              │        │
│  │         [✏️ 编辑]  [❌ Reject]  [✅ Approve] │        │
│  └─────────────────────────────────────────────┘        │
│                                                          │
├──────────────────────────────────────────────────────────┤
│  TERMINAL [claude-code] [tests]                     [✕]  │
│  $ claude                                                │
│  ✅ 创建 src/permissions/router.py                       │
│  ⏳ ...                                                  │
└──────────────────────────────────────────────────────────┘
```

### 4.1 子步骤流水线

- **横向排列**，每个节点标注执行角色（🧑 人 / 🤖 AI / 🤝 协作）
- 活跃节点脉动高亮 + 呼吸灯效果
- 已完成节点连线显示 ─✓▶
- 点击节点切换下方内容区

### 4.2 人机交接规则

- **等待人操作**时：内容区顶部显示蓝色高亮提示"🧑 等待你的操作"
- 提供操作按钮：Approve / Reject / Edit
- **AI 执行中**时：终端面板自动展开，显示实时日志
- 人完成操作（如点击 Approve）后，状态自动流转到下一步

### 4.3 终端集成（方案 B：混合模式）

终端面板采用 **交互式 + headless 混合模式**，根据子步骤自动选择：

| 子步骤 | 终端模式 | 用户体验 | 触发方式 |
|--------|---------|---------|---------|
| 代码实现 | 交互式（`claude`） | 可与 Claude Code 实时对话 | 用户点击 Approve 后自动启动 |
| Fix Loop | 交互式（`claude`） | 可追问、可干预 | Triage 完成后自动启动 |
| 测试 | Headless（`claude --print`） | 只读日志 | 代码实现完成后自动触发 |
| Review Agent | Headless（`claude --print`） | 只读日志 | 测试通过后自动触发 |
| Convention Extraction | Headless（`claude --print`） | 只读日志 | 模块完成后自动触发 |

**终端面板技术实现：**
- 底部可收起/展开，展开时约占 30% 高度
- 支持多 tab（如 claude-code / tests）
- AI 执行步骤时自动展开
- 后端实现：Node.js + node-pty，前端：xterm.js，WebSocket 桥接

**交互式模式**：BO 后端 spawn 一个 pty 进程运行 `claude`，前端 xterm.js 渲染完整终端，用户可输入。

**Headless 模式**：BO 后端 spawn 子进程运行 `claude --print "prompt_content"`，前端显示只读日志窗口。BO 监听 exit code 判断成功/失败，自动流转到下一步。

**两种模式共享同一套 xterm.js + node-pty + WebSocket 基础设施**，差异仅在于前端是否允许用户输入。

### 4.4 CLAUDE.md 自动注入机制

Claude Code 启动 session 时自动读取项目根目录的 `CLAUDE.md`。Dashboard 利用这一原生机制，在每个子步骤切换时自动更新 `CLAUDE.md`，确保 Claude Code 获得正确的上下文。

**位置**：`{项目目录}/CLAUDE.md`（项目根目录）

**写入者**：BO Dashboard（唯一写入者）

**触发时机**：

```
用户在 Dashboard 点击"开始模块 s-X-X"
  │
  ├─ 1. 读取 .mimir/state.json（当前 phase、module、sub_step）
  ├─ 2. 读取 .mimir/config.yml（路径配置）
  ├─ 3. 读取 .mimir/skill-manifest.md（skill 文件列表）
  ├─ 4. 读取 .mimir/conventions/latest.md（前序模块约定）
  ├─ 5. 读取当前模块 prompt 和依赖关系
  ├─ 6. 组装并覆盖写入 CLAUDE.md
  └─ 7. 更新 .mimir/state.json
```

**每次是覆盖写入**，不是追加。CLAUDE.md 在任何时刻都是"当前任务的快照"，约 1KB，不会膨胀。

**CLAUDE.md 内容结构**：

```markdown
# Project: Voice Platform 语音平台
# 由 MIMIR-BO 自动生成，请勿手动编辑
# 最后更新: 2026-02-22T14:30:00Z

## 项目规范

执行任务前，按需读取以下文件：
- 📋 MIMIR Skill Manifest: .mimir/skill-manifest.md
- 📐 Convention Snapshot: .mimir/conventions/latest.md

Skill Manifest 中列出了本项目需要遵循的所有 MIMIR 规范文件路径。
按当前任务的相关性选择性读取，不需要全部加载。
Convention Snapshot 记录了前序模块中提取的代码约定，新模块必须遵循。

## 当前任务

当前阶段: BUILD
当前模块: s-2-2 权限管理
模块状态: 代码实现

### 模块 Prompt
读取并执行: .mimir/prompts/s-2-2/s-2-2-prompt.md

### 模块依赖
- s-1-1 项目基础设施 ✅
- s-1-2 用户认证 ✅

### 设计文档参考
- docs/design/api-design.md — 权限相关 API 端点
- docs/design/security-architecture.md — RBAC 模型
- docs/design/business-rules.md — 权限业务规则

## Git 规范
- commit message: feat(s-2-2): <描述>
- 不要修改不属于当前模块的文件

## 关键约定摘要
（从 convention snapshot 中自动提取最关键的几条）
- Docker: 所有命令在容器内执行，rebuild 在 host 执行
- API: 路由文件放 routers/，业务逻辑放 services/
- 测试: 每个 router 对应一个 test 文件
- Migration: 使用 alembic auto-generate，不手写

## 用户自定义指令
如有个人编码偏好，请同时读取: .claude-user.md
```

**不同子步骤时 CLAUDE.md 的"当前任务"区域自动变化**：

代码实现阶段：
```markdown
## 当前任务
当前模块: s-2-2 权限管理 | 模块状态: 代码实现
### 模块 Prompt
读取并执行: .mimir/prompts/s-2-2/s-2-2-prompt.md
```

Review 阶段：
```markdown
## 当前任务
当前模块: s-2-2 权限管理 | 模块状态: Review
### 任务
你是 review-agent。读取 review 指令：
{tools}/review-agent/system-prompt.md
审查范围：本模块新增/修改的文件（参考最近的 git diff）
输出报告到: .mimir/reports/s-2-2/review-report.md
```

Fix 阶段：
```markdown
## 当前任务
当前模块: s-2-2 权限管理 | 模块状态: Fix
### Fix Prompt
读取并执行: .mimir/reports/s-2-2/fix-prompt.md
```

**作用域说明**：CLAUDE.md 是项目级的，不是全局的。每个项目目录下有自己的 CLAUDE.md，互不影响。

**用户自定义指令**：个人编码偏好放在 `.claude-user.md`（用户手动维护，BO 不触碰），CLAUDE.md 中引用但不覆盖它。

---

## 5. 初始化设置（Lifecycle 第 0 步）

初始化设置不是独立页面，而是左侧树导航中的**第一个阶段节点**。Dashboard 启动后，如果尚未完成初始化，此节点自动展开并高亮，右侧显示对应的设置面板。后续阶段（DESIGN/BUILD/VERIFY/SHIP）全部灰色锁定，直到初始化完成。

完成后可通过左侧栏 instance 名称旁的 ⚙️ 图标重新进入修改。

### 向导步骤（3 步）

**Step 1: 基本信息**
- Instance 名称（如 "Voice Platform 语音平台"）
- 语言偏好（zh / en / bilingual）
- 项目类型选择：
  - ✅ `enterprise-web` — 企业级 Web 应用（可选）
  - 🔒 `lightweight-web` — 轻量 Web 应用（即将支持）
  - 🔒 `mobile-app` — 移动端应用（即将支持）
  - 🔒 `cli-tool` — 命令行工具（即将支持）
  - 🔒 `mvp` — 快速原型（即将支持）
  - 🔒 `minimal` — 最小配置（即将支持）

项目类型决定后续 Skill 绑定中自动加载哪组 MIMIR 项目类型 skill。

**Step 2: 目录配置**

三个目录路径，均使用**原生文件夹选择对话框**（不手动输入）。

| 目录 | 图标 | 说明 | 选择方式 |
|------|------|------|---------|
| MIMIR 目录 | 📦 | MIMIR 方法论**根目录**（包含 zh/ en/ 子目录） | 用户从本机选择 |
| BO 工具目录 | 🔧 | MIMIR-BO（agent、模板所在） | 用户从本机选择 |
| 项目目录 | 📁 | 项目代码目录 | 用户从本机选择 |

工作目录（`.mimir/`）自动创建在项目目录下，不需要用户选择。

MIMIR 多语言目录自动解析规则：
- 用户只需选择 MIMIR 根目录（如 `/Users/amy/dev/mimir`）
- Skill 绑定时，Dashboard 根据 Step 1 中的语言偏好，自动去对应子目录查找：
  - zh → `{mimir}/zh/skills/`
  - en → `{mimir}/en/skills/`
  - bilingual → 优先 zh，回退 en

注意：MIMIR 和 MIMIR-BO 是两个独立的目录/仓库。MIMIR 包含方法论和 skill set，MIMIR-BO 包含 agent 和 dashboard 工具。

**Step 3: MIMIR 内容确认**

Dashboard 自动扫描 `{mimir}/{lang}/` 下所有 `.md` 文件和 `templates/` 目录，全量加载到 skill manifest 中。不再依赖 SKILL.md 入口约定，也不需要用户逐个管理 skill——Claude 在执行任务时会根据当前阶段（DESIGN / BUILD / VERIFY）自行筛选需要的内容。

Step 3 展示两个区域：

```
📦 MIMIR 内容预览（只读，自动扫描结果）
├── 📄 core-principles.md
├── 📄 mimir-readme.md
├── 📁 skills/
│   ├── 📁 claude-code-prompt/ (3 files)
│   ├── 📁 convention-extraction/ (1 file)
│   ├── 📁 meta-knowledge/ (2 files)
│   ├── 📁 retro/ (5 files)
│   ├── 📁 review-agent/ (1 file)
│   └── 📁 project-kickoff/
│       ├── 📁 templates/ (2 files)
│       └── 📁 enterprise-web/ (4 files)
└── 统计：23 个 .md 文件，4 个模板

👤 用户自定义内容（可选）
├── /path/to/my-company-style/   ← 从本机选择添加
└── ＋ 添加自定义目录
```

点击任意 `.md` 文件可在右侧预览内容。

| 分类 | 来源 | 加载规则 |
|------|------|---------|
| 📦 MIMIR 内容 | `{mimir}/{lang}/` 递归扫描 | 全量自动加载所有 .md + templates/ |
| 👤 用户自定义 | 任意本机路径 | 手动添加目录，递归扫描其中 .md 文件 |

### Skill Manifest 生成策略

Manifest 不再列出单个 skill，而是列出**文件路径清单**，供 Agent 执行时按需读取：

```markdown
# MIMIR Skill Manifest
# 项目类型: enterprise-web | 语言: zh

## MIMIR 内容（{mimir}/zh/）
| # | 文件路径 | 大小 |
|---|---------|------|
| 1 | core-principles.md | 2.1KB |
| 2 | mimir-readme.md | 1.5KB |
| 3 | skills/claude-code-prompt/SKILL.md | 4.2KB |
| ... | ... | ... |

## 用户自定义内容
| # | 文件路径 | 大小 |
|---|---------|------|
| 1 | /path/to/my-company-style/coding-rules.md | 1.8KB |

## 使用说明
执行任务前，根据当前任务阶段和内容相关性，选择性读取上述文件。
不需要全部读取，按需加载以节省 context window。
```

### 配置持久化

保存到项目目录下的 `.mimir/config.yml`：

```yaml
instance_name: "Voice Platform 语音平台"
language: zh
project_type: enterprise-web

paths:
  mimir: /Users/amy/dev/MIMIR                  # MIMIR 方法论根目录
  tools: /Users/amy/dev/MIMIR_BO               # MIMIR-BO 工具目录
  project: /Users/amy/dev/voice-platform        # 项目目录
  # 工作目录 = {project}/.mimir/（固定，不可配置）

# MIMIR 内容自动扫描 {mimir}/{language}/ 下所有 .md + templates/
# 无需手动配置 skill 列表

# 用户自定义内容目录（可选）
user_content_dirs: []
  # - /Users/amy/projects/skills/my-company-style

source_docs: {}    # 在 DESIGN 阶段填充，不在初始化时配置
```

---

## 6. MIMIR Skill 注入机制

### 6.1 两层关系

```
MIMIR 方法论
├── 方法论层 → Agent 的设计来源（工作流、质量原则、协作模式）
└── Skill 层 → Agent 执行时注入的领域知识（可插拔）

Agent（如 runprompt-agent）
├── 框架：通用的（来自 MIMIR 方法论，写在 Agent system prompt 中）
└── 知识：可插拔的（来自绑定的 MIMIR skill，运行时文件注入）
```

Agent 框架是通用的，Skill 是可插拔的。同一个 runprompt-agent 框架，绑定 enterprise-web skill 就做 Web 项目，绑定 mobile-app skill 就做移动端项目。

所有 Agent 共享同一套 skill（不按 Agent 分子集）。

### 6.2 Skill 目录结构

MIMIR 和 MIMIR-BO 是两个独立的仓库/目录。Skill 只存放在 MIMIR 中。MIMIR-BO 不提供 skill，只包含 agent 工具。

```
MIMIR/                                 # MIMIR 方法论目录（独立仓库）
├── zh/                                # 中文版
│   └── skills/
│       ├── claude-code-prompt/        # Common skill（通用）
│       │   ├── SKILL.md
│       │   └── templates/
│       ├── convention-extraction/     # Common skill（通用）
│       │   └── SKILL.md
│       ├── meta-knowledge/            # Common skill（通用）
│       │   └── SKILL.md
│       ├── retro/                     # Common skill（通用）
│       │   └── SKILL.md
│       ├── review-agent/              # Common skill（通用）
│       │   └── SKILL.md
│       └── project-kickoff/           # 特殊：按项目类型分子目录
│           ├── templates/
│           └── enterprise-web/        # 项目类型: 企业 Web 应用
│               └── SKILL.md
├── en/                                # 英文版（结构与 zh/ 镜像）
│   └── skills/
│       └── ...
└── ...

MIMIR_BO/                              # MIMIR-BO 工具目录（独立仓库）
├── review-agent/                      # Agent（不是 skill）
├── convention-extraction/             # Agent
├── dashboard/                         # 本 Dashboard 项目
├── docs/
└── projects.yml                       # 项目注册表
```

Skill 分类规则（语义区分，非目录层级区分）：
- **Common**：`{mimir}/{lang}/skills/` 下除 `project-kickoff` 以外的所有顶级目录
- **project-kickoff**：`{mimir}/{lang}/skills/project-kickoff/{project_type}/` 根据项目类型加载对应子目录
- **用户自定义**：任意本机路径（通过文件夹选择器添加）

设计原则：
- MIMIR 方法论独立维护，按语言版本组织（zh/ en/）
- MIMIR-BO 只包含 agent 工具，不提供 skill
- 每个 skill 自包含（目录 + SKILL.md），创建新 skill 门槛低
- SKILL.md 作为入口，可引用同目录下其他文件，Agent 按需读取（节省 context window）

### 6.3 SKILL.md 最小模板

```markdown
# {Skill 名称}

## 适用范围
（这个 skill 适用于什么类型的项目/场景）

## 核心原则
（必须遵循的规则，Agent 每次执行任务时都应读取本节）

## 详细规范
（可选，引用同目录下的其他文件，Agent 按当前任务相关性按需读取）
- 详见 [docker-conventions.md](./docker-conventions.md)
- 详见 [api-conventions.md](./api-conventions.md)

## 示例
（可选）
```

分层设计：「核心原则」= 必读，「详细规范」= 按需读取，控制 context 消耗。

### 6.4 Skill 绑定与优先级

在 `.mimir/config.yml` 中通过 `mimir_skills` 列表绑定，**列表顺序即优先级**（排在前面的优先）。

初始化时根据项目类型和语言偏好自动填充三类 skill：

| source 值 | 扫描路径 | 触发条件 |
|-----------|---------|---------|
| `mimir-common` | `{mimir}/{lang}/skills/common/` | 始终自动加载 |
| `mimir-project-type` | `{mimir}/{lang}/skills/{project_type}/` | 根据项目类型自动加载 |
| `bo-agent` | `{tools}/agents/*/skills/` | 自动扫描所有 agent |
| `user` | 用户任意路径 | 手动添加（文件夹选择器） |

默认优先级：MIMIR Common → MIMIR 项目类型 → BO Agent → 用户自定义。用户可拖拽排序调整。

冲突解决策略：**优先级由列表顺序决定，用户可通过拖拽排序控制**。Dashboard 设置页面提供可拖拽排序的列表 UI。

### 6.5 注入机制：CLAUDE.md + Skill Manifest

BO 自动生成 `skill-manifest.md` 到 `.mimir/` 目录，并通过 `CLAUDE.md`（见 §4.4）引用它。

Context 组装过程：

```
Claude Code 启动 session
  ↓ 自动读取
CLAUDE.md（项目根目录）
  ↓ 其中指向
.mimir/skill-manifest.md → 获得 skill 列表和路径
  ↓ Claude Code 按需读取
各 SKILL.md 入口 → 按需读取引用的详细规范文件
  ↓ 加上
.mimir/conventions/latest.md（前序模块约定）
  ↓ 加上
项目设计文档（docs/design/ 下的文件）
  ↓ 加上
当前任务的具体 prompt（.mimir/prompts/s-X-X/）
  = 完整的执行上下文
```

### 6.6 Manifest 重新生成时机

三个触发点：
1. BO Dashboard 启动时
2. `.mimir/config.yml` 的 skill 配置变更时
3. 用户在设置页面手动点击「刷新 Skill」时

不需要 watch 文件系统变化（skill 变更不频繁），SKILL.md 内容的变更在下次 Agent 运行时自动生效（因为 Agent 每次都从文件读取）。

### 6.7 Skill 生命周期

```
选择 Skill Set
  初始化时选择 MIMIR skill set 类型（如 enterprise-web）
  → 该 set 下所有 skill 自动添加到列表
      ↓
添加用户 Skill（可选）
  通过本机文件夹选择器，选择包含 SKILL.md 的目录
      ↓
调整优先级（可选）
  拖拽排序，或删除不需要的 skill
      ↓
生成 manifest
  BO 自动生成 skill-manifest.md 到 .mimir/
      ↓
Agent 消费
  Agent 运行时通过 CLAUDE.md → manifest → 按需读取各 SKILL.md → 执行任务
      ↓
更新 skill
  用户直接编辑 SKILL.md，下次 Agent 运行自动生效（无需重启）
      ↓
停用 skill
  从列表中移除，manifest 自动更新
```

### 6.8 在 Dashboard 中的体现

- **初始化设置 Step 3**：选择 skill set 类型 → 自动列出 set 内 skill → 可添加用户自定义 skill（本机文件夹选择器）→ 可拖拽排序
- **设置页面（⚙️）**：可重新进入修改 skill set 类型、增删 skill、调整优先级
- **左侧项目空间**：MIMIR 目录下显示 `skills/` 文件夹结构，用户可查看已安装的 skill set
- **模块执行面板**：终端日志中可看到 Agent 读取了哪些 skill 文件

---

## 7. 状态持久化

### 两层持久化

```
Dashboard 级别（跨项目）
  └── projects.yml — 项目注册表
      存储位置：默认 {BO工具目录}/projects.yml
      用户可在全局设置中修改

项目级别（每个项目独立，存储在 {项目目录}/.mimir/ 下）
  ├── config.yml             — 项目配置
  ├── state.json             — 项目进度状态
  └── skill-manifest.md      — MIMIR 内容清单（自动生成）

项目根目录
  └── CLAUDE.md              — Claude Code 上下文注入（BO 自动维护）
```

### state.json

```json
{
  "project": "voice-platform",
  "current_phase": "BUILD",
  "updated_at": "2026-02-20T10:30:00Z",
  "phases": {
    "DESIGN": {
      "status": "completed",
      "checklist": {
        "prd": { "status": "done", "path": "docs/design/prd.md" }
      }
    },
    "BUILD": {
      "status": "in_progress",
      "import_check": "completed",
      "task_decompose": "completed",
      "modules": {
        "s-1-1": { "status": "completed", "sub_step": "done" },
        "s-2-2": { "status": "in_progress", "sub_step": "prompt_review" }
      },
      "checkpoint": "pending"
    },
    "VERIFY": { "status": "pending" },
    "SHIP": { "status": "pending" }
  }
}
```

- 建议纳入 git 管理，可追踪工作流推进历史
- 打开项目时读取，恢复到离开时的确切状态
- 每次状态变更自动写入
- 切换/关闭项目时无需额外保存（已实时持久化）

### .gitignore 策略

```gitignore
# .mimir/ — BO 工作目录（中间产物）
.mimir/

# 如需追踪项目状态和配置，可选择性保留：
# !.mimir/config.yml
# !.mimir/state.json
# !.mimir/conventions/
```

CLAUDE.md 建议纳入 git（内容是有价值的项目 context 快照）。

---

## 8. 技术栈

| 层 | 技术 | 说明 |
|----|------|------|
| 前端 | Vue 3 + Vite | 熟悉的技术栈 |
| 后端 | Node.js (Express) | 进程管理、WebSocket |
| 终端 | node-pty + xterm.js | Claude Code CLI 桥接（交互式 + headless） |
| 通信 | WebSocket | 终端实时输出、状态推送 |
| 持久化 | YAML + JSON 文件 | config.yml + state.json |
| 运行 | localhost | 先本地，后续可部署 |

---

## 9. 实现阶段建议

### Phase 1: 骨架 + 状态管理
- 项目初始化向导（配置页面，3 步）
- 左侧树导航 + 右侧面板路由
- 项目空间文件树（读取真实文件系统）
- `.mimir/` 目录创建 + config.yml / state.json 读写
- CLAUDE.md 自动生成（初始化完成时创建首版）
- 多项目管理（projects.yml 注册表、项目选择页）

### Phase 2: BUILD 工作流 + 基础终端
- 导入检查（扫描设计文档）
- 任务分解结果展示（读取已有分解结果）
- 模块执行面板（子步骤流水线 UI）
- CLAUDE.md 子步骤联动（每次子步骤切换时自动更新）
- **Headless 终端集成**：`claude --print` 执行 review / test / convention-extraction
  - node-pty + xterm.js + WebSocket 基础设施搭建
  - 只读日志展示
  - exit code 监听 + 状态自动流转

### Phase 3: 交互式终端 + Agent 集成
- **交互式终端集成**：代码实现 + Fix Loop 使用 `claude` 交互模式
  - 前端 xterm.js 允许用户输入
  - BO 后端控制 session 启动/终止
- Prompt 确认 → Claude Code 执行的完整流程
- Review Agent 触发 + Triage 面板
- Convention Extraction Agent 触发
- 状态自动流转（人机交接规则实现）

### Phase 4: VERIFY / SHIP
- 测试 Agent 集成
- 文档生成 Agent (doc-gen-agent) 集成
- 部署流程

---

## 10. DESIGN 阶段引导（待细化）

DESIGN 是 lifecycle 的第一个正式阶段（初始化之后）。Dashboard 在此阶段提供引导，帮助用户完成设计工作并将文档落盘到项目目录。

### 工具选择

用户可在以下环境完成 DESIGN 阶段（Dashboard 不强制指定）：
- **Claude Desktop Chat**（推荐）：结合 Cowork 可直接将文档落盘
- **Claude.ai Web**：通过 Project 功能组织讨论
- **任何其他工具**：只要最终文档落盘到 `docs/design/` 即可

### 设计文档导入

1. 在 Claude Desktop Chat 或 Claude.ai 中完成设计讨论
2. 将产出文档保存到项目目录的 `docs/design/`
3. 回到 Dashboard，DESIGN 阶段的 Checklist 自动扫描检测文档

具体引导内容和 Checklist 交互待后续讨论细化。

---

## 11. 项目文件全景图

```
{项目目录}/                              ← Claude Code 的 cwd
├── CLAUDE.md                            ← BO 自动维护（~1KB，覆盖写入）
│                                           Claude Code 启动时自动读取
├── .claude-user.md                      ← 用户手动维护（可选，BO 不触碰）
│
├── .mimir/                              ← BO 工作目录（中间产物）
│   ├── config.yml                       ← 项目配置
│   ├── state.json                       ← 项目状态
│   ├── skill-manifest.md                ← MIMIR 内容清单（BO 自动生成）
│   ├── conventions/
│   │   └── latest.md                    ← Convention Snapshot
│   ├── prompts/
│   │   ├── s-1-1/
│   │   │   └── s-1-1-prompt.md
│   │   ├── s-2-2/
│   │   │   ├── s-2-2-prompt.md
│   │   │   └── s-2-2-fix-prompt.md
│   │   └── ...
│   └── reports/
│       ├── s-2-2/
│       │   ├── review-report.md
│       │   └── fix-prompt.md
│       └── ...
│
├── src/                                 ← 项目源代码
├── docs/
│   └── design/                          ← 设计文档（DESIGN 阶段产出）
│       ├── prd.md
│       ├── api-design.md
│       ├── database-design.md
│       ├── state-machines.md
│       ├── business-rules.md
│       └── security-architecture.md
├── tests/
├── docker-compose.yml
└── .gitignore
```

CLAUDE.md 是这个文件体系的"入口指针"——它不存储大段内容，只告诉 Claude Code"当前该做什么、去哪里读详细信息"。所有路径均为相对路径，项目可移植。
