<template>
  <span
    class="status-dot"
    :class="status"
    :style="{ width: size + 'px', height: size + 'px' }"
  />
</template>

<script setup>
defineProps({
  status: { type: String, default: 'pending' },
  size: { type: Number, default: 7 },
})
</script>

<style scoped>
.status-dot {
  display: inline-block;
  border-radius: 50%;
  flex-shrink: 0;
  background: var(--text-dim);
}

.status-dot.completed, .status-dot.done { background: var(--green); }
.status-dot.active, .status-dot.in_progress {
  background: var(--accent);
  animation: pulse 2s ease-in-out infinite;
}
.status-dot.pending { background: var(--text-dim); }
.status-dot.blocked { background: var(--red); }
</style>
