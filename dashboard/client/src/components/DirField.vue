<template>
  <div class="form-group">
    <label>{{ icon }} {{ label }}</label>
    <div class="dir-row">
      <div class="dir-display" :class="{ empty: !value }">
        {{ value || t.notSelected }}
      </div>
      <button class="btn btn-secondary btn-sm" @click="$emit('pick')">{{ t.pick }}</button>
    </div>
    <span class="form-hint" v-if="hint">{{ hint }}</span>
  </div>
</template>

<script setup>
import { useI18n } from '../composables/useI18n.js'
const { t } = useI18n()
defineProps({ icon: String, label: String, hint: String, value: String })
defineEmits(['pick'])
</script>

<style scoped>
.form-group { margin-bottom: 14px; }
.form-group label { display: block; font-size: 12px; font-weight: 600; margin-bottom: 4px; color: var(--text-secondary); }
.dir-row { display: flex; gap: 6px; }
.dir-display {
  flex: 1; padding: 7px 11px; border: 1.5px solid var(--border); border-radius: 6px;
  font-family: var(--mono); font-size: 11px; color: var(--text);
  background: var(--surface-alt); min-height: 32px;
}
.dir-display.empty { color: var(--text-dim); }
.form-hint { display: block; font-size: 11px; color: var(--text-muted); margin-top: 2px; }
.btn { padding: 5px 12px; border-radius: 6px; font-size: 11px; font-weight: 700; border: none; cursor: pointer; }
.btn-secondary { background: var(--surface); color: var(--text-secondary); border: 1.5px solid var(--border); }
.btn-sm { padding: 5px 12px; }
</style>
