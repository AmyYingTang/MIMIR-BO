<template>
  <div class="panel">
    <h2 class="panel-title">{{ t.designChecklist }}</h2>
    <p class="panel-status" :class="allDone ? 'done' : 'partial'">
      {{ allDone ? t.allDocsReady : t.docsPartial(doneCount, totalCount) }}
    </p>
    <div class="checklist">
      <div v-for="(item, key) in checklist" :key="key" class="checklist-item">
        <span class="check-icon">{{ item.status === 'done' ? '✓' : '⚠️' }}</span>
        <span class="check-label">{{ docLabel(key) }}</span>
        <span class="check-path" v-if="item.path">{{ item.path }}</span>
        <span class="check-missing" v-else>{{ t.notFound }}</span>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { useI18n } from '../../composables/useI18n.js'
const { t } = useI18n()
const props = defineProps({ state: Object, config: Object })

const DOC_KEY_MAP = { prd: 'prd', tech_stack: 'techStack', api_design: 'apiDesign', database_design: 'dbDesign', state_machines: 'stateMachines', business_rules: 'businessRules', security_arch: 'securityArch' }
function docLabel(key) { return t.value[DOC_KEY_MAP[key]] || key }

const checklist = computed(() => props.state?.phases?.DESIGN?.checklist || {})
const totalCount = computed(() => Object.keys(checklist.value).length)
const doneCount = computed(() => Object.values(checklist.value).filter(c => c.status === 'done').length)
const allDone = computed(() => totalCount.value > 0 && doneCount.value === totalCount.value)
</script>

<style scoped>
.panel { padding: 24px 28px; max-width: 700px; overflow-y: auto; }
.panel-title { font-family: var(--serif); font-size: 17px; font-weight: 700; margin-bottom: 4px; }
.panel-status { font-size: 12px; font-weight: 600; margin-bottom: 16px; }
.panel-status.done { color: var(--green); }
.panel-status.partial { color: var(--yellow); }
.checklist { background: var(--surface); border: 1.5px solid var(--border); border-radius: 8px; overflow: hidden; }
.checklist-item { display: flex; align-items: center; gap: 10px; padding: 10px 14px; border-bottom: 1px solid var(--border-light); font-size: 12px; }
.checklist-item:last-child { border-bottom: none; }
.check-icon { font-weight: 700; }
.check-label { font-weight: 600; flex: 1; }
.check-path { color: var(--text-muted); font-family: var(--mono); font-size: 10px; }
.check-missing { color: var(--yellow); font-size: 11px; }
</style>
