# Doc-Gen Agent

> MIMIR-BO 文档生成 Agent — 从设计文档自动生成用户文档

## 它做什么

读取项目的设计文档（PRD、API 设计、状态机、业务规则等），自动生成面向特定读者的用户文档站点。

```
设计文档 → 分析 → 骨架 → 逐页填充 → 自检 → 构建站点
```

## 快速开始

```bash
# 1. 准备配置文件
cp doc-gen-agent/templates/doc-gen.yml ./doc-gen.yml
# 编辑 doc-gen.yml，填入实际的源文档路径

# 2. 一键执行
./doc-gen-agent/doc-gen.sh ./doc-gen.yml all ~/your-project

# 3. 查看结果
cat docs/user-guide/qa-report.md    # 自检报告
cd docs/user-guide && mkdocs serve  # 预览站点
```

## 分步执行

```bash
# Step 1: 分析源文档覆盖情况
./doc-gen-agent/doc-gen.sh ./doc-gen.yml analyze ~/your-project

# Step 2: 生成骨架 + 提取 prompt（建议 review 后再继续）
./doc-gen-agent/doc-gen.sh ./doc-gen.yml skeleton ~/your-project

# Step 3: 逐页填充
./doc-gen-agent/doc-gen.sh ./doc-gen.yml fill ~/your-project

# Step 4: 自检 + 构建
./doc-gen-agent/doc-gen.sh ./doc-gen.yml qa ~/your-project
```

## 支持的文档类型

| doc_type | 说明 | 内置模板 |
|----------|------|---------|
| `user-guide` | 终端用户操作指南 | ✅ `templates/user-guide.yml` |
| `admin-guide` | 管理员操作指南 | ✅ `templates/admin-guide.yml` |
| `api-doc` | API 参考文档 | ⬜ 计划中 |
| `ops-manual` | 运维手册 | ⬜ 计划中 |

## 配置文件说明

```yaml
doc_type: user-guide          # 文档类型
audience: end-user            # 目标读者（决定术语边界）
language: zh                  # 输出语言
output_format: mkdocs         # 输出格式

source_docs:                  # 源文档路径（相对于项目根目录）
  prd: docs/design/prd.md
  api_design: docs/design/api-design.md
  # ...

output_dir: docs/user-guide   # 输出目录

writing_rules:
  tone: friendly-professional # 语气
  no_technical_terms: true    # 是否禁止技术术语
  unknown_value_marker: '[待确认]'  # 缺失信息标记
```

## 输出结构

```
{output_dir}/
├── analysis-report.md    # 源文档分析报告
├── fill-order.md         # 填充依赖顺序
├── qa-report.md          # 自检报告
├── mkdocs.yml            # 站点配置
├── prompts/              # 提取 prompt（中间产物）
│   ├── 00-common-rules.md
│   ├── 01-limits.md
│   └── ...
├── docs/                 # 文档内容
│   ├── index.md
│   ├── quickstart.md
│   ├── guides/
│   ├── reference/
│   └── faq.md
└── site/                 # 构建产物（mkdocs build 生成）
```

## 在 BO 工作流中的位置

```
模块全部完成 → review-agent → 人工验收
    → doc-gen-agent → 人工 review → mkdocs build → SHIP
```

## 前置依赖

- `claude` CLI（`npm install -g @anthropic-ai/claude-code`）
- Python 3（用于解析 stream-json 输出）
- `mkdocs` + `mkdocs-material`（仅 Step 4 构建需要，可选）

## 文件说明

| 文件 | 用途 |
|------|------|
| `doc-gen.sh` | 主执行脚本 |
| `system-prompt.md` | Agent 行为准则（被 Step 2 引用） |
| `templates/doc-gen.yml` | 配置文件模板 |
| `templates/user-guide.yml` | User Guide 骨架模板 |
| `templates/admin-guide.yml` | Admin Guide 骨架模板 |
| `templates/common-rules.md` | 通用写作指令模板 |
| `DESIGN.md` | 设计文档（详细设计决策和原理） |

## 预估费用

每次完整运行（all）约 4 次 Claude API 调用 + N 次填充调用（N = 页面数）。
以 user-guide（10 页）为例，预估总费用约 $5-15。

## 版本

v0.1 — 初始版本
