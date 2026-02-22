<template>
  <div class="picker-overlay" @click.self="$emit('cancel')">
    <div class="picker-dialog">
      <div class="picker-header">
        <span class="picker-title">{{ title || t.selectDir }}</span>
        <button class="picker-close" @click="$emit('cancel')">✕</button>
      </div>

      <div class="picker-breadcrumb">
        <span class="crumb-path">{{ currentDir }}</span>
      </div>

      <div class="picker-list">
        <div v-if="parentDir" class="picker-item parent" @click="navigate(parentDir)">
          <span class="item-icon">⬆️</span>
          <span class="item-name">..</span>
        </div>
        <template v-for="entry in entries" :key="entry.path">
          <div class="picker-item"
            :class="{ selected: entry.path === selectedPath }"
            @click="selectEntry(entry)" @dblclick="navigate(entry.path)">
            <span class="item-icon">📁</span>
            <span class="item-name">{{ entry.name }}</span>
            <span v-if="entry.path === selectedPath && entry.children?.length" class="child-count">
              {{ t.subDirsCount(entry.children.length) }}
            </span>
          </div>
          <div v-if="entry.path === selectedPath && entry.children?.length" class="child-list">
            <div v-for="child in entry.children" :key="child.path" class="picker-item child"
              @click="selectEntry(child)" @dblclick="navigate(child.path)"
              :class="{ selected: child.path === selectedPath }">
              <span class="item-icon">📂</span>
              <span class="item-name">{{ child.name }}</span>
            </div>
          </div>
        </template>
        <div v-if="entries.length === 0 && !loading" class="picker-empty">{{ t.noSubDirs }}</div>
      </div>

      <div class="picker-selected" v-if="selectedPath">
        {{ t.selectedLabel }}: <span class="selected-path">{{ selectedPath }}</span>
      </div>

      <div class="picker-footer">
        <button class="btn btn-secondary" @click="$emit('cancel')">{{ t.cancel }}</button>
        <button class="btn btn-primary" :disabled="!selectedPath" @click="confirm">{{ t.confirm }}</button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useApi } from '../composables/useApi.js'
import { useI18n } from '../composables/useI18n.js'

const { t } = useI18n()
const props = defineProps({ title: String, initialPath: String })
const emit = defineEmits(['select', 'cancel'])
const api = useApi()

const currentDir = ref('')
const parentDir = ref(null)
const entries = ref([])
const selectedPath = ref(null)
const loading = ref(false)

async function navigate(dir) {
  loading.value = true
  selectedPath.value = null
  try {
    const data = await api.browse(dir)
    currentDir.value = data.current
    parentDir.value = data.parent
    entries.value = data.entries.map(e => ({ ...e, children: null }))
  } catch (e) { entries.value = [] }
  loading.value = false
}

async function selectEntry(entry) {
  selectedPath.value = entry.path
  const target = entries.value.find(e => e.path === entry.path)
  if (target && target.children === null) {
    try { const data = await api.browse(entry.path); target.children = data.entries }
    catch (e) { target.children = [] }
  }
  for (const e of entries.value) {
    if (e.children) {
      const child = e.children.find(c => c.path === entry.path)
      if (child) { selectedPath.value = entry.path; return }
    }
  }
}

function confirm() { if (selectedPath.value) emit('select', selectedPath.value) }

onMounted(() => navigate(props.initialPath || ''))
</script>

<style scoped>
.picker-overlay {
  position: fixed; top: 0; left: 0; right: 0; bottom: 0;
  background: rgba(0,0,0,0.3); display: flex; align-items: center;
  justify-content: center; z-index: 1000;
}
.picker-dialog {
  background: var(--surface); border: 1.5px solid var(--border);
  border-radius: 12px; width: 540px; max-height: 75vh;
  display: flex; flex-direction: column;
  box-shadow: 0 8px 32px rgba(0,0,0,0.12);
}
.picker-header {
  padding: 12px 16px; border-bottom: 1px solid var(--border-light);
  display: flex; align-items: center; justify-content: space-between;
}
.picker-title { font-size: 13px; font-weight: 700; }
.picker-close { background: none; border: none; font-size: 14px; cursor: pointer; color: var(--text-muted); }
.picker-breadcrumb { padding: 6px 16px; background: var(--surface-alt); border-bottom: 1px solid var(--border-light); }
.crumb-path { font-family: var(--mono); font-size: 11px; color: var(--text-secondary); }
.picker-list { flex: 1; overflow-y: auto; padding: 4px 8px; min-height: 200px; max-height: 380px; }
.picker-item {
  display: flex; align-items: center; gap: 8px;
  padding: 6px 10px; border-radius: 5px; cursor: pointer;
  font-size: 12px; transition: background 0.1s;
}
.picker-item:hover { background: var(--surface-alt); }
.picker-item.selected { background: var(--accent-bg); border: 1px solid var(--accent-border); }
.picker-item.parent { color: var(--text-muted); }
.picker-item.child { padding-left: 32px; font-size: 11px; }
.item-icon { font-size: 13px; }
.item-name { flex: 1; }
.child-count { font-size: 9px; color: var(--text-dim); font-family: var(--mono); }
.child-list { border-left: 2px solid var(--accent-bg); margin-left: 22px; }
.picker-empty { text-align: center; padding: 20px; color: var(--text-dim); font-size: 12px; }
.picker-selected {
  padding: 6px 16px; font-size: 11px; color: var(--text-muted);
  border-top: 1px solid var(--border-light); background: var(--surface-alt);
}
.selected-path { font-family: var(--mono); color: var(--accent); }
.picker-footer {
  padding: 10px 16px; border-top: 1px solid var(--border-light);
  display: flex; gap: 8px; justify-content: flex-end;
}
.btn { padding: 6px 16px; border-radius: 6px; font-size: 11px; font-weight: 700; border: none; cursor: pointer; }
.btn-primary { background: var(--accent); color: #fff; }
.btn-primary:disabled { opacity: 0.4; cursor: not-allowed; }
.btn-secondary { background: var(--surface); color: var(--text-secondary); border: 1.5px solid var(--border); }
</style>
