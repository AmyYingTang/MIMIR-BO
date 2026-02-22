<template>
  <div>
    <div
      class="file-node"
      :style="{ paddingLeft: 12 + depth * 11 + 'px' }"
      @click="node.isDirectory && node.children ? (expanded = !expanded) : null"
      :class="{ clickable: node.isDirectory && node.children?.length }"
    >
      <span v-if="node.isDirectory && node.children?.length" class="node-arrow">
        {{ expanded ? '▼' : '▶' }}
      </span>
      <span v-else class="node-spacer" />
      <span class="node-icon">{{ node.isDirectory ? '📂' : '📄' }}</span>
      <span class="node-name" :class="{ directory: node.isDirectory }">
        {{ node.name }}{{ node.isDirectory ? '/' : '' }}
      </span>
    </div>
    <div v-if="expanded && node.children">
      <FileNode
        v-for="child in node.children"
        :key="child.name"
        :node="child"
        :depth="depth + 1"
      />
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'

const props = defineProps({
  node: Object,
  depth: { type: Number, default: 0 },
})

const expanded = ref(false)
</script>

<style scoped>
.file-node {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 2px 8px;
  font-size: 11px;
  color: var(--text-secondary);
  border-radius: 3px;
}

.file-node.clickable { cursor: pointer; }
.file-node.clickable:hover { background: var(--surface-alt); }

.node-arrow {
  font-size: 7px;
  color: var(--text-muted);
  width: 7px;
}

.node-spacer { width: 7px; }
.node-icon { opacity: 0.6; font-size: 10px; }

.node-name { font-size: 11px; }
.node-name.directory { font-weight: 500; }
</style>
