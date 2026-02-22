<template>
  <div class="panel">
    <h2 class="panel-title">{{ t.overview }}</h2>
    <div class="phase-grid">
      <div v-for="p in phases" :key="p.label" class="phase-card">
        <div class="phase-label">{{ p.label }}</div>
        <div class="phase-value" :style="{ color: p.color }">{{ p.value }}</div>
      </div>
    </div>
    <div class="section-label">{{ t.recentActivity }}</div>
    <div class="activity-list">
      <div class="activity-empty" v-if="!state">{{ t.activityHint }}</div>
      <div v-else class="activity-item" v-for="(a, i) in recentActivity" :key="i">
        <span class="activity-time">{{ a.time }}</span>
        <span class="activity-dot" :style="{ background: a.color }" />
        <span>{{ a.text }}</span>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { useI18n } from '../../composables/useI18n.js'
const { t } = useI18n()
const props = defineProps({ state: Object, config: Object })

const phases = computed(() => {
  const s = props.state?.phases || {}
  const cl = s.DESIGN?.checklist || {}
  const dt = Object.keys(cl).length, dd = Object.values(cl).filter(c => c.status === 'done').length
  const mods = s.BUILD?.modules || {}
  const mt = Object.keys(mods).length, md = Object.values(mods).filter(m => m.status === 'completed').length
  return [
    { label: t.value.designPhase, value: dt ? `${dd}/${dt} ${t.value.completed}` : t.value.notStarted, color: dd === dt && dt > 0 ? '#16a34a' : '#B3562A' },
    { label: t.value.buildPhase, value: mt ? `${md}/${mt} ${t.value.modules}` : t.value.notStarted, color: md === mt && mt > 0 ? '#16a34a' : '#B3562A' },
    { label: t.value.verifyPhase, value: s.VERIFY?.status === 'completed' ? t.value.completed : t.value.notStarted, color: '#C4BDB5' },
    { label: t.value.shipPhase, value: s.SHIP?.status === 'completed' ? t.value.completed : t.value.notStarted, color: '#C4BDB5' },
  ]
})

const recentActivity = computed(() => {
  if (!props.state) return []
  return [{ time: t.value.justNow, text: t.value.activityInitDone, color: '#16a34a' }]
})
</script>

<style scoped>
.panel { padding: 28px 32px; overflow-y: auto; }
.panel-title { font-family: var(--serif); font-size: 17px; font-weight: 700; margin-bottom: 16px; }
.phase-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 10px; margin-bottom: 24px; }
.phase-card { background: var(--surface); border: 1.5px solid var(--border); border-radius: 8px; padding: 12px 14px; }
.phase-label { font-size: 12px; color: var(--text-muted); margin-bottom: 4px; }
.phase-value { font-size: 16px; font-weight: 700; font-family: var(--mono); }
.section-label { font-size: 12px; font-weight: 700; color: var(--text-muted); margin-bottom: 8px; }
.activity-list { display: flex; flex-direction: column; gap: 2px; }
.activity-item { display: flex; gap: 8px; align-items: center; padding: 5px 0; font-size: 12px; color: var(--text-secondary); }
.activity-time { font-family: var(--mono); color: var(--text-muted); font-size: 11px; min-width: 40px; }
.activity-dot { width: 6px; height: 6px; border-radius: 50%; flex-shrink: 0; }
.activity-empty { color: var(--text-muted); font-size: 12px; padding: 20px 0; }
</style>
