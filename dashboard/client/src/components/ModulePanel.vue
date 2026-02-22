<template>
  <div class="module-panel">
    <!-- Header -->
    <div class="module-header">
      <span class="module-id">{{ module.id }}</span>
      <span class="module-label">{{ module.label }}</span>
      <StatusDot :status="module.status" :size="8" />
    </div>

    <!-- Sub-step pipeline -->
    <div class="pipeline">
      <div v-for="(step, i) in computedSubSteps" :key="step.id" class="pipeline-segment">
        <div class="pipeline-node"
          :class="{ active: stepStatus(step.id) === 'active', current: activeSubStep === step.id, completed: stepStatus(step.id) === 'completed', pending: stepStatus(step.id) === 'pending' }"
          @click="activeSubStep = step.id">
          <span class="node-icon">{{ step.icon }}</span>
          <span class="node-label">{{ step.label }}</span>
          <span class="node-role" :class="step.role">{{ roleLabel(step.role) }}</span>
        </div>
        <span v-if="i < computedSubSteps.length - 1" class="pipeline-arrow" :class="{ done: stepStatus(step.id) === 'completed' }">
          {{ stepStatus(step.id) === 'completed' ? '─✓▶' : '──▶' }}
        </span>
      </div>
    </div>

    <!-- Content area -->
    <div class="module-content">
      <template v-if="activeSubStep === 'prompt' && module.status === 'active'">
        <div class="human-action-banner">
          <span class="banner-pulse">{{ t.waitingAction }}</span>
          <span class="banner-hint">{{ t.waitingActionHint }}</span>
        </div>
        <div class="prompt-card">
          <div class="prompt-header">
            <span class="prompt-filename">{{ module.id }}-prompt.md</span>
            <div class="prompt-actions">
              <button class="btn btn-secondary btn-sm">{{ t.edit }}</button>
              <button class="btn btn-danger btn-sm">{{ t.reject }}</button>
              <button class="btn btn-primary btn-sm" @click="approvePrompt">{{ t.approveRun }}</button>
            </div>
          </div>
          <pre class="prompt-body">{{ promptContent || t.loading }}</pre>
        </div>
      </template>
      <template v-else>
        <div class="empty-content">
          <span class="empty-icon">
            {{ module.status === 'completed' ? '✅' : module.status === 'pending' ? '⏳' : computedSubSteps.find(s => s.id === activeSubStep)?.icon || '📋' }}
          </span>
          <span class="empty-text">
            {{ module.status === 'completed' ? t.moduleCompleted(module.id, module.label) :
               module.status === 'pending' ? t.waitingPrevModule :
               `${computedSubSteps.find(s => s.id === activeSubStep)?.label || ''} — ${stepStatus(activeSubStep) === 'pending' ? t.waitingPrevStep : t.inProgress}` }}
          </span>
        </div>
      </template>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, watch } from 'vue'
import StatusDot from './StatusDot.vue'
import { useApi } from '../composables/useApi.js'
import { useI18n } from '../composables/useI18n.js'

const { t } = useI18n()
const props = defineProps({ module: Object, config: Object })
const emit = defineEmits(['stateChange'])
const api = useApi()
const activeSubStep = ref('prompt')
const promptContent = ref('')

const computedSubSteps = computed(() => [
  { id: 'prompt', label: t.value.promptConfirm, role: 'human', icon: '📋' },
  { id: 'execute', label: t.value.codeExec, role: 'ai', icon: '⚙️' },
  { id: 'test', label: t.value.autoTest, role: 'ai', icon: '🧪' },
  { id: 'review', label: t.value.review, role: 'human', icon: '🔍' },
  { id: 'fix', label: t.value.fixLoop, role: 'collab', icon: '🔧' },
])

const stepOrder = ['prompt', 'execute', 'test', 'review', 'fix']

function stepStatus(stepId) {
  if (props.module.status === 'completed') return 'completed'
  if (props.module.status === 'pending') return 'pending'
  const currentStep = props.module.sub_step?.replace('_review', '') || 'prompt'
  const ci = stepOrder.indexOf(currentStep), si = stepOrder.indexOf(stepId)
  if (si < ci) return 'completed'
  if (si === ci) return 'active'
  return 'pending'
}

function roleLabel(role) { return role === 'human' ? '🧑' : role === 'ai' ? '🤖' : '🤝' }

async function loadPrompt() {
  if (!props.config?.paths?.workspace) return
  const promptPath = `${props.config.paths.workspace}/prompts/${props.module.id}-prompt.md`
  try { const res = await api.readFile(promptPath); promptContent.value = res.content }
  catch (e) { promptContent.value = `# ${props.module.id} Prompt\n\n${t.value.promptNotGenerated}\n\nPath: ${promptPath}` }
}

function approvePrompt() { alert(t.value.promptApproved(props.module.id)) }

watch(() => props.module.id, loadPrompt, { immediate: true })
</script>

<style scoped>
.module-panel { display: flex; flex-direction: column; height: 100%; }
.module-header { padding: 14px 20px; border-bottom: 1.5px solid var(--border); display: flex; align-items: center; gap: 10px; flex-shrink: 0; background: var(--surface); }
.module-id { font-family: var(--mono); font-size: 14px; font-weight: 700; color: var(--accent); }
.module-label { font-size: 14px; font-weight: 600; }
.pipeline { padding: 12px 18px; border-bottom: 1px solid var(--border-light); display: flex; align-items: center; gap: 4px; flex-shrink: 0; overflow-x: auto; }
.pipeline-segment { display: flex; align-items: center; gap: 4px; }
.pipeline-node { display: flex; flex-direction: column; align-items: center; gap: 3px; padding: 7px 11px; border-radius: 8px; cursor: pointer; min-width: 68px; border: 1.5px solid transparent; transition: all 0.15s; }
.pipeline-node:hover { background: var(--surface-alt); }
.pipeline-node.current { background: var(--surface-alt); border-color: var(--border); }
.pipeline-node.active { background: var(--accent-bg); border-color: var(--accent-border); animation: glow 2s ease-in-out infinite; }
.pipeline-node.pending { opacity: 0.4; }
.node-icon { font-size: 14px; }
.node-label { font-size: 10px; font-weight: 700; }
.pipeline-node.active .node-label { color: var(--accent); }
.node-role { font-size: 10px; padding: 0 5px; border-radius: 3px; font-weight: 600; }
.node-role.human { background: var(--blue-bg); color: var(--blue); border: 1px solid var(--blue-border); }
.node-role.ai { background: #f5f3ff; color: var(--purple); border: 1px solid #ddd6fe; }
.node-role.collab { background: #fffbeb; color: #d97706; border: 1px solid #fde68a; }
.pipeline-arrow { color: var(--text-dim); font-size: 10px; font-family: var(--mono); font-weight: 700; }
.pipeline-arrow.done { color: var(--green); }
.module-content { flex: 1; overflow-y: auto; padding: 16px 20px; background: var(--bg); }
.human-action-banner { display: flex; align-items: center; gap: 8px; margin-bottom: 12px; }
.banner-pulse { display: inline-flex; align-items: center; gap: 6px; background: var(--blue-bg); color: var(--blue); border: 1.5px solid var(--blue-border); padding: 5px 12px; border-radius: 7px; font-size: 12px; font-weight: 700; animation: pulse 2s ease-in-out infinite; }
.banner-hint { font-size: 12px; color: var(--text-muted); }
.prompt-card { background: var(--surface); border: 1.5px solid var(--border); border-radius: 8px; overflow: hidden; }
.prompt-header { padding: 9px 14px; border-bottom: 1.5px solid var(--border); display: flex; align-items: center; justify-content: space-between; background: var(--surface-alt); }
.prompt-filename { font-size: 12px; font-weight: 700; font-family: var(--mono); }
.prompt-actions { display: flex; gap: 6px; }
.btn { padding: 5px 12px; border-radius: 6px; font-size: 11px; font-weight: 700; border: none; cursor: pointer; transition: all 0.1s; }
.btn-sm { padding: 5px 12px; }
.btn-primary { background: var(--accent); color: #fff; }
.btn-primary:hover { background: var(--accent-light); }
.btn-secondary { background: var(--surface); color: var(--text-secondary); border: 1.5px solid var(--border); }
.btn-danger { background: var(--red-bg); color: var(--red); border: 1.5px solid var(--red-border); }
.prompt-body { padding: 12px 16px; font-size: 11.5px; color: var(--text-secondary); line-height: 1.65; white-space: pre-wrap; font-family: var(--mono); margin: 0; max-height: 500px; overflow-y: auto; }
.empty-content { display: flex; flex-direction: column; align-items: center; justify-content: center; padding: 80px 0; color: var(--text-muted); font-size: 13px; gap: 8px; }
.empty-icon { font-size: 28px; }
</style>
