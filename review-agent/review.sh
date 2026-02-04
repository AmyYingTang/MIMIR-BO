#!/bin/bash
# review.sh — Independent Code Review Agent
# 
# Runs an independent code review by comparing design documents against
# actual implementation. Uses Claude Code CLI in non-interactive mode.
#
# Usage:
#   ./review.sh <module_name> [project_dir] [docs_dir] [scope_hint]
#
# Examples:
#   ./review.sh auth
#   ./review.sh training ~/voice-platform ~/voice-platform/docs "backend/app/api/v1/tasks.py backend/app/services/task_service.py frontend/src/views/training/"
#   ./review.sh auth ~/my-project ~/my-project/docs ""
#
# Arguments:
#   module_name  - Name of the module to review (e.g., "auth", "training")
#   project_dir  - Project root directory (default: current directory)
#   docs_dir     - Design documents directory (default: <project_dir>/docs)
#   scope_hint   - Space-separated list of files/dirs changed in this module
#                  (helps reviewer focus; leave empty to scan everything)

set -euo pipefail

# ─── Arguments ───
MODULE=${1:?"Usage: review.sh <module_name> [project_dir] [docs_dir] [scope_hint]"}
PROJECT_DIR=${2:-$(pwd)}
DOCS_DIR=${3:-"${PROJECT_DIR}/docs"}
SCOPE_HINT=${4:-"(not specified — reviewer will scan based on module name)"}

# ─── Resolve paths ───
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROMPT_TEMPLATE="${SCRIPT_DIR}/review-prompt.md"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"

if [ ! -f "$PROMPT_TEMPLATE" ]; then
    echo "❌ Prompt template not found: $PROMPT_TEMPLATE"
    exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
    echo "❌ Project directory not found: $PROJECT_DIR"
    exit 1
fi

# ─── Build prompt ───
PROMPT=$(cat "$PROMPT_TEMPLATE" \
    | sed "s|{{module_name}}|${MODULE}|g" \
    | sed "s|{{project_dir}}|${PROJECT_DIR}|g" \
    | sed "s|{{docs_dir}}|${DOCS_DIR}|g" \
    | sed "s|{{scope_hint}}|${SCOPE_HINT}|g"
)

# ─── Info ───
echo "╔══════════════════════════════════════════════════╗"
echo "║         MIMIR-BO Review Agent                    ║"
echo "╠══════════════════════════════════════════════════╣"
echo "║  Module:      ${MODULE}"
echo "║  Project:     ${PROJECT_DIR}"
echo "║  Docs:        ${DOCS_DIR}"
echo "║  Scope:       ${SCOPE_HINT}"
echo "║  Report:      ${PROJECT_DIR}/review-report-${MODULE}.md"
echo "╚══════════════════════════════════════════════════╝"
echo ""
echo "🔍 Starting independent review..."
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
        print(f'📊 Review complete. Cost: \${ e.get(\"cost_usd\", \"?\") }')
except:
    pass
" 2>/dev/null; then
        :  # python handled it
    else
        # Non-JSON line, show as-is if non-empty
        [ -n "$line" ] && echo "$line"
    fi
done

REPORT="${PROJECT_DIR}/review-report-${MODULE}.md"
echo ""
if [ -f "$REPORT" ]; then
    echo "✅ Review report generated: $REPORT"
    echo ""
    # Show summary (first 20 lines)
    echo "─── Report Summary ───"
    head -20 "$REPORT"
    echo "..."
    echo "─── End Summary ───"
else
    echo "⚠️ Review report not found at expected path: $REPORT"
    echo "   The reviewer may have written it to a different location."
    echo "   Check the output above for details."
fi
