<template>
  <div class="panel center">
    <div class="icon">🏁</div>
    <div class="title">{{ t.checkpointTitle }}</div>
    <div class="desc">{{ t.checkpointDesc }}</div>
    <div class="progress" v-if="modules.length > 0">{{ t.checkpointProgress(doneCount, modules.length) }}</div>
  </div>
</template>

<script setup>
import { computed } from 'vue'
import { useI18n } from '../../composables/useI18n.js'
const { t } = useI18n()
const props = defineProps({ modules: { type: Array, default: () => [] } })
const doneCount = computed(() => props.modules.filter(m => m.status === 'completed').length)
</script>

<style scoped>
.panel.center { padding: 24px 28px; text-align: center; padding-top: 80px; }
.icon { font-size: 28px; margin-bottom: 8px; }
.title { font-size: 14px; font-weight: 600; margin-bottom: 4px; }
.desc, .progress { font-size: 12px; color: var(--text-muted); }
</style>
