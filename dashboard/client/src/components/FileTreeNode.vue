<template>
  <div class="tree-node">
    <div class="node-row" :class="{ dir: node.isDirectory, file: !node.isDirectory, selected: node.path === selectedPath }"
      @click="handleClick">
      <span v-if="node.isDirectory" class="expand-icon" @click.stop="expanded = !expanded">
        {{ expanded ? '▼' : '▶' }}
      </span>
      <span v-else class="expand-icon spacer"></span>
      <span class="node-icon">{{ node.isDirectory ? '📁' : '📄' }}</span>
      <span class="node-name">{{ node.name }}</span>
      <span v-if="node.isDirectory && node.children" class="node-count">{{ countFiles(node) }}</span>
      <span v-if="!node.isDirectory && node.size" class="node-size">{{ formatSize(node.size) }}</span>
    </div>
    <div v-if="node.isDirectory && expanded && node.children" class="node-children">
      <FileTreeNode v-for="child in node.children" :key="child.path"
        :node="child" :selectedPath="selectedPath"
        @select="$emit('select', $event)" />
    </div>
  </div>
</template>

<script setup>
import { ref } from 'vue'

const props = defineProps({
  node: Object,
  selectedPath: String,
})
const emit = defineEmits(['select'])

const expanded = ref(false)

function handleClick() {
  if (props.node.isDirectory) {
    expanded.value = !expanded.value
  } else {
    emit('select', props.node)
  }
}

function countFiles(node) {
  if (!node.children) return ''
  let count = 0
  function walk(n) {
    if (!n.isDirectory) count++
    else if (n.children) n.children.forEach(walk)
  }
  node.children.forEach(walk)
  return count + ' files'
}

function formatSize(bytes) {
  return bytes < 1024 ? bytes + 'B' : (bytes / 1024).toFixed(1) + 'KB'
}
</script>

<style scoped>
.tree-node { font-size: 12px; }
.node-row {
  display: flex; align-items: center; gap: 4px;
  padding: 2px 6px; border-radius: 4px; cursor: pointer;
  transition: background 0.1s;
}
.node-row:hover { background: var(--surface-alt); }
.node-row.selected { background: var(--accent-bg); border: 1px solid var(--accent-border); }
.node-row.file { cursor: pointer; }
.expand-icon { width: 12px; font-size: 8px; color: var(--text-dim); text-align: center; flex-shrink: 0; }
.expand-icon.spacer { visibility: hidden; }
.node-icon { font-size: 11px; flex-shrink: 0; }
.node-name { flex: 1; font-family: var(--mono); font-size: 11px; }
.node-row.file .node-name { color: var(--text); }
.node-row.dir .node-name { font-weight: 600; color: var(--text-secondary); }
.node-count { font-size: 9px; color: var(--text-dim); font-family: var(--mono); }
.node-size { font-size: 9px; color: var(--text-dim); font-family: var(--mono); }
.node-children { padding-left: 16px; }
</style>
