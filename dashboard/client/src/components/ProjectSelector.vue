<template>
  <div class="selector">
    <div class="selector-inner">
      <!-- Hero -->
      <h1 class="hero-title">MIMIR Build Orchestrator</h1>
      <p class="hero-intro">{{ t.intro }}</p>

      <!-- Action cards -->
      <div class="action-row">
        <div class="action-card" @click="createNew">
          <span class="action-icon">🆕</span>
          <span class="action-label">{{ t.newProject }}</span>
          <span class="action-desc">{{ t.newDesc }}</span>
        </div>
        <div class="action-card" @click="openExisting">
          <span class="action-icon">📂</span>
          <span class="action-label">{{ t.openProject }}</span>
          <span class="action-desc">{{ t.openDesc }}</span>
        </div>
      </div>

      <!-- Recent projects -->
      <div class="recent" v-if="projects.length > 0">
        <div class="recent-header">
          <span>{{ t.recent }}</span>
          <button class="btn-link" @click="showSettings = !showSettings">⚙️ {{ t.settings }}</button>
        </div>

        <div v-if="showSettings" class="settings-bar">
          <label>{{ t.registryDir }}</label>
          <div class="settings-row">
            <input :value="registryDir" class="form-input mono" readonly />
            <button class="btn btn-secondary btn-sm" @click="changeRegistryDir">{{ t.change }}</button>
          </div>
        </div>

        <div class="project-list">
          <div v-for="proj in sortedProjects" :key="proj.project_dir" class="project-card"
            :class="{ missing: !proj.exists }" @click="proj.exists && open(proj)">
            <div class="proj-left">
              <span class="proj-pin" @click.stop="togglePin(proj)" :title="proj.pinned ? t.unpin : t.pin">
                {{ proj.pinned ? '📌' : '  ' }}
              </span>
              <span class="proj-phase">{{ phaseIcon(proj.phase) }}</span>
            </div>
            <div class="proj-info">
              <div class="proj-name">{{ proj.name }}</div>
              <div class="proj-meta">
                {{ proj.phase }} · {{ timeAgo(proj.updated_at) }}
                <span v-if="!proj.exists" class="proj-missing">{{ t.dirMissing }}</span>
              </div>
              <div class="proj-path">{{ proj.project_dir }}</div>
            </div>
            <div class="proj-actions" @click.stop>
              <button class="btn-icon" @click="remove(proj)" :title="t.removeFromList">✕</button>
            </div>
          </div>
        </div>
      </div>

      <div v-else class="empty">
        <p>{{ t.emptyHint }}</p>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useApi } from '../composables/useApi.js'
import { useI18n } from '../composables/useI18n.js'

const emit = defineEmits(['open', 'create'])
const api = useApi()
const { t, timeAgo } = useI18n()

const projects = ref([])
const registryDir = ref('')
const showSettings = ref(false)

const sortedProjects = computed(() =>
  [...projects.value].sort((a, b) => {
    if (a.pinned !== b.pinned) return a.pinned ? -1 : 1
    return new Date(b.updated_at || 0) - new Date(a.updated_at || 0)
  })
)

async function loadProjects() {
  try { const d = await api.getProjects(); projects.value = d.projects || []; registryDir.value = d.registryDir || '' }
  catch (e) { projects.value = [] }
}

async function createNew() {
  try {
    const r = await api.pickFolder(t.value.pickNewWs)
    if (r.cancelled || !r.selected) return
    await api.createProject(r.selected)
    emit('create', r.selected)
  } catch (e) {}
}

async function openExisting() {
  try {
    const r = await api.pickFolder(t.value.pickExistingWs)
    if (r.cancelled || !r.selected) return
    const d = await api.openProject(r.selected)
    emit('open', r.selected, d.config, d.state)
  } catch (e) { alert(e.message) }
}

function open(proj) {
  api.openProject(proj.project_dir)
    .then(d => emit('open', proj.project_dir, d.config, d.state))
    .catch(e => alert(e.message))
}
function togglePin(proj) { api.pinProject(proj.project_dir, !proj.pinned).then(loadProjects) }
function remove(proj) {
  if (!confirm(t.value.confirmRemove(proj.name))) return
  api.unregisterProject(proj.project_dir).then(loadProjects)
}
async function changeRegistryDir() {
  try {
    const r = await api.pickFolder(t.value.pickRegistryDir)
    if (r.cancelled || !r.selected) return
    await api.setRegistryDir(r.selected); await loadProjects()
  } catch (e) {}
}
function phaseIcon(p) { return { INIT:'⬜', DESIGN:'📐', BUILD:'⚙️', VERIFY:'✅', SHIP:'🚢' }[p] || '⬜' }

onMounted(loadProjects)
</script>

<style scoped>
.selector {
  flex: 1; width: 100%;
  display: flex; flex-direction: column; align-items: center;
  height: 100vh; background: var(--bg); overflow-y: auto;
  padding-top: 12vh;
}
.selector-inner { width: 560px; max-width: 88vw; }

/* Hero */
.hero-title {
  font-family: var(--mono); font-size: 28px; font-weight: 700;
  color: var(--text); margin-bottom: 10px; letter-spacing: -0.5px;
  text-align: center;
}
.hero-intro {
  font-size: 13px; line-height: 1.7; color: var(--text-secondary);
  margin-bottom: 32px; text-align: left;
}

/* Action cards */
.action-row { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-bottom: 32px; }
.action-card {
  display: flex; flex-direction: column; align-items: center; gap: 4px;
  padding: 22px 16px; border: 2px solid var(--border); border-radius: 10px;
  cursor: pointer; transition: all 0.15s; background: var(--surface);
}
.action-card:hover { border-color: var(--accent); background: var(--accent-bg); }
.action-icon { font-size: 28px; }
.action-label { font-size: 14px; font-weight: 700; }
.action-desc { font-size: 11px; color: var(--text-muted); }

/* Recent */
.recent { text-align: left; }
.recent-header {
  display: flex; justify-content: space-between; align-items: center;
  margin-bottom: 8px; font-size: 12px; font-weight: 700; color: var(--text-secondary); text-align: left;
}
.btn-link { background: none; border: none; font-size: 11px; color: var(--text-muted); cursor: pointer; }
.btn-link:hover { color: var(--text); }

.settings-bar { background: var(--surface-alt); border-radius: 6px; padding: 8px 12px; margin-bottom: 10px; text-align: left; }
.settings-bar label { font-size: 10px; font-weight: 600; color: var(--text-muted); display: block; margin-bottom: 4px; }
.settings-row { display: flex; gap: 6px; }
.settings-row .form-input { flex: 1; padding: 4px 8px; font-size: 11px; }

.project-list { display: flex; flex-direction: column; gap: 4px; text-align: left; }
.project-card {
  display: flex; align-items: center; gap: 10px; padding: 10px 12px;
  border: 1.5px solid var(--border); border-radius: 8px; cursor: pointer;
  transition: all 0.1s; background: var(--surface);
}
.project-card:hover:not(.missing) { border-color: var(--accent); }
.project-card.missing { opacity: 0.5; cursor: not-allowed; }
.proj-left { display: flex; align-items: center; gap: 4px; }
.proj-pin { cursor: pointer; font-size: 12px; width: 18px; text-align: center; }
.proj-phase { font-size: 16px; }
.proj-info { flex: 1; min-width: 0; }
.proj-name { font-size: 13px; font-weight: 700; }
.proj-meta { font-size: 11px; color: var(--text-muted); }
.proj-missing { color: var(--red); }
.proj-path { font-size: 10px; color: var(--text-dim); font-family: var(--mono); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.proj-actions { flex-shrink: 0; }
.btn-icon { background: none; border: none; font-size: 10px; cursor: pointer; color: var(--text-muted); padding: 4px; }
.btn-icon:hover { color: var(--red); }

.form-input { width: 100%; padding: 7px 11px; border: 1.5px solid var(--border); border-radius: 6px; font-size: 13px; background: var(--surface); color: var(--text); outline: none; }
.form-input.mono { font-family: var(--mono); font-size: 11px; }
.btn { padding: 7px 18px; border-radius: 6px; font-size: 12px; font-weight: 700; border: none; cursor: pointer; }
.btn-secondary { background: var(--surface); color: var(--text-secondary); border: 1.5px solid var(--border); }
.btn-sm { padding: 4px 10px; font-size: 11px; }
.empty { text-align: center; padding: 32px 0; color: var(--text-dim); font-size: 13px; }
</style>
