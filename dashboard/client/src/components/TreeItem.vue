<template>
  <div
    class="tree-item"
    :class="{ selected, 'is-pending': status === 'pending' }"
    :style="{ paddingLeft: 8 + ((depth || 1) + 1) * 14 + 'px' }"
    @click="$emit('click')"
  >
    <span class="tree-spacer" />
    <StatusDot :status="status" :size="6" />
    <span v-if="icon" class="tree-icon">{{ icon }}</span>
    <span class="tree-label" :class="{ mono }">{{ label }}</span>
    <span v-if="pulse" class="pulse-dot" />
  </div>
</template>

<script setup>
import StatusDot from './StatusDot.vue'

defineProps({
  icon: String,
  label: String,
  nodeId: String,
  status: { type: String, default: 'pending' },
  selected: Boolean,
  mono: Boolean,
  pulse: Boolean,
  depth: { type: Number, default: 1 },
})

defineEmits(['click'])
</script>

<style scoped>
.tree-item {
  padding: 4px 8px;
  display: flex;
  align-items: center;
  gap: 6px;
  cursor: pointer;
  font-size: 12px;
  font-weight: 500;
  color: var(--text);
  border-radius: 4px;
  margin: 0 4px;
  transition: all 0.1s;
}

.tree-item:hover { background: var(--surface-alt); }

.tree-item.selected {
  background: var(--accent-bg);
  color: var(--accent);
  font-weight: 700;
}

.tree-item.is-pending { opacity: 0.45; }

.tree-spacer { width: 8px; }
.tree-icon { font-size: 11px; }
.tree-label { flex: 1; }
.tree-label.mono { font-family: var(--mono); font-size: 11px; }

.pulse-dot {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--yellow);
  animation: pulse 2s ease-in-out infinite;
}
</style>
