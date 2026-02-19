#!/bin/bash
# doc-gen.sh — MIMIR-BO Doc-Gen Agent Runner
# 从设计文档自动生成用户文档
#
# 用法:
#   ./doc-gen.sh <config-file> [step] [project-dir]
#
#   config-file : doc-gen.yml 配置文件路径
#   step        : all | analyze | skeleton | fill | qa  (默认: all)
#   project-dir : 项目根目录 (默认: 当前目录)
#
# 示例:
#   ./doc-gen.sh ./doc-gen.yml all ~/voice-platform
#   ./doc-gen.sh ./doc-gen.yml skeleton
#   ./doc-gen.sh ./doc-gen.yml fill ~/voice-platform

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CONFIG="${1:?用法: $0 <config-file> [step] [project-dir]}"
STEP="${2:-all}"
PROJECT_DIR="${3:-.}"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

# ─── 前置检查 ───
command -v claude >/dev/null 2>&1 || { echo "❌ claude CLI 未安装。请先安装: npm install -g @anthropic-ai/claude-code"; exit 1; }

if [ ! -f "$CONFIG" ]; then
    echo "❌ 配置文件不存在: $CONFIG"
    exit 1
fi

# ─── 解析配置 (简易 YAML 解析) ───
get_yaml() { grep "^${1}:" "$CONFIG" | sed "s/^${1}:[[:space:]]*//" | tr -d "'\""; }

DOC_TYPE=$(get_yaml "doc_type")
AUDIENCE=$(get_yaml "audience")
LANGUAGE=$(get_yaml "language")
OUTPUT_FORMAT=$(get_yaml "output_format")
OUTPUT_DIR=$(get_yaml "output_dir")

# 解析 source_docs (多行 YAML)
parse_source_docs() {
    local in_source=false
    local docs=""
    while IFS= read -r line; do
        if [[ "$line" =~ ^source_docs: ]]; then
            in_source=true
            continue
        fi
        if $in_source; then
            if [[ "$line" =~ ^[[:space:]]+[a-z_]+: ]]; then
                local key=$(echo "$line" | sed 's/^[[:space:]]*//' | cut -d: -f1)
                local val=$(echo "$line" | sed 's/^[^:]*:[[:space:]]*//' | tr -d "'\"")
                docs="${docs}${key}=${val}\n"
            elif [[ ! "$line" =~ ^[[:space:]] ]] && [ -n "$line" ]; then
                break
            fi
        fi
    done < "$CONFIG"
    echo -e "$docs"
}

SOURCE_DOCS=$(parse_source_docs)

# 解析 writing_rules
TONE=$(grep -A10 "^writing_rules:" "$CONFIG" | grep "tone:" | sed 's/.*tone:[[:space:]]*//' | tr -d "'\"" || echo "friendly-professional")
NO_TECH=$(grep -A10 "^writing_rules:" "$CONFIG" | grep "no_technical_terms:" | sed 's/.*no_technical_terms:[[:space:]]*//' || echo "true")
UNKNOWN_MARKER=$(grep -A10 "^writing_rules:" "$CONFIG" | grep "unknown_value_marker:" | sed 's/.*unknown_value_marker:[[:space:]]*//' | tr -d "'\"" || echo "[待确认]")

# 确保输出目录存在
OUTPUT_PATH="${PROJECT_DIR}/${OUTPUT_DIR}"
mkdir -p "${OUTPUT_PATH}/docs" "${OUTPUT_PATH}/prompts"

# ─── 打印信息 ───
echo "╔══════════════════════════════════════════╗"
echo "║     📄 MIMIR-BO Doc-Gen Agent            ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "  配置文件 : $CONFIG"
echo "  文档类型 : $DOC_TYPE"
echo "  目标读者 : $AUDIENCE"
echo "  输出语言 : $LANGUAGE"
echo "  输出格式 : $OUTPUT_FORMAT"
echo "  输出目录 : $OUTPUT_PATH"
echo "  项目目录 : $PROJECT_DIR"
echo "  执行步骤 : $STEP"
echo ""

# ─── 构建源文档清单 ───
build_source_list() {
    local list=""
    while IFS='=' read -r key val; do
        [ -z "$key" ] && continue
        local full_path="${PROJECT_DIR}/${val}"
        if [ -f "$full_path" ]; then
            list="${list}  ✅ ${key}: ${full_path}\n"
        else
            list="${list}  ❌ ${key}: ${full_path} (文件不存在)\n"
        fi
    done <<< "$SOURCE_DOCS"
    echo -e "$list"
}

echo "源文档:"
build_source_list
echo ""

# ─── 构建源文档内容块（供 prompt 引用）───
build_source_content_refs() {
    local refs=""
    while IFS='=' read -r key val; do
        [ -z "$key" ] && continue
        local full_path="${PROJECT_DIR}/${val}"
        if [ -f "$full_path" ]; then
            refs="${refs}\n源文档 ${key} 的路径: ${full_path}\n"
        fi
    done <<< "$SOURCE_DOCS"
    echo -e "$refs"
}

SOURCE_REFS=$(build_source_content_refs)

# ─── Step 1: 分析源文档 ───
run_analyze() {
    echo "🔍 Step 1: 分析源文档..."
    echo ""

    local prompt="$(cat <<PROMPT
你是 MIMIR-BO doc-gen-agent，正在执行 Step 1：源文档分析。

## 任务
扫描以下源文档，生成覆盖分析报告。
${SOURCE_REFS}

## 配置
- 文档类型: ${DOC_TYPE}
- 目标读者: ${AUDIENCE}

## 要求
1. 读取每个源文档，生成摘要：文件名 | 主要覆盖内容 | 可提取的用户文档条目
2. 标记 ${DOC_TYPE} 所需但源文档未覆盖的领域为 ⚠️ 缺失
3. 将报告输出到 ${OUTPUT_PATH}/analysis-report.md

## 输出格式
Markdown 表格 + 缺失领域列表
PROMPT
    )"

    echo "$prompt" | claude -p --allowedTools "Read,Write" --output-format stream-json \
        2>/dev/null | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'assistant' and 'content' in obj:
            for block in obj['content']:
                if block.get('type') == 'text':
                    print(block['text'], end='', flush=True)
        elif obj.get('type') == 'result':
            cost = obj.get('cost_usd', 0)
            duration = obj.get('duration_ms', 0)
            print(f'\n\n  💰 Cost: \${cost:.2f} | ⏱ Duration: {duration/1000:.1f}s')
    except json.JSONDecodeError:
        pass
" 2>/dev/null || echo "  ⚠️ 输出解析失败，请检查 ${OUTPUT_PATH}/analysis-report.md"

    echo ""
    echo "  ✅ 分析报告: ${OUTPUT_PATH}/analysis-report.md"
    echo ""
}

# ─── Step 2: 生成骨架 + Prompt ───
run_skeleton() {
    echo "🦴 Step 2: 生成骨架 + 提取 prompt..."
    echo ""

    # 读取骨架模板（如果存在）
    local template_file="${SCRIPT_DIR}/templates/${DOC_TYPE}.yml"
    local template_ref=""
    if [ -f "$template_file" ]; then
        template_ref="骨架模板文件: ${template_file}（请读取并遵循其结构定义）"
    else
        template_ref="无预定义模板，请根据 doc_type=${DOC_TYPE} 和 audience=${AUDIENCE} 自行推导合理的文档结构"
    fi

    # 读取系统 prompt
    local system_prompt_file="${SCRIPT_DIR}/system-prompt.md"
    local system_prompt_ref=""
    if [ -f "$system_prompt_file" ]; then
        system_prompt_ref="系统角色定义: ${system_prompt_file}（请先读取作为你的行为准则）"
    fi

    local prompt="$(cat <<PROMPT
你是 MIMIR-BO doc-gen-agent，正在执行 Step 2：生成骨架和提取 prompt。

${system_prompt_ref}

## 任务
根据分析报告和配置，生成文档骨架和填充用的提取 prompt。

## 输入
- 分析报告: ${OUTPUT_PATH}/analysis-report.md（请先读取）
- ${template_ref}
${SOURCE_REFS}

## 配置
- 文档类型: ${DOC_TYPE}
- 目标读者: ${AUDIENCE}
- 输出语言: ${LANGUAGE}
- 语气: ${TONE}
- 禁止技术术语: ${NO_TECH}
- 缺失信息标记: ${UNKNOWN_MARKER}

## 输出要求

### 1. 骨架 Markdown 文件
在 ${OUTPUT_PATH}/docs/ 下生成带 TODO 标记的 .md 文件。
每个 TODO 必须标明：从哪个源文档、提取什么内容、转化为什么形式。
保留截图占位标记: <!-- TODO: 截图 — 描述 -->

### 2. mkdocs.yml
在 ${OUTPUT_PATH}/ 下生成 mkdocs.yml 配置，使用 Material 主题，支持中文搜索。

### 3. 填充顺序
在 ${OUTPUT_PATH}/fill-order.md 中定义三批执行顺序：
- 第1批：纯数据提取页（可并行）
- 第2批：操作指南页（建议按功能流程顺序）
- 第3批：综合页（必须串行，依赖前两批结果）

### 4. 提取 Prompt
在 ${OUTPUT_PATH}/prompts/ 下为每个页面生成独立的提取 prompt：
- 00-common-rules.md: 通用写作指令（读者意识、术语禁止、格式要求）
- 01-xxx.md ~ NN-xxx.md: 每页的具体提取任务

每个提取 prompt 必须包含：
- 需要读取的源文档路径（使用绝对路径）
- 目标骨架文件路径
- 转化规则（技术术语→用户语言的映射）
- 该页面特有的约束
PROMPT
    )"

    echo "$prompt" | claude -p --allowedTools "Read,Write" --output-format stream-json \
        2>/dev/null | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'assistant' and 'content' in obj:
            for block in obj['content']:
                if block.get('type') == 'text':
                    print(block['text'], end='', flush=True)
        elif obj.get('type') == 'result':
            cost = obj.get('cost_usd', 0)
            duration = obj.get('duration_ms', 0)
            print(f'\n\n  💰 Cost: \${cost:.2f} | ⏱ Duration: {duration/1000:.1f}s')
    except json.JSONDecodeError:
        pass
" 2>/dev/null || echo "  ⚠️ 输出解析失败"

    echo ""
    echo "  ✅ 骨架文件: ${OUTPUT_PATH}/docs/"
    echo "  ✅ 提取 prompt: ${OUTPUT_PATH}/prompts/"
    echo "  ✅ 填充顺序: ${OUTPUT_PATH}/fill-order.md"
    echo ""
}

# ─── Step 3: 逐页填充 ───
run_fill() {
    echo "📝 Step 3: 逐页填充..."
    echo ""

    local common_rules="${OUTPUT_PATH}/prompts/00-common-rules.md"
    if [ ! -f "$common_rules" ]; then
        echo "  ❌ 通用指令文件不存在: $common_rules"
        echo "  请先运行 skeleton 步骤"
        exit 1
    fi

    # 按文件名排序逐个执行
    local count=0
    local total=$(ls "${OUTPUT_PATH}"/prompts/[0-9]*.md 2>/dev/null | grep -v "00-common-rules.md" | wc -l | tr -d ' ')

    for prompt_file in "${OUTPUT_PATH}"/prompts/[0-9]*.md; do
        [ "$prompt_file" = "$common_rules" ] && continue
        count=$((count + 1))
        local page_name=$(basename "$prompt_file" .md | sed 's/^[0-9]*-//')
        echo "  [$count/$total] 📄 填充: $page_name"

        local prompt="$(cat <<PROMPT
你是 MIMIR-BO doc-gen-agent，正在执行 Step 3：内容填充。

## 任务
按照提取 prompt 的要求，用源文档中的真实信息填充骨架页面。

## 输入
1. 通用写作指令: ${common_rules}（请先读取并严格遵循）
2. 本页提取任务: ${prompt_file}（请读取，按其中的要求执行）

## 核心规则
- 只使用源文档中明确存在的信息，不编造
- 找不到的数值标记为 ${UNKNOWN_MARKER}
- 保留 Markdown 原有结构
- 保留截图占位标记
- 填充完成后覆盖写回目标文件
PROMPT
        )"

        echo "$prompt" | claude -p --allowedTools "Read,Write" --output-format stream-json \
            2>/dev/null | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'result':
            cost = obj.get('cost_usd', 0)
            duration = obj.get('duration_ms', 0)
            print(f'         💰 \${cost:.2f} | ⏱ {duration/1000:.1f}s')
    except json.JSONDecodeError:
        pass
" 2>/dev/null || echo "         ⚠️ 填充可能未完成"

    done

    echo ""
    echo "  ✅ 全部 $total 页填充完成"
    echo ""
}

# ─── Step 4: 自检 + 构建 ───
run_qa() {
    echo "🔍 Step 4: 自检..."
    echo ""

    local prompt="$(cat <<PROMPT
你是 MIMIR-BO doc-gen-agent，正在执行 Step 4：质量自检。

## 任务
扫描 ${OUTPUT_PATH}/docs/ 下所有 .md 文件，执行以下检查：

1. **${UNKNOWN_MARKER} 扫描**: 列出所有仍包含 ${UNKNOWN_MARKER} 的位置（文件:行号:上下文）
2. **链接检查**: 验证所有 Markdown 页面间链接的目标文件存在
3. **术语一致性**: 检查同一概念在不同页面是否使用了不同名称
4. **截图占位统计**: 列出所有 <!-- TODO: 截图 --> 的位置
5. **数值一致性**: 检查同一数值（如配额上限）在不同页面是否一致

## 输出
将自检报告输出到 ${OUTPUT_PATH}/qa-report.md，包含：
- 📊 总览表（页面数、填充完成数、待确认数、断链数、截图占位数）
- 各检查项的详细结果
- 每项用 ✅ 通过 或 ⚠️ 有问题 标记
PROMPT
    )"

    echo "$prompt" | claude -p --allowedTools "Read,Write" --output-format stream-json \
        2>/dev/null | python3 -c "
import sys, json
for line in sys.stdin:
    line = line.strip()
    if not line: continue
    try:
        obj = json.loads(line)
        if obj.get('type') == 'assistant' and 'content' in obj:
            for block in obj['content']:
                if block.get('type') == 'text':
                    print(block['text'], end='', flush=True)
        elif obj.get('type') == 'result':
            cost = obj.get('cost_usd', 0)
            duration = obj.get('duration_ms', 0)
            print(f'\n\n  💰 Cost: \${cost:.2f} | ⏱ Duration: {duration/1000:.1f}s')
    except json.JSONDecodeError:
        pass
" 2>/dev/null || echo "  ⚠️ 自检可能未完成"

    echo ""
    echo "  ✅ 自检报告: ${OUTPUT_PATH}/qa-report.md"

    # 构建（如果是 mkdocs 格式）
    if [ "$OUTPUT_FORMAT" = "mkdocs" ]; then
        echo ""
        echo "🔨 构建 MkDocs 站点..."
        if command -v mkdocs >/dev/null 2>&1; then
            cd "$OUTPUT_PATH" && mkdocs build 2>&1 | tail -5
            echo "  ✅ 站点输出: ${OUTPUT_PATH}/site/"
        else
            echo "  ⚠️ mkdocs 未安装，跳过构建。请运行: pipx install mkdocs && pipx inject mkdocs mkdocs-material"
        fi
    fi

    echo ""
}

# ─── 执行 ───
case "$STEP" in
    all)
        run_analyze
        echo "────────────────────────────────────"
        run_skeleton
        echo "────────────────────────────────────"
        echo "⏸  骨架已生成，建议先 review 再继续填充。"
        read -p "   继续填充？(y/n) " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "────────────────────────────────────"
            run_fill
            echo "────────────────────────────────────"
            echo "⏸  内容填充完成。现在可以："
            echo "     - 补充 UI 截图到 ${OUTPUT_PATH}/docs/images/"
            echo "     - 人工审校填充内容"
            echo "     - 修改任何不满意的页面"
            echo ""
            read -p "   继续自检+构建？(y/n) " -n 1 -r
            echo ""
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                echo "────────────────────────────────────"
                run_qa
            else
                echo "   已暂停。后续执行: $0 $CONFIG qa $PROJECT_DIR"
            fi
        else
            echo "   已暂停。后续执行: $0 $CONFIG fill $PROJECT_DIR"
        fi
        ;;
    analyze)  run_analyze ;;
    skeleton) run_skeleton ;;
    fill)     run_fill ;;
    qa)       run_qa ;;
    *)
        echo "❌ 未知步骤: $STEP"
        echo "   可选: all | analyze | skeleton | fill | qa"
        exit 1
        ;;
esac

echo "════════════════════════════════════"
echo "🎉 Doc-Gen Agent 执行完成!"
echo "════════════════════════════════════"
