<template>
  <div>
    <div
      class="tree-phase"
      :class="{ 'is-locked': locked }"
      :style="{ paddingLeft: 8 + (depth || 0) * 14 + 'px' }"
      @click="!locked && $emit('toggle')"
    >
      <span class="tree-arrow">{{ expanded ? '▼' : '▶' }}</span>
      <StatusDot :status="status" :size="6" />
      <span class="tree-icon">{{ icon }}</span>
      <span class="tree-label">{{ label }}</span>
      <span v-if="badge" class="tree-badge" :class="status">{{ badge }}</span>
    </div>
    <div v-if="expanded">
      <slot />
    </div>
  </div>
</template>

<script setup>
import StatusDot from './StatusDot.vue'

defineProps({
  icon: String,
  label: String,
  nodeId: String,
  status: { type: String, default: 'pending' },
  badge: String,
  expanded: Boolean,
  depth: { type: Number, default: 0 },
  locked: { type: Boolean, default: false },
})

defineEmits(['toggle'])
</script>

<style scoped>
.tree-phase {
  padding: 5px 8px;
  display: flex;
  align-items: center;
  gap: 6px;
  cursor: pointer;
  font-size: 12px;
  font-weight: 600;
  color: var(--text);
  border-radius: 4px;
  margin: 0 4px;
  transition: background 0.1s;
}

.tree-phase.is-locked {
  opacity: 0.35;
  cursor: default;
}

.tree-phase:hover {
  background: var(--surface-alt);
}

.tree-arrow {
  font-size: 8px;
  color: var(--text-muted);
  width: 8px;
  text-align: center;
}

.tree-icon { font-size: 11px; }

.tree-label { flex: 1; }

.tree-badge {
  font-size: 9px;
  font-weight: 700;
  font-family: var(--mono);
  padding: 1px 5px;
  border-radius: 8px;
}

.tree-badge.completed { color: var(--green); background: var(--green-bg); }
.tree-badge.active { color: var(--accent); background: var(--accent-bg); }
.tree-badge.pending { color: var(--text-dim); }
</style>
