<template>
  <div class="dashboard">
    <!-- Global language toggle -->
    <div class="global-lang-toggle">
      <button :class="{ active: lang === 'zh' }" @click="lang = 'zh'">中文</button>
      <button :class="{ active: lang === 'en' }" @click="lang = 'en'">EN</button>
    </div>

    <!-- Project selector (no active project) -->
    <ProjectSelector v-if="!hasActiveProject"
      @open="onProjectOpen" @create="onProjectCreate" />

    <!-- Main dashboard (active project) -->
    <template v-else>
      <Sidebar
        :config="config"
        :state="state"
        :selected="selected"
        :modules="modules"
        @select="onSelect"
        @selectModule="activeModule = $event"
        @backToProjects="closeProject"
      />

      <div class="main-content">
        <!-- INIT panels -->
        <InitPanel v-if="selected?.startsWith('INIT')"
          :readonly="isInitialized" :existingConfig="config" :selected="selected"
          :projectDir="activeProjectDir"
          @initialized="onInitialized" @backToProjects="closeProject" />

        <!-- Overview -->
        <OverviewPanel v-else-if="selected === 'OVERVIEW' && isInitialized" :state="state" :config="config" />

        <!-- Design -->
        <DesignChecklistPanel v-else-if="selected === 'DESIGN_checklist'" :state="state" :config="config" />

        <!-- Build -->
        <ImportCheckPanel v-else-if="selected === 'BUILD_import'" :state="state" :config="config" @update="refreshState" />
        <DecomposePanel v-else-if="selected === 'BUILD_decompose'" :state="state" :modules="modules" />
        <CheckpointPanel v-else-if="selected === 'BUILD_checkpoint'" :modules="modules" />

        <!-- Module -->
        <ModulePanel v-else-if="selected?.startsWith('MODULE_') && currentModule"
          :module="currentModule" :config="config" />

        <!-- Pending phases -->
        <PendingPanel v-else-if="selected?.startsWith('VERIFY_')" :title="t.verifyPhase" />
        <PendingPanel v-else-if="selected?.startsWith('SHIP_')" :title="t.shipPhase" />

        <!-- Default -->
        <InitPanel v-else-if="!isInitialized" :selected="selected"
          :projectDir="activeProjectDir"
          @initialized="onInitialized" @backToProjects="closeProject" />
        <OverviewPanel v-else :state="state" :config="config" />
      </div>
    </template>
  </div>
</template>

<script setup>
import { ref, computed, onMounted } from 'vue'
import { useApi } from '../composables/useApi.js'
import { useWebSocket } from '../composables/useWebSocket.js'
import { useI18n } from '../composables/useI18n.js'
import ProjectSelector from '../components/ProjectSelector.vue'
import Sidebar from '../components/Sidebar.vue'
import InitPanel from '../components/InitPanel.vue'
import ModulePanel from '../components/ModulePanel.vue'
import OverviewPanel from '../components/panels/OverviewPanel.vue'
import DesignChecklistPanel from '../components/panels/DesignChecklistPanel.vue'
import ImportCheckPanel from '../components/panels/ImportCheckPanel.vue'
import DecomposePanel from '../components/panels/DecomposePanel.vue'
import CheckpointPanel from '../components/panels/CheckpointPanel.vue'
import PendingPanel from '../components/panels/PendingPanel.vue'

const api = useApi()
const ws = useWebSocket()
const { t, lang } = useI18n()

const hasActiveProject = ref(false)
const activeProjectDir = ref(null)
const config = ref(null)
const state = ref(null)
const selected = ref('INIT_basic')
const activeModule = ref(null)

const isInitialized = computed(() => state.value?.phases?.INIT?.status === 'completed')

const modules = computed(() => {
  const mods = state.value?.phases?.BUILD?.modules || {}
  return Object.entries(mods).map(([id, data]) => ({
    id, label: data.label || id,
    status: data.status === 'completed' ? 'completed' : data.status === 'in_progress' ? 'active' : 'pending',
    sub_step: data.sub_step, ...data,
  }))
})

const currentModule = computed(() => modules.value.find(m => m.id === activeModule.value) || null)

function onSelect(nodeId) { selected.value = nodeId }

// Project opened from selector (existing project)
async function onProjectOpen(projectDir, cfg, st) {
  activeProjectDir.value = projectDir
  config.value = cfg
  state.value = st
  hasActiveProject.value = true
  if (isInitialized.value) {
    selected.value = 'OVERVIEW'
    const active = modules.value.find(m => m.status === 'active')
    if (active) { activeModule.value = active.id; selected.value = 'MODULE_' + active.id }
  } else {
    selected.value = 'INIT_basic'
  }
}

// New project created from selector
async function onProjectCreate(projectDir) {
  activeProjectDir.value = projectDir
  hasActiveProject.value = true
  config.value = null
  state.value = {
    project: null, current_phase: 'INIT',
    phases: { INIT: { status: 'in_progress' }, DESIGN: { status: 'locked' }, BUILD: { status: 'locked', modules: {} }, VERIFY: { status: 'locked' }, SHIP: { status: 'locked' } },
  }
  selected.value = 'INIT_basic'
}

// Init completed
async function onInitialized() {
  config.value = await api.getConfig()
  state.value = await api.getState()
  selected.value = 'OVERVIEW'
}

// Close project → back to selector
async function closeProject() {
  try { await api.closeProject() } catch (e) {}
  hasActiveProject.value = false
  activeProjectDir.value = null
  config.value = null
  state.value = null
  selected.value = 'INIT_basic'
}

async function refreshState() {
  try { state.value = await api.getState() } catch (e) {}
}

ws.on('state_updated', (data) => { state.value = data })

onMounted(async () => {
  // Check if there's an active project from a previous session
  try {
    const active = await api.getActive()
    if (active.hasProject && active.project_dir) {
      activeProjectDir.value = active.project_dir
      config.value = await api.getConfig()
      state.value = await api.getState()
      hasActiveProject.value = true
      if (isInitialized.value) {
        selected.value = 'OVERVIEW'
      } else {
        selected.value = 'INIT_basic'
      }
      return
    }
  } catch (e) {}
  // No active project → show selector
  hasActiveProject.value = false
})
</script>

<style scoped>
.dashboard { display: flex; height: 100vh; overflow: hidden; position: relative; }
.main-content { flex: 1; overflow: hidden; display: flex; flex-direction: column; }

.global-lang-toggle {
  position: fixed; top: 12px; right: 16px; display: flex; gap: 0; z-index: 100;
}
.global-lang-toggle button {
  font-size: 11px; padding: 4px 12px; border: 1.5px solid var(--border);
  background: var(--surface); color: var(--text-muted); cursor: pointer; transition: all 0.1s;
}
.global-lang-toggle button:first-child { border-radius: 5px 0 0 5px; border-right: none; }
.global-lang-toggle button:last-child { border-radius: 0 5px 5px 0; }
.global-lang-toggle button.active { background: var(--accent); color: #fff; border-color: var(--accent); }
</style>
