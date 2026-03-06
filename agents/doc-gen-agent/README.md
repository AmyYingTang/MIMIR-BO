# Doc-Gen Agent

> MIMIR-BO 文档生成 Agent — 从设计文档自动生成用户文档

## 它做什么

读取项目的设计文档（PRD、API 设计、状态机、业务规则等），自动生成面向特定读者的用户文档。

```
设计文档 → 分析 → 骨架 → 逐页填充 → 自检 → 构建
              ↑        ↑                    ↑
           人工确认  人工确认             人工确认
```

**这不是一键全自动工具**——每个关键步骤后你需要 review 产出，确认后再继续。这是设计上的选择：AI 生成 + 人工把关 = 高质量文档。

## 三层分离

Agent 的产出严格分为三层：

| 层 | 内容 | 来源 | 生命周期 |
|----|------|------|---------|
| **Layer 1: Generic** | 骨架模板、写作规则、system prompt | agent 自带 | 随 agent 版本更新 |
| **Layer 2: Project-specific** | 分析报告、提取 prompt、骨架 .md | Step 1+2 动态生成 | 每次运行时重新生成 |
| **Layer 3: Final** | 最终文档内容 | Step 3 填充产出 | 最终交付物 |

Generic 模板不含任何项目信息（没有章节号、角色名、端点列表），确保跨项目可复用。项目特定的提取指令由 agent 在 skeleton 阶段结合分析报告动态生成。

## 快速开始

### 1. 准备配置文件

每种文档类型有独立的配置文件，`doc_type`/`audience`/`output_dir` 已预设：

```bash
# 选择你要生成的文档类型
cp doc-gen-agent/templates/doc-gen-user.yml ./doc-gen-user.yml    # 用户指南
cp doc-gen-agent/templates/doc-gen-admin.yml ./doc-gen-admin.yml  # 管理员手册
cp doc-gen-agent/templates/doc-gen-ops.yml ./doc-gen-ops.yml      # 运维手册
```

编辑配置文件，修改 `source_docs` 为项目实际的源文档路径。其他字段通常不需要改。

### 2. 分步执行（推荐）

```bash
# Step 1: 分析源文档 → 生成 analysis-report.md
./doc-gen-agent/doc-gen.sh ./doc-gen-user.yml analyze ~/your-project
#
# 👀 review: 看看源文档分析得对不对
#    中间产物在 doc-gen-agent/.work/user-guide/
cat doc-gen-agent/.work/user-guide/analysis-report.md

# Step 2: 生成骨架 + 提取 prompt
./doc-gen-agent/doc-gen.sh ./doc-gen-user.yml skeleton ~/your-project
#
# 👀 review: 骨架结构合不合适？提取 prompt 准确吗？
#    doc-gen-agent/.work/user-guide/docs/*.md        ← 骨架文件
#    doc-gen-agent/.work/user-guide/fill-order.md    ← 填充顺序
#    doc-gen-agent/.work/user-guide/prompts/*.md     ← 提取 prompt

# Step 3: 逐页填充（最耗时的步骤）
./doc-gen-agent/doc-gen.sh ./doc-gen-user.yml fill ~/your-project

# Step 4: 自检 + 构建 → 最终产物输出到 project-dir/docs/user-guide/
./doc-gen-agent/doc-gen.sh ./doc-gen-user.yml qa ~/your-project
#
# 👀 review: 看自检报告，处理 [待确认] 和补截图
cat doc-gen-agent/.work/user-guide/qa-report.md
# 最终文档在 ~/your-project/docs/user-guide/

# Step 5: 单独重新构建（补截图或修正 .md 后，不重跑 fill）
./doc-gen-agent/doc-gen.sh ./doc-gen-user.yml build ~/your-project
```

### 3. 一键执行（all 模式）

```bash
./doc-gen-agent/doc-gen.sh ./doc-gen-user.yml all ~/your-project
```

`all` 模式依次执行 analyze → skeleton → fill → qa，但会在 skeleton 完成后**暂停**，让你 review 骨架和 prompts。确认后输入 `y` 继续。

如果想跳过暂停（比如你已经跑过一次、对骨架有信心），在配置文件中设置：

```yaml
auto_build: true    # 跳过中间暂停，一键直出
```

### 4. 补截图和修正

```bash
# 将截图放到 work_dir 的 docs 目录
cp screenshots/*.png doc-gen-agent/.work/user-guide/docs/images/

# 在 .md 文件中替换截图占位
#   <!-- TODO: 截图 — xxx --> → ![描述](images/xxx.png)

# 重新构建（只构建，不重跑 fill）
./doc-gen-agent/doc-gen.sh ./doc-gen-user.yml build ~/your-project
```

`build` 命令从 work_dir 的已填充 .md 文件重新生成最终产物到 output_dir，适用于补截图、修正文字、处理 `[待确认]` 后的快速重建。

## 配置文件

每种 type 一个配置文件，`doc_type`/`audience`/`output_dir` 写死，只需改源文档路径：

| 配置文件 | doc_type | audience | output_dir |
|----------|----------|----------|------------|
| `doc-gen-user.yml` | user-guide | end-user | docs/user-guide |
| `doc-gen-admin.yml` | admin-guide | admin | docs/admin-guide |
| `doc-gen-ops.yml` | ops-manual | ops | docs/ops-manual |

同时需要 user-guide 和 admin-guide 时，两个配置文件分别执行。

### 配置文件结构

```yaml
# === 固定配置（本文件专用）===
doc_type: user-guide
audience: end-user

# === 项目配置（按项目修改）===
language: zh                    # zh | en | bilingual
output_format: single-html     # single-html | mkdocs | markdown-only
auto_build: false               # true=all模式跳过暂停 | false=skeleton后暂停review（默认）

source_docs:                    # 源文档路径（相对于 project-dir）
  prd: docs/design/prd.md
  api_design: docs/design/api-design.md
  # ...可按需添加

# === 输出路径 ===
# work_dir: 中间产物存放位置
#   默认: {agent目录}/.work/{doc_type}/（不污染项目目录）
#   取消注释可自定义:
# work_dir: /path/to/custom/workdir

# output_dir: 最终交付物（相对于 project-dir）
output_dir: docs/user-guide     # 只放 single-html 或 site/

writing_rules:
  tone: friendly-professional   # friendly-professional | formal | casual
  no_technical_terms: true      # end-user=true, admin/ops=false
  screenshot_placeholders: true
  unknown_value_marker: '[待确认]'

site:                           # 站点元信息
  name: ''                      # 留空自动生成
  color_primary: '#3f51b5'
```

## 输出格式

| output_format | 说明 | 输出 | 适合场景 |
|---------------|------|------|---------|
| `single-html` | 自包含单页 HTML，CSS/JS 内联 | 一个 `.html` 文件 | 快速分享、双击即看 |
| `mkdocs` | 多页站点 | `site/` 目录 | 正式部署 |
| `markdown-only` | 只生成 .md 文件 | `docs/` 目录 | 集成到现有文档体系 |

`single-html` 推荐用于分享和预览（零依赖，双击可看）；`mkdocs` 适合正式文档站点。

## 支持的文档类型

| doc_type | 说明 | 骨架模板 |
|----------|------|---------|
| `user-guide` | 终端用户操作指南 | ✅ `user-guide.yml` |
| `admin-guide` | 管理员操作指南 | ✅ `admin-guide.yml` |
| `ops-manual` | 运维部署手册 | ✅ `ops-manual.yml` |
| `api-doc` | API 参考文档 | ⬜ 计划中 |

## 输出结构

中间产物和最终交付物分开存放：

```
{agent目录}/.work/{doc_type}/      ← work_dir（中间产物，不污染项目）
├── analysis-report.md             # Step 1: 源文档分析报告
├── fill-order.md                  # Step 2: 填充依赖顺序
├── qa-report.md                   # Step 4: 自检报告
├── prompts/                       # Step 2: 提取 prompt
│   ├── 00-common-rules.md
│   ├── 01-limits.md
│   └── ...
├── docs/                          # Step 2→3: 骨架 → 填充后的 .md
│   ├── index.md
│   ├── quickstart.md
│   ├── guides/
│   ├── reference/
│   └── faq.md
└── mkdocs.yml                     # mkdocs 格式时生成

{project-dir}/{output_dir}/        ← output_dir（最终交付物）
└── user-guide.html                # single-html 输出
    或 site/                       # mkdocs build 输出
```

## 交互式工作流详解

```
你                          Agent                        产出
──                          ─────                        ────
准备 doc-gen-*.yml
  ↓
执行 analyze ──────────→  扫描源文档 ─────────────→  work_dir/analysis-report.md
  ↓
review 分析报告
确认 or 调整配置
  ↓
执行 skeleton ─────────→  读取 generic 模板           work_dir/prompts/*.md
                          + analysis-report     ──→  work_dir/docs/*.md (骨架)
                          动态生成 prompts             work_dir/fill-order.md
  ↓
review 骨架和 prompts
  ↓
执行 fill ─────────────→  逐页读取 prompt     ──→  work_dir/docs/*.md (已填充)
                          + 源文档，填充骨架
  ↓
执行 qa ───────────────→  自检 + 构建         ──→  work_dir/qa-report.md
                                                    output_dir/ ← 最终交付物
  ↓
review qa-report
补截图、修正 [待确认]
  ↓
执行 build（如需重建）──→  重新构建            ──→  output_dir/ ← 更新
```

## 在 BO 工作流中的位置

```
模块全部完成 → review-agent → 人工验收
    → doc-gen-agent → 人工 review（补截图等）→ build → SHIP
```

## 前置依赖

| 依赖 | 用途 | 必须？ |
|------|------|--------|
| `claude` CLI | Agent 执行引擎 | ✅ |
| Python 3 | stream-json 解析 + single-html 构建 | ✅ |
| `mkdocs` + `mkdocs-material` | mkdocs 格式构建 | 仅 mkdocs 模式 |

## 文件清单

```
doc-gen-agent/
├── doc-gen.sh                    # 主执行脚本
├── single-html-build.py          # 单文件 HTML 构建脚本
├── system-prompt.md              # Agent 行为准则
├── DESIGN.md                     # 设计文档
├── README.md                     # 本文件
└── templates/
    ├── doc-gen-user.yml          # User Guide 配置模板
    ├── doc-gen-admin.yml         # Admin Guide 配置模板
    ├── doc-gen-ops.yml           # Ops Manual 配置模板
    ├── user-guide.yml            # User Guide 骨架模板（generic）
    ├── admin-guide.yml           # Admin Guide 骨架模板（generic）
    ├── ops-manual.yml            # Ops Manual 骨架模板（generic）
    └── common-rules.md           # 通用写作指令模板
```

## 版本

- v0.3 — 三层分离重构（generic 模板 / project-specific prompts / final 文档）；配置文件按 type 拆分；骨架模板清除项目特定内容
- v0.2 — 新增 `single-html` 输出格式、`auto_build` 配置、`build` 单步命令
- v0.1 — 初始版本
