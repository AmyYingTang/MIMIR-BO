<template>
  <div class="panel">
    <h2 class="panel-title">{{ t.importCheckTitle }}</h2>
    <p class="panel-desc">{{ t.importCheckDesc }}</p>
    <button class="btn btn-primary" @click="runScan" :disabled="scanning">
      {{ scanning ? t.scanning : t.runScan }}
    </button>
    <div v-if="results.length > 0" class="scan-results">
      <div v-for="doc in results" :key="doc.id" class="scan-item" :class="doc.status">
        <span class="scan-icon">{{ doc.status === 'found' ? '✅' : '⚠️' }}</span>
        <span class="scan-label">{{ doc.label }}</span>
        <span class="scan-path" v-if="doc.path">{{ doc.path }}</span>
        <span class="scan-missing" v-else>{{ t.notFound }}</span>
      </div>
    </div>
    <div v-if="scanDone" class="scan-summary">
      <span class="found-count">✅ {{ foundCount }} {{ t.found }}</span>
      <span class="missing-count" v-if="missingCount > 0">⚠️ {{ missingCount }} {{ t.missing }}</span>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from 'vue'
import { useApi } from '../../composables/useApi.js'
import { useI18n } from '../../composables/useI18n.js'
const { t } = useI18n()
const props = defineProps({ state: Object, config: Object })
const emit = defineEmits(['update'])
const api = useApi()
const scanning = ref(false), scanDone = ref(false), results = ref([])
const foundCount = computed(() => results.value.filter(d => d.status === 'found').length)
const missingCount = computed(() => results.value.filter(d => d.status === 'missing').length)

async function runScan() {
  scanning.value = true
  try {
    results.value = await api.scanDesignDocs()
    scanDone.value = true
    await api.patchState({
      phases: {
        BUILD: { import_check: 'completed' },
        DESIGN: { status: 'completed', checklist: Object.fromEntries(results.value.map(d => [d.id, { status: d.path ? 'done' : 'missing', path: d.path }])) },
      },
    })
    emit('update')
  } catch (e) { alert(t.value.scanFailed + ': ' + e.message) }
  scanning.value = false
}
</script>

<style scoped>
.panel { padding: 24px 28px; max-width: 700px; overflow-y: auto; }
.panel-title { font-family: var(--serif); font-size: 17px; font-weight: 700; margin-bottom: 4px; }
.panel-desc { font-size: 12px; color: var(--text-muted); margin-bottom: 16px; }
.btn { padding: 8px 20px; border-radius: 7px; font-size: 12px; font-weight: 700; border: none; transition: all 0.1s; margin-bottom: 16px; }
.btn-primary { background: var(--accent); color: #fff; cursor: pointer; }
.btn-primary:hover { background: var(--accent-light); }
.btn-primary:disabled { opacity: 0.5; cursor: not-allowed; }
.scan-results { display: flex; flex-direction: column; gap: 4px; margin-bottom: 12px; }
.scan-item { display: flex; align-items: center; gap: 8px; padding: 8px 10px; border: 1.5px solid var(--border); border-radius: 6px; font-size: 12px; }
.scan-item.found { border-color: var(--green-border); background: var(--green-bg); }
.scan-label { font-weight: 600; flex: 1; }
.scan-path { color: var(--text-muted); font-family: var(--mono); font-size: 10px; }
.scan-missing { color: var(--yellow); font-size: 11px; }
.scan-summary { display: flex; gap: 12px; font-size: 12px; font-weight: 600; }
.found-count { color: var(--green); }
.missing-count { color: var(--yellow); }
</style>
