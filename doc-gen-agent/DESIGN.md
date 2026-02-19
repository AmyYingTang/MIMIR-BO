# Doc-Gen Agent 设计文档

> MIMIR-BO 文档生成 Agent — 从设计文档自动生成用户文档

---

## 1. 定位与边界

### 在 BO 中的位置

```
MIMIR-BO Agent 家族
├── runprompt-agent    — 执行 Prompt 生成代码
├── review-agent       — 独立代码审查
├── convention-extraction-agent  — 模式提取
└── doc-gen-agent      — 文档生成          ← 本文档
```

在 lifecycle 中的触发点：**VERIFY 通过后、SHIP 之前**，或按需触发。

```
模块全部完成 → review-agent → 人工验收 → doc-gen-agent → mkdocs build → SHIP
                                              ↑ 你在这里
```

### 与其他 Agent 的区别

| Agent | 输入 | 输出 | 核心操作 |
|-------|------|------|---------|
| runprompt-agent | Prompt 文件 | 项目代码 | 执行代码生成指令 |
| review-agent | 代码 + 设计文档 | Review 报告 | 对照检查 |
| convention-extraction | 代码 | Convention 快照 | 模式扫描提取 |
| **doc-gen-agent** | **设计文档** | **用户文档站点** | **分析→骨架→填充→构建** |

---

## 2. 工作流总览

```
┌─────────────────────────────────────────────────────────────────┐
│                     doc-gen-agent 管线                           │
│                                                                 │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌─────────────┐ │
│  │ Step 1   │   │ Step 2   │   │ Step 3   │   │ Step 4      │ │
│  │ 分析源   │──▶│ 生成骨架 │──▶│ 逐页填充 │──▶│ 自检+构建   │ │
│  │ 文档     │   │ + prompt  │   │          │   │             │ │
│  └──────────┘   └──────────┘   └──────────┘   └─────────────┘ │
│       │              │              │                │          │
│   读取配置       输出骨架 .md    调用 Claude     扫描 [待确认]   │
│   扫描目录       输出 prompts    Code 填充      mkdocs build   │
│   生成清单       输出依赖图      覆盖写回        输出报告       │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. 配置文件设计

Agent 的行为由一个 `doc-gen.yml` 配置文件驱动：

```yaml
# doc-gen.yml — 文档生成配置
# 放在项目根目录或 docs/ 目录下

# === 基本信息 ===
doc_type: user-guide          # user-guide | admin-guide | api-doc | ops-manual
audience: end-user            # end-user | admin | developer | ops
language: zh                  # zh | en | bilingual
output_format: mkdocs         # mkdocs | vitepress | markdown-only

# === 源文档路径 ===
source_docs:
  prd: docs/design/prd.md
  api_design: docs/design/api-design.md
  database_design: docs/design/database-design.md
  state_machines: docs/design/state-machines.md
  business_rules: docs/design/business-rules.md
  security_arch: docs/design/security-architecture.md

# === 输出路径 ===
output_dir: docs/user-guide       # 骨架和填充后的 .md 文件
site_dir: docs/user-guide/site    # mkdocs build 输出

# === 写作约束 ===
writing_rules:
  tone: friendly-professional     # friendly-professional | formal | casual
  no_technical_terms: true        # 禁止暴露 API 路径、数据库字段等
  max_admonition_length: 3        # admonition 内容最多几句话
  screenshot_placeholders: true   # 是否生成截图占位标记
  unknown_value_marker: "[待确认]" # 源文档中缺失信息的标记

# === 骨架模板（可选，不指定则自动推导）===
# skeleton_template: templates/user-guide-skeleton.yml
```

### 不同 doc_type 的默认骨架

Agent 内置的骨架模板映射：

```yaml
# 内置模板库（agent 内部）
templates:
  user-guide:
    pages:
      - index.md:          { sources: [prd], role: "平台概览" }
      - quickstart.md:     { sources: [synthesized], role: "3步快速开始" }
      - guides/:
        - model-create.md: { sources: [api_design, business_rules], role: "创建操作指南" }
        - model-train.md:  { sources: [state_machines, business_rules, database_design], role: "训练流程" }
        - model-test.md:   { sources: [api_design, business_rules], role: "试听测试" }
        - model-manage.md: { sources: [api_design, business_rules, database_design], role: "管理操作" }
      - reference/:
        - permissions.md:  { sources: [security_arch, api_design], role: "权限说明" }
        - limits.md:       { sources: [business_rules, api_design], role: "配额限制" }
        - status-guide.md: { sources: [state_machines, database_design], role: "状态速查" }
      - faq.md:            { sources: [synthesized], role: "常见问题" }

  admin-guide:
    pages:
      - index.md:          { sources: [prd, security_arch], role: "管理员概览" }
      - quickstart.md:     { sources: [synthesized], role: "管理员快速上手" }
      - guides/:
        - user-management.md:  { sources: [api_design, security_arch, business_rules], role: "用户管理" }
        - audit-logs.md:       { sources: [api_design, database_design], role: "审计日志查看" }
        - system-config.md:    { sources: [business_rules, api_design], role: "系统配置" }
        - monitoring.md:       { sources: [api_design], role: "监控与告警" }
      - reference/:
        - role-matrix.md:      { sources: [security_arch], role: "完整权限矩阵" }
        - api-reference.md:    { sources: [api_design], role: "管理API参考" }
      - faq.md:                { sources: [synthesized], role: "管理员FAQ" }
```

---

## 4. Agent 主 Prompt（System Prompt）

```markdown
# Doc-Gen Agent System Prompt

你是 MIMIR-BO 的文档生成 Agent（doc-gen-agent），负责从项目设计文档自动生成面向特定读者的用户文档。

## 你的身份
- 你是一个技术文档写作专家
- 你严格遵循配置文件中的 writing_rules
- 你不会自行决定文档结构——结构由骨架模板决定
- 你只负责用源文档中的真实信息填充骨架中的 TODO 标记

## 核心原则

### 读者意识
- end-user: 禁止一切技术术语（API 路径、数据库字段、HTTP 方法、框架名称）
- admin: 允许管理概念（角色、权限、审计），禁止实现细节（SQL、ORM、中间件）
- developer: 允许技术细节，保持准确
- ops: 允许运维术语（部署、监控、日志），禁止业务逻辑细节

### 信息忠实度
- 只使用源文档中明确存在的信息，不编造
- 源文档中找不到的数值，标记为 [待确认]
- 从技术描述到用户语言的转化必须保持语义等价

### 填充规则
- 保留 Markdown 原有结构（标题层级、admonition 语法、表格格式）
- 保留截图占位标记（<!-- TODO: 截图 -->）
- 每个 admonition 内容不超过 writing_rules.max_admonition_length 句话
- 中文输出时，技术名词首次出现括号标注英文

## 执行流程

你会被以下方式调用：

### 模式 A：生成骨架
输入：doc-gen.yml 配置 + 源文档路径清单
输出：带 TODO 标记的 Markdown 骨架文件 + mkdocs.yml

### 模式 B：填充单页
输入：一个骨架 .md 文件 + 该页面需要的源文档内容
输出：填充完成的 .md 文件（覆盖原文件）

### 模式 C：自检报告
输入：所有已填充的 .md 文件
输出：自检报告（[待确认] 数量、跨页链接检查、术语一致性）
```

---

## 5. 四步执行详细设计

### Step 1: 分析源文档

**Agent 指令：**
```
读取 doc-gen.yml 配置文件。
扫描 source_docs 中列出的所有文件，确认每个文件存在且非空。
对每个源文档生成一行摘要：文件名 | 主要覆盖内容 | 预估可提取的用户文档条目数。
输出源文档覆盖分析报告到 {output_dir}/analysis-report.md。
如果有 doc_type 所需但源文档中完全未覆盖的领域，在报告中标记为 ⚠️ 缺失。
```

**输出示例：**
```markdown
# 源文档分析报告

| 源文档 | 覆盖内容 | 可提取条目 |
|--------|---------|-----------|
| prd.md | 用户故事 12 个，功能模块 4 个 | 首页概览、快速开始流程 |
| api-design.md | 端点 23 个，覆盖 CRUD + TTS | 操作指南全部 4 页 |
| state-machines.md | 状态 6 个，流转 8 条 | 状态速查、训练说明 |
| business-rules.md | 规则 15 条 | 配额限制、FAQ |
| security-arch.md | 角色 3 个，权限 12 项 | 权限页 |
| database-design.md | 表 8 个，关键字段 retry_count, expires_at | 状态速查补充 |

⚠️ 缺失：监控告警相关内容（admin-guide 需要但无源文档）
```

### Step 2: 生成骨架 + 提取 Prompt

**Agent 指令：**
```
根据 doc-gen.yml 的 doc_type 和源文档分析报告：

1. 选择对应的内置骨架模板（或使用 skeleton_template 自定义模板）
2. 为每个页面生成带 TODO 标记的 .md 骨架文件，每个 TODO 必须包含：
   - 从哪个源文档提取
   - 提取什么内容
   - 转化为什么形式（表格/步骤/说明/FAQ）
3. 生成 mkdocs.yml 配置文件
4. 生成填充依赖图 fill-order.md，标注三批执行顺序：
   - 第1批：纯数据提取页（可并行）
   - 第2批：操作指南页（可并行，但建议按功能流程顺序）
   - 第3批：综合页（必须串行，依赖前两批结果）
5. 为每个页面生成提取 prompt，保存到 {output_dir}/prompts/ 目录
```

**输出文件结构：**
```
{output_dir}/
├── analysis-report.md        ← Step 1 产出
├── fill-order.md             ← 填充依赖图
├── prompts/                  ← 每页的提取 prompt
│   ├── 00-common-rules.md    ← 通用写作指令
│   ├── 01-limits.md
│   ├── 02-permissions.md
│   ├── 03-status-guide.md
│   ├── 04-model-create.md
│   ├── ...
│   └── 10-index.md
├── mkdocs.yml
└── docs/                     ← 骨架 .md 文件
    ├── index.md
    ├── quickstart.md
    ├── guides/
    ├── reference/
    └── faq.md
```

### Step 3: 逐页填充

**Agent 指令（对每个页面重复执行）：**
```
读取 {output_dir}/prompts/00-common-rules.md 作为通用指令。
读取 {output_dir}/prompts/{NN}-{page-name}.md 作为本页任务。
读取任务中指定的源文档。
读取 {output_dir}/docs/{page-path} 作为目标骨架。
按 TODO 标记逐项填充，输出完整 Markdown，覆盖写回原文件。
```

**执行顺序由 fill-order.md 控制：**
```markdown
# 填充执行顺序

## 第1批（数据提取页，可并行）
1. reference/limits.md       ← business-rules + api-design
2. reference/permissions.md  ← security-arch + api-design
3. reference/status-guide.md ← state-machines + database-design

## 第2批（操作指南页，建议按顺序）
4. guides/model-create.md   ← api-design + business-rules
5. guides/model-train.md    ← state-machines + business-rules + database-design
6. guides/model-test.md     ← api-design + business-rules
7. guides/model-manage.md   ← api-design + business-rules + database-design

## 第3批（综合页，必须串行）
8. quickstart.md            ← 已填充的 create + train + test
9. faq.md                   ← 已填充的全部页面
10. index.md                ← 已填充的 quickstart + limits
```

### Step 4: 自检 + 构建

**Agent 指令：**
```
对 {output_dir}/docs/ 下所有已填充的 .md 文件执行以下检查：

1. [待确认] 扫描：列出所有仍包含 [待确认] 的位置（文件:行号:上下文）
2. 链接检查：验证所有页面间链接的目标文件存在
3. 术语一致性：检查同一概念是否在不同页面使用了不同名称
4. 截图占位统计：列出所有 <!-- TODO: 截图 --> 的位置
5. 数值一致性：检查同一数值（如配额上限）在不同页面是否一致

输出自检报告到 {output_dir}/qa-report.md。

如果 output_format 为 mkdocs：
  执行 mkdocs build --strict
  报告构建结果（成功/失败/警告数）
```

**自检报告示例：**
```markdown
# 文档自检报告

## 📊 总览
- 页面总数：10
- 填充完成：10/10
- [待确认] 标记：2 处
- 断链：0
- 截图占位：8 处

## ⚠️ [待确认] 详情
| 文件 | 行号 | 上下文 |
|------|------|--------|
| guides/model-train.md | 42 | 训练时长 [待确认] 分钟 |
| reference/limits.md | 18 | 每日试听次数 [待确认] |

## ✅ 术语一致性：通过
## ✅ 数值一致性：通过
## ✅ 链接检查：通过

## 📸 截图占位（8处）
- quickstart.md: 3 处（登录页、创建页、训练状态页）
- guides/model-create.md: 2 处（列表页、创建表单）
- ...

## 🔨 构建结果
mkdocs build: ✅ 成功（0 警告）
```

---

## 6. Runner 脚本设计

### doc-gen.sh — 主执行脚本

```bash
#!/bin/bash
# doc-gen.sh — MIMIR-BO Doc-Gen Agent Runner
# 用法: ./doc-gen.sh [config-path] [step]
#   config-path: doc-gen.yml 的路径（默认: ./doc-gen.yml）
#   step:        all | analyze | skeleton | fill | qa（默认: all）

set -euo pipefail

CONFIG="${1:-./doc-gen.yml}"
STEP="${2:-all}"

# 检查依赖
command -v claude >/dev/null 2>&1 || { echo "❌ claude CLI not found"; exit 1; }

# 解析配置（简易 YAML 解析）
OUTPUT_DIR=$(grep 'output_dir:' "$CONFIG" | awk '{print $2}')
DOC_TYPE=$(grep 'doc_type:' "$CONFIG" | awk '{print $2}')

echo "📄 Doc-Gen Agent"
echo "   Type: $DOC_TYPE"
echo "   Output: $OUTPUT_DIR"
echo "   Step: $STEP"
echo ""

# === Step 1: 分析源文档 ===
run_analyze() {
    echo "🔍 Step 1: 分析源文档..."
    claude --print "$(cat <<EOF
读取配置文件 $CONFIG。
扫描其中 source_docs 列出的所有文件。
对每个文件生成摘要：文件名 | 覆盖内容 | 可提取条目。
标记缺失领域。
输出到 ${OUTPUT_DIR}/analysis-report.md。
EOF
    )" --allowedTools "Read,Write" 2>/dev/null
    echo "  ✅ 分析报告: ${OUTPUT_DIR}/analysis-report.md"
}

# === Step 2: 生成骨架 ===
run_skeleton() {
    echo "🦴 Step 2: 生成骨架 + 提取 prompt..."
    claude --print "$(cat <<EOF
读取 $CONFIG 和 ${OUTPUT_DIR}/analysis-report.md。
根据 doc_type=$DOC_TYPE 的内置骨架模板：
1. 在 ${OUTPUT_DIR}/docs/ 下生成带 TODO 标记的 .md 骨架文件
2. 生成 ${OUTPUT_DIR}/mkdocs.yml
3. 生成 ${OUTPUT_DIR}/fill-order.md（三批执行顺序）
4. 在 ${OUTPUT_DIR}/prompts/ 下为每个页面生成提取 prompt
骨架中每个 TODO 必须标明：从哪个源文档、提取什么、转化为什么形式。
EOF
    )" --allowedTools "Read,Write" 2>/dev/null
    echo "  ✅ 骨架文件: ${OUTPUT_DIR}/docs/"
    echo "  ✅ 提取 prompt: ${OUTPUT_DIR}/prompts/"
    echo "  ✅ 填充顺序: ${OUTPUT_DIR}/fill-order.md"
}

# === Step 3: 逐页填充 ===
run_fill() {
    echo "📝 Step 3: 逐页填充..."
    COMMON_RULES="${OUTPUT_DIR}/prompts/00-common-rules.md"

    # 按 fill-order.md 中的顺序执行
    for prompt_file in "${OUTPUT_DIR}"/prompts/[0-9]*.md; do
        [ "$prompt_file" = "$COMMON_RULES" ] && continue
        page_name=$(basename "$prompt_file" .md | sed 's/^[0-9]*-//')
        echo "  📄 填充: $page_name"

        claude --print "$(cat <<EOF
读取通用指令: $COMMON_RULES
读取本页任务: $prompt_file
按任务中指定的源文档和目标文件执行填充。
保留原有 Markdown 结构，只替换 TODO 标记处的内容。
源文档中找不到的信息标记为 [待确认]。
完成后覆盖写回目标文件。
EOF
        )" --allowedTools "Read,Write" 2>/dev/null
    done
    echo "  ✅ 全部页面填充完成"
}

# === Step 4: 自检 + 构建 ===
run_qa() {
    echo "🔍 Step 4: 自检..."
    claude --print "$(cat <<EOF
扫描 ${OUTPUT_DIR}/docs/ 下所有 .md 文件，执行以下检查：
1. 列出所有 [待确认] 标记（文件:行号:上下文）
2. 验证页面间链接目标文件存在
3. 检查术语一致性（同一概念不同页面是否用词一致）
4. 统计截图占位标记数量和位置
5. 检查同一数值在不同页面是否一致
输出自检报告到 ${OUTPUT_DIR}/qa-report.md。
EOF
    )" --allowedTools "Read,Write" 2>/dev/null
    echo "  ✅ 自检报告: ${OUTPUT_DIR}/qa-report.md"

    # 构建（如果是 mkdocs 格式）
    if grep -q 'output_format: mkdocs' "$CONFIG"; then
        echo "🔨 构建 MkDocs 站点..."
        cd "$OUTPUT_DIR" && mkdocs build --strict 2>&1 | tail -5
        echo "  ✅ 站点输出: ${OUTPUT_DIR}/site/"
    fi
}

# === 执行 ===
case "$STEP" in
    all)      run_analyze && run_skeleton && run_fill && run_qa ;;
    analyze)  run_analyze ;;
    skeleton) run_skeleton ;;
    fill)     run_fill ;;
    qa)       run_qa ;;
    *)        echo "❌ Unknown step: $STEP (use: all|analyze|skeleton|fill|qa)"; exit 1 ;;
esac

echo ""
echo "🎉 Done!"
```

---

## 7. 使用方式

### 全自动（一键执行）

```bash
# 1. 创建配置文件
cp doc-gen-agent/templates/doc-gen.yml ./doc-gen.yml
# 编辑 doc-gen.yml，填入项目实际的源文档路径

# 2. 一键执行全流程
./doc-gen-agent/doc-gen.sh ./doc-gen.yml all

# 3. 人工 review
#    - 查看 qa-report.md 中的 [待确认] 项
#    - 补充截图
#    - 最终确认
```

### 分步执行（推荐首次使用）

```bash
# Step 1: 看看源文档分析得对不对
./doc-gen-agent/doc-gen.sh ./doc-gen.yml analyze
cat docs/user-guide/analysis-report.md

# Step 2: 看看骨架结构合不合适
./doc-gen-agent/doc-gen.sh ./doc-gen.yml skeleton
# review 骨架 .md 文件和 fill-order.md

# Step 3: 逐页填充
./doc-gen-agent/doc-gen.sh ./doc-gen.yml fill

# Step 4: 自检 + 构建
./doc-gen-agent/doc-gen.sh ./doc-gen.yml qa
```

### 在 Claude Code 中手动调用（灵活模式）

```
读取 doc-gen.yml，按 doc-gen-agent 的 Step 2 要求，
为 admin-guide 类型生成骨架和提取 prompt。
```

---

## 8. 目录结构（放入 MIMIR-BO）

```
mimir-bo/
├── runprompt-agent/
├── review-agent/
├── convention-extraction/
├── doc-gen-agent/              ← 新增
│   ├── README.md               ← 使用说明
│   ├── doc-gen.sh              ← Runner 脚本
│   ├── system-prompt.md        ← Agent 主 Prompt
│   ├── templates/
│   │   ├── doc-gen.yml         ← 配置文件模板
│   │   ├── user-guide.yml      ← user-guide 骨架模板
│   │   ├── admin-guide.yml     ← admin-guide 骨架模板
│   │   └── common-rules.md     ← 通用写作指令模板
│   └── DESIGN.md               ← 本设计文档
└── dashboard/
```

---

## 9. Admin Guide 测试计划

用 doc-gen-agent 生成 admin guide 作为首次测试：

### 配置文件

```yaml
doc_type: admin-guide
audience: admin
language: zh
output_format: mkdocs

source_docs:
  prd: docs/design/prd.md
  api_design: docs/design/api-design.md
  database_design: docs/design/database-design.md
  state_machines: docs/design/state-machines.md
  business_rules: docs/design/business-rules.md
  security_arch: docs/design/security-architecture.md

output_dir: docs/admin-guide
```

### 预期骨架差异（vs user-guide）

| 维度 | User Guide | Admin Guide |
|------|-----------|-------------|
| 首页重点 | 平台功能概览 | 管理职责概览 |
| 指南内容 | 创建/训练/试听/管理模型 | 用户管理/审计日志/系统配置/监控 |
| 参考内容 | 基本权限、配额 | 完整权限矩阵、管理API参考 |
| 术语级别 | 禁止技术术语 | 允许管理概念 |
| FAQ 来源 | 终端用户常见操作问题 | 管理员运维场景问题 |

### 验收标准

1. ✅ 骨架结构正确反映 admin-guide 模板（不是 user-guide 的复制品）
2. ✅ 填充内容聚焦管理员视角（用户管理、审计、权限分配）
3. ✅ 术语级别正确（允许"角色"、"审计日志"，禁止"SQLAlchemy"、"JWT"）
4. ✅ 自检报告无断链
5. ✅ mkdocs build 成功
6. ✅ [待确认] 数量合理（缺失的确实是源文档未覆盖的内容）

---

## 10. 未来扩展点

- **骨架模板库扩展**：api-doc、ops-manual、release-notes 等模板
- **增量更新模式**：源文档变更后，只重新填充受影响的页面（而非全部重跑）
- **多语言支持**：bilingual 模式下同时生成中英文版本
- **截图自动化**：集成 Playwright 自动截取 UI 截图（需要前端运行环境）
- **与 review-agent 联动**：代码变更后自动检测文档是否需要同步更新
