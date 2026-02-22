<template>
  <div class="project-space">
    <div class="space-title">{{ t.projectSpace.toUpperCase() }}</div>

    <template v-if="initialized">
      <DirSection icon="📦" :label="t.mimirDir" color="#7c3aed"
        :basePath="config?.paths?.mimir" :defaultOpen="false" />
      <DirSection icon="🔧" :label="t.boToolsDir" color="#78716c"
        :basePath="config?.paths?.tools" :defaultOpen="false" />
      <DirSection icon="📁" :label="t.projectDir" color="#16a34a"
        :basePath="config?.paths?.project" :defaultOpen="true" />
    </template>

    <div v-else class="space-empty">
      —
    </div>
  </div>
</template>

<script setup>
import DirSection from './DirSection.vue'
import { useI18n } from '../composables/useI18n.js'
const { t } = useI18n()
defineProps({ config: Object, initialized: Boolean })
</script>

<style scoped>
.project-space {
  border-top: 1.5px solid var(--border); overflow-y: auto;
  flex-shrink: 0; max-height: 40%; font-size: 11px;
}
.space-title {
  padding: 8px 10px 4px; font-size: 9px; font-weight: 700;
  color: var(--text-muted); letter-spacing: 1px; font-family: var(--mono);
}
.space-empty {
  padding: 12px 10px; font-size: 11px; color: var(--text-dim); text-align: center;
}
</style>
