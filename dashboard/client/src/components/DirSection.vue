<template>
  <div class="dir-section">
    <div class="dir-header" @click="toggleOpen" :style="{ color }">
      <span class="dir-arrow">{{ isOpen ? '▼' : '▶' }}</span>
      <span class="dir-icon">{{ icon }}</span>
      <span class="dir-label">{{ label }}</span>
    </div>
    <div class="dir-path" :title="basePath">{{ basePath || '—' }}</div>
    <div v-if="isOpen && tree.length > 0" class="dir-tree">
      <FileNode v-for="node in tree" :key="node.name" :node="node" :depth="0" />
    </div>
    <div v-if="isOpen && tree.length === 0 && basePath" class="dir-empty">
      {{ loading ? '...' : '—' }}
    </div>
  </div>
</template>

<script setup>
import { ref, watch } from 'vue'
import FileNode from './FileNode.vue'
import { useApi } from '../composables/useApi.js'

const props = defineProps({
  icon: String, label: String, color: String,
  basePath: String, defaultOpen: { type: Boolean, default: false },
})

const api = useApi()
const isOpen = ref(props.defaultOpen)
const tree = ref([])
const loading = ref(false)
const loaded = ref(false)

function toggleOpen() { isOpen.value = !isOpen.value; if (isOpen.value && !loaded.value) loadTree() }

async function loadTree() {
  if (!props.basePath) return
  loading.value = true
  try { const data = await api.getFileTree(props.basePath); tree.value = data.tree || []; loaded.value = true }
  catch (e) { tree.value = [] }
  loading.value = false
}

if (props.defaultOpen && props.basePath) loadTree()
watch(() => props.basePath, () => { loaded.value = false; tree.value = []; if (isOpen.value) loadTree() })
</script>

<style scoped>
.dir-section { margin-bottom: 2px; }
.dir-header { padding: 4px 8px; display: flex; align-items: center; gap: 5px; cursor: pointer; font-weight: 700; font-size: 11px; }
.dir-arrow { font-size: 8px; color: var(--text-muted); width: 8px; text-align: center; }
.dir-icon { font-size: 12px; }
.dir-path { padding: 0 8px 2px 21px; font-size: 9px; color: var(--text-muted); font-family: var(--mono); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.dir-tree { padding-left: 4px; }
.dir-empty { padding: 4px 21px; font-size: 10px; color: var(--text-dim); }
</style>
