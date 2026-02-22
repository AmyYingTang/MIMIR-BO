<template>
  <div class="panel center">
    <div class="icon">⏳</div>
    <div class="title">{{ title }}</div>
    <div class="desc">{{ t.pendingDesc }}</div>
  </div>
</template>

<script setup>
import { useI18n } from '../../composables/useI18n.js'
const { t } = useI18n()
defineProps({ title: String })
</script>

<style scoped>
.panel.center { padding: 24px 28px; text-align: center; padding-top: 80px; color: var(--text-muted); }
.icon { font-size: 28px; margin-bottom: 8px; }
.title { font-size: 14px; font-weight: 600; margin-bottom: 4px; }
.desc { font-size: 12px; }
</style>
