#!/bin/bash
# doc-gen.sh — MIMIR-BO Doc-Gen Agent Runner
# 从设计文档自动生成用户文档
#
# 用法:
#   ./doc-gen.sh <config-file> [step] [project-dir]
#
#   config-file : doc-gen.yml 配置文件路径
#   step        : all | analyze | skeleton | fill | qa | build  (默认: all)
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

# auto_build: true 时跳过中间暂停，分析→骨架→填充→自检→构建一气呵成
AUTO_BUILD=$(get_yaml "auto_build")
[ -z "$AUTO_BUILD" ] && AUTO_BUILD="false"

# 确保输出目录存在
OUTPUT_PATH="${PROJECT_DIR}/${OUTPUT_DIR}"
mkdir -p "${OUTPUT_PATH}/docs" "${OUTPUT_PATH}/prompts"

# ─── 模糊文件匹配 ───
# 如果精确路径不存在，尝试模糊匹配（如 prd 匹配 prd-v1.2.md）
resolve_source_path() {
    local configured_path="$1"
    local full_path="${PROJECT_DIR}/${configured_path}"

    # 精确匹配
    if [ -f "$full_path" ]; then
        echo "$full_path"
        return 0
    fi

    # 模糊匹配：在同目录下找文件名中包含关键词的文件
    local dir=$(dirname "$full_path")
    local base=$(basename "$configured_path" .md)
    if [ -d "$dir" ]; then
        local match=$(find "$dir" -maxdepth 1 -name "*${base}*" -type f 2>/dev/null | head -1)
        if [ -n "$match" ]; then
            echo "$match"
            return 0
        fi
    fi

    # 未找到
    echo ""
    return 1
}

# ─── 构建源文档清单（带模糊匹配）───
build_source_list() {
    local found=0
    local missing=0
    while IFS='=' read -r key val; do
        [ -z "$key" ] && continue
        local resolved=$(resolve_source_path "$val")
        if [ -n "$resolved" ]; then
            local configured="${PROJECT_DIR}/${val}"
            if [ "$resolved" = "$configured" ]; then
                echo "  ✅ ${key}: ${resolved}"
            else
                echo "  ✅ ${key}: ${resolved} (模糊匹配)"
            fi
            found=$((found + 1))
        else
            echo "  ⚠️  ${key}: ${PROJECT_DIR}/${val} (未找到，将跳过)"
            missing=$((missing + 1))
        fi
    done <<< "$SOURCE_DOCS"
    echo ""
    echo "  找到 ${found} 个源文档，${missing} 个未找到"
    if [ $missing -gt 0 ]; then
        echo "  💡 缺失的源文档不会阻断执行，相关内容将标记为 ${UNKNOWN_MARKER}"
    fi
}

# ─── 构建源文档路径引用（供 prompt 使用）───
build_source_refs() {
    local refs=""
    while IFS='=' read -r key val; do
        [ -z "$key" ] && continue
        local resolved=$(resolve_source_path "$val")
        if [ -n "$resolved" ]; then
            refs="${refs}
- ${key}: ${resolved}"
        else
            refs="${refs}
- ${key}: (未提供，相关内容标记为 ${UNKNOWN_MARKER})"
        fi
    done <<< "$SOURCE_DOCS"
    echo "$refs"
}

SOURCE_REFS=$(build_source_refs)

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
if [ "$AUTO_BUILD" = "true" ]; then
    echo "  自动构建 : ✅ 跳过中间暂停，直接输出站点"
fi
echo ""
echo "源文档:"
build_source_list
echo ""

# ─── Claude 调用封装 ───
# 对齐 review.sh / extract.sh 的调用方式：直接传 prompt 参数
run_claude() {
    local prompt="$1"
    local label="$2"

    claude -p "$prompt" \
        --verbose \
        --output-format stream-json \
        --dangerously-skip-permissions \
        2>&1 | while IFS= read -r line; do

        # 尝试解析 JSON
        if echo "$line" | python3 -c "
import sys, json
try:
    e = json.load(sys.stdin)
    t = e.get('type','')
    if t == 'assistant' and 'content' in e:
        for block in e['content']:
            if block.get('type') == 'text':
                text = block['text'][:300]
                print(f'  💬 {text}')
            elif block.get('type') == 'tool_use':
                name = block.get('name','')
                inp = str(block.get('input',{}))[:150]
                print(f'  🔧 {name}: {inp}')
    elif t == 'result':
        cost = e.get('cost_usd', '?')
        duration = e.get('duration_ms', 0)
        print(f'  📊 {label} 完成. 💰 \${cost} | ⏱ {duration/1000:.1f}s')
except:
    pass
" 2>/dev/null; then
            :
        else
            [ -n "$line" ] && echo "  $line"
        fi
    done
}

# ─── Step 1: 分析源文档 ───
run_analyze() {
    echo "🔍 Step 1: 分析源文档..."
    echo ""

    local system_prompt_ref=""
    if [ -f "${SCRIPT_DIR}/system-prompt.md" ]; then
        system_prompt_ref="请先读取 ${SCRIPT_DIR}/system-prompt.md 作为你的行为准则。"
    fi

    local prompt="${system_prompt_ref}

你是 MIMIR-BO doc-gen-agent，正在执行 Step 1：源文档分析。

## 任务
扫描以下源文档，生成覆盖分析报告。

源文档清单：
${SOURCE_REFS}

## 配置
- 文档类型: ${DOC_TYPE}
- 目标读者: ${AUDIENCE}

## 要求
1. 读取每个存在的源文档，生成摘要：文件名 | 主要覆盖内容 | 可提取的用户文档条目
2. 标记 ${DOC_TYPE} 所需但源文档未覆盖的领域为 ⚠️ 缺失
3. 缺失的源文档也列出，标注为未提供
4. 将报告输出到 ${OUTPUT_PATH}/analysis-report.md

## 输出格式
Markdown 表格 + 缺失领域列表"

    run_claude "$prompt" "分析"

    echo ""
    if [ -f "${OUTPUT_PATH}/analysis-report.md" ]; then
        echo "  ✅ 分析报告: ${OUTPUT_PATH}/analysis-report.md"
    else
        echo "  ⚠️  分析报告未生成，请检查上方输出"
    fi
    echo ""
}

# ─── Step 2: 生成骨架 + Prompt ───
run_skeleton() {
    echo "🦴 Step 2: 生成骨架 + 提取 prompt..."
    echo ""

    local template_file="${SCRIPT_DIR}/templates/${DOC_TYPE}.yml"
    local template_ref=""
    if [ -f "$template_file" ]; then
        template_ref="请先读取骨架模板文件 ${template_file}，按其中定义的页面结构、源文档映射和提取策略来生成。"
    else
        template_ref="无预定义模板，请根据 doc_type=${DOC_TYPE} 和 audience=${AUDIENCE} 自行推导合理的文档结构。"
    fi

    local system_prompt_ref=""
    if [ -f "${SCRIPT_DIR}/system-prompt.md" ]; then
        system_prompt_ref="请先读取 ${SCRIPT_DIR}/system-prompt.md 作为你的行为准则。"
    fi

    local prompt="${system_prompt_ref}

你是 MIMIR-BO doc-gen-agent，正在执行 Step 2：生成骨架和提取 prompt。

${template_ref}

## 输入
- 分析报告: ${OUTPUT_PATH}/analysis-report.md（请先读取）

源文档清单：
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

### 2. 站点配置
$(if [ "$OUTPUT_FORMAT" = "mkdocs" ]; then
echo "在 ${OUTPUT_PATH}/ 下生成 mkdocs.yml 配置，使用 Material 主题，支持中文搜索。"
elif [ "$OUTPUT_FORMAT" = "single-html" ]; then
echo "不需要生成 mkdocs.yml。输出格式为单文件 HTML，构建脚本会自动读取 fill-order.md 来确定页面顺序和导航结构。"
fi)

### 3. 填充顺序
在 ${OUTPUT_PATH}/fill-order.md 中定义三批执行顺序：
- 第1批：纯数据提取页（可并行）
- 第2批：操作指南页（建议按功能流程顺序）
- 第3批：综合页（必须串行，依赖前两批结果）

### 4. 提取 Prompt
在 ${OUTPUT_PATH}/prompts/ 下为每个页面生成独立的提取 prompt：
- 00-common-rules.md: 通用写作指令
- 01-xxx.md ~ NN-xxx.md: 每页的具体提取任务

每个提取 prompt 必须包含：
- 需要读取的源文档路径（使用绝对路径）
- 目标骨架文件路径（使用绝对路径）
- 转化规则和该页面特有的约束"

    run_claude "$prompt" "骨架生成"

    echo ""
    [ -d "${OUTPUT_PATH}/docs" ] && echo "  ✅ 骨架文件: ${OUTPUT_PATH}/docs/"
    [ -d "${OUTPUT_PATH}/prompts" ] && echo "  ✅ 提取 prompt: ${OUTPUT_PATH}/prompts/"
    [ -f "${OUTPUT_PATH}/fill-order.md" ] && echo "  ✅ 填充顺序: ${OUTPUT_PATH}/fill-order.md"
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

    local total=$(ls "${OUTPUT_PATH}"/prompts/[0-9]*.md 2>/dev/null | grep -v "00-common-rules.md" | wc -l | tr -d ' ')
    if [ "$total" = "0" ]; then
        echo "  ❌ 未找到提取 prompt 文件"
        exit 1
    fi

    local count=0
    for prompt_file in "${OUTPUT_PATH}"/prompts/[0-9]*.md; do
        [ "$prompt_file" = "$common_rules" ] && continue
        count=$((count + 1))
        local page_name=$(basename "$prompt_file" .md | sed 's/^[0-9]*-//')
        echo "  [$count/$total] 📄 填充: $page_name"

        local prompt="你是 MIMIR-BO doc-gen-agent，正在执行 Step 3：内容填充。

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
- 填充完成后覆盖写回目标文件"

        run_claude "$prompt" "$page_name"

    done

    echo ""
    echo "  ✅ 全部 $total 页填充完成"
    echo ""
}

# ─── Step 4: 自检 + 构建 ───
run_qa() {
    echo "🔍 Step 4: 自检..."
    echo ""

    local prompt="你是 MIMIR-BO doc-gen-agent，正在执行 Step 4：质量自检。

## 任务
扫描 ${OUTPUT_PATH}/docs/ 下所有 .md 文件，执行以下检查：

1. **${UNKNOWN_MARKER} 扫描**: 列出所有仍包含 ${UNKNOWN_MARKER} 的位置（文件:行号:上下文）
2. **链接检查**: 验证所有 Markdown 页面间链接的目标文件存在
3. **术语一致性**: 检查同一概念在不同页面是否使用了不同名称
4. **截图占位统计**: 列出所有 <!-- TODO: 截图 --> 的位置
5. **数值一致性**: 检查同一数值（如配额上限）在不同页面是否一致

## 输出
将自检报告输出到 ${OUTPUT_PATH}/qa-report.md，包含：
- 📊 总览表
- 各检查项的详细结果
- 每项用 ✅ 通过 或 ⚠️ 有问题 标记"

    run_claude "$prompt" "自检"

    echo ""
    if [ -f "${OUTPUT_PATH}/qa-report.md" ]; then
        echo "  ✅ 自检报告: ${OUTPUT_PATH}/qa-report.md"
    else
        echo "  ⚠️  自检报告未生成"
    fi

    # 构建
    if [ "$OUTPUT_FORMAT" = "mkdocs" ]; then
        echo ""
        echo "🔨 构建 MkDocs 站点..."
        if command -v mkdocs >/dev/null 2>&1; then
            (cd "$OUTPUT_PATH" && mkdocs build 2>&1 | tail -5)
            echo "  ✅ 站点输出: ${OUTPUT_PATH}/site/"
        else
            echo "  ⚠️  mkdocs 未安装，跳过构建"
            echo "  安装: pipx install mkdocs==1.6.1 && pipx inject mkdocs mkdocs-material"
        fi
    elif [ "$OUTPUT_FORMAT" = "single-html" ]; then
        echo ""
        echo "🔨 构建单文件 HTML..."
        local doc_title="${DOC_TYPE}"
        # 从配置文件中获取实例名（如果有的话）
        local instance_name=$(get_yaml "title")
        [ -n "$instance_name" ] && doc_title="$instance_name"
        python3 "${SCRIPT_DIR}/single-html-build.py" "$OUTPUT_PATH" "$doc_title"
    fi

    echo ""
}

# ─── 单独构建（不含自检）───
run_build() {
    echo "🔨 构建文档..."
    echo ""

    if [ "$OUTPUT_FORMAT" = "mkdocs" ]; then
        if ! command -v mkdocs >/dev/null 2>&1; then
            echo "  ❌ mkdocs 未安装"
            echo "  安装: pipx install mkdocs==1.6.1 && pipx inject mkdocs mkdocs-material"
            exit 1
        fi
        if [ ! -f "${OUTPUT_PATH}/mkdocs.yml" ]; then
            echo "  ❌ mkdocs.yml 不存在: ${OUTPUT_PATH}/mkdocs.yml"
            echo "  请先运行 skeleton 步骤"
            exit 1
        fi
        (cd "$OUTPUT_PATH" && mkdocs build 2>&1 | tail -10)
        echo ""
        echo "  ✅ 站点输出: ${OUTPUT_PATH}/site/"
        echo "  💡 预览: cd ${OUTPUT_PATH} && mkdocs serve"

    elif [ "$OUTPUT_FORMAT" = "single-html" ]; then
        local doc_title="${DOC_TYPE}"
        local instance_name=$(get_yaml "title")
        [ -n "$instance_name" ] && doc_title="$instance_name"
        python3 "${SCRIPT_DIR}/single-html-build.py" "$OUTPUT_PATH" "$doc_title"
        echo "  💡 双击 HTML 文件即可在浏览器中查看"

    else
        echo "  ⚠️  未知的 output_format: ${OUTPUT_FORMAT}"
        echo "  支持: mkdocs | single-html"
    fi
    echo ""
}

# ─── 执行 ───
case "$STEP" in
    all)
        if [ "$AUTO_BUILD" = "true" ]; then
            # 自动模式：全程无暂停
            run_analyze
            echo "────────────────────────────────────"
            run_skeleton
            echo "────────────────────────────────────"
            run_fill
            echo "────────────────────────────────────"
            run_qa
        else
            # 交互模式：保留暂停点
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
        fi
        ;;
    analyze)  run_analyze ;;
    skeleton) run_skeleton ;;
    fill)     run_fill ;;
    qa)       run_qa ;;
    build)    run_build ;;
    *)
        echo "❌ 未知步骤: $STEP"
        echo "   可选: all | analyze | skeleton | fill | qa | build"
        exit 1
        ;;
esac

echo "════════════════════════════════════"
echo "🎉 Doc-Gen Agent 执行完成!"
echo "════════════════════════════════════"
