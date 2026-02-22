<template>
  <div class="panel">
    <h2 class="panel-title">{{ t.decomposeTitle }}</h2>
    <p class="panel-desc" v-if="modules.length === 0">{{ t.decomposeEmpty }}</p>
    <p class="panel-status" v-else>{{ t.decomposeDone(modules.length) }}</p>
    <div v-if="modules.length > 0" class="module-list">
      <div v-for="(mod, i) in modules" :key="mod.id" class="module-item">
        <span class="mod-index">{{ i + 1 }}</span>
        <span class="mod-id">{{ mod.id }}</span>
        <span class="mod-label">{{ mod.label }}</span>
        <span class="mod-status">{{ mod.status === 'completed' ? '✅' : mod.status === 'active' ? '🔵' : '⬜' }}</span>
      </div>
    </div>
    <div v-else class="placeholder">
      <div class="placeholder-icon">✂️</div>
      <div>{{ t.decomposePlaceholder }}</div>
    </div>
  </div>
</template>

<script setup>
import { useI18n } from '../../composables/useI18n.js'
const { t } = useI18n()
defineProps({ state: Object, modules: { type: Array, default: () => [] } })
</script>

<style scoped>
.panel { padding: 24px 28px; overflow-y: auto; }
.panel-title { font-family: var(--serif); font-size: 17px; font-weight: 700; margin-bottom: 4px; }
.panel-desc { font-size: 12px; color: var(--text-muted); margin-bottom: 16px; }
.panel-status { font-size: 12px; color: var(--green); font-weight: 600; margin-bottom: 16px; }
.module-list { display: flex; flex-direction: column; gap: 4px; }
.module-item { display: flex; align-items: center; gap: 8px; padding: 8px 12px; border: 1.5px solid var(--border); border-radius: 6px; font-size: 12px; }
.mod-index { font-size: 10px; color: var(--text-muted); font-family: var(--mono); width: 16px; }
.mod-id { font-family: var(--mono); font-weight: 700; color: var(--accent); }
.mod-label { flex: 1; color: var(--text-secondary); }
.placeholder { text-align: center; padding: 60px 0; color: var(--text-muted); font-size: 13px; }
.placeholder-icon { font-size: 28px; margin-bottom: 8px; }
</style>
