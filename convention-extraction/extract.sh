#!/bin/bash
# extract.sh — Convention Extraction Agent
# 
# Scans existing codebase after a module completion and extracts
# implicit conventions into a structured snapshot file.
# The snapshot feeds into the next module's prompt generation.
#
# Usage:
#   ./extract.sh <module_name> [project_dir] [output_path] [project_name]
#
# Examples:
#   ./extract.sh auth
#   ./extract.sh auth ~/voice-platform
#   ./extract.sh training ~/voice-platform ~/voice-platform/docs/project-conventions.md "Voice Platform"
#
# Arguments:
#   module_name   - Name of the module just completed (e.g., "auth", "training")
#   project_dir   - Project root directory (default: current directory)
#   output_path   - Where to write the snapshot (default: <project_dir>/docs/project-conventions.md)
#   project_name  - Human-readable project name (default: directory basename)

set -euo pipefail

# ─── Arguments ───
MODULE=${1:?"Usage: extract.sh <module_name> [project_dir] [output_path] [project_name]"}
PROJECT_DIR=${2:-$(pwd)}
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
OUTPUT_PATH=${3:-"${PROJECT_DIR}/docs/project-conventions.md"}
PROJECT_NAME=${4:-$(basename "$PROJECT_DIR")}

# ─── Resolve paths ───
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_TEMPLATE="${SCRIPT_DIR}/extraction-prompt.md"

if [ ! -f "$PROMPT_TEMPLATE" ]; then
    echo "❌ Prompt template not found: $PROMPT_TEMPLATE"
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ Project directory not found: $PROJECT_DIR"
    exit 1
fi

# ─── Determine snapshot version ───
EXISTING_SNAPSHOT="(none — creating initial snapshot)"
SNAPSHOT_VERSION="v1"

if [ -f "$OUTPUT_PATH" ]; then
    EXISTING_SNAPSHOT="$OUTPUT_PATH"
    # Try to extract current version number and increment
    CURRENT_VER=$(grep -oP 'Snapshot version.*?v\K\d+' "$OUTPUT_PATH" 2>/dev/null || echo "0")
    SNAPSHOT_VERSION="v$((CURRENT_VER + 1))"
    echo "📋 Found existing snapshot (v${CURRENT_VER}), will update to ${SNAPSHOT_VERSION}"
fi

# ─── Ensure output directory exists ───
OUTPUT_DIR=$(dirname "$OUTPUT_PATH")
mkdir -p "$OUTPUT_DIR"

# ─── Build prompt ───
PROMPT=$(cat "$PROMPT_TEMPLATE" \
    | sed "s|{{module_name}}|${MODULE}|g" \
    | sed "s|{{project_dir}}|${PROJECT_DIR}|g" \
    | sed "s|{{project_name}}|${PROJECT_NAME}|g" \
    | sed "s|{{output_path}}|${OUTPUT_PATH}|g" \
    | sed "s|{{existing_snapshot}}|${EXISTING_SNAPSHOT}|g" \
    | sed "s|{{snapshot_version}}|${SNAPSHOT_VERSION}|g"
)

# ─── Info ───
echo "╔══════════════════════════════════════════════════╗"
echo "║      MIMIR-BO Convention Extraction              ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  Module:      ${MODULE}"
echo "║  Project:     ${PROJECT_DIR}"
echo "║  Output:      ${OUTPUT_PATH}"
echo "║  Version:     ${SNAPSHOT_VERSION}"
echo "║  Existing:    ${EXISTING_SNAPSHOT}"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "🔍 Scanning codebase for conventions..."
echo ""

# ─── Execute ───
claude -p "$PROMPT" \
    --verbose \
    --output-format stream-json \
    --dangerously-skip-permissions \
    2>&1 | while IFS= read -r line; do
    
    # Try to parse as JSON for structured display
    if echo "$line" | python3 -c "
import sys, json
try:
    e = json.load(sys.stdin)
    t = e.get('type','')
    if t == 'assistant' and 'content' in e:
        for block in e['content']:
            if block.get('type') == 'text':
                text = block['text'][:200]
                print(f'💬 {text}')
            elif block.get('type') == 'tool_use':
                name = block.get('name','')
                inp = str(block.get('input',{}))[:100]
                print(f'🔧 {name}: {inp}')
    elif t == 'result':
        print(f'📊 Extraction complete. Cost: \${ e.get(\"cost_usd\", \"?\") }')
except:
    pass
" 2>/dev/null; then
        :  # python handled it
    else
        # Non-JSON line, show as-is if non-empty
        [ -n "$line" ] && echo "$line"
    fi
done

echo ""
if [ -f "$OUTPUT_PATH" ]; then
    echo "✅ Convention snapshot generated: $OUTPUT_PATH"
    echo ""
    # Show summary (first 15 lines)
    echo "─── Snapshot Header ───"
    head -15 "$OUTPUT_PATH"
    echo "..."
    echo "─── End Header ───"
    echo ""
    # Show line count
    LINES=$(wc -l < "$OUTPUT_PATH")
    echo "📏 Snapshot size: ${LINES} lines"
    if [ "$LINES" -gt 200 ]; then
        echo "⚠️  Warning: Snapshot exceeds 200-line target. Consider trimming details."
    else
        echo "✅ Within 200-line target."
    fi
else
    echo "⚠️ Convention snapshot not found at expected path: $OUTPUT_PATH"
    echo "   The extractor may have written it to a different location."
    echo "   Check the output above for details."
fi
