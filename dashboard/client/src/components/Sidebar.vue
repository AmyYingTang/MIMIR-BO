<template>
  <div class="sidebar">
    <div class="sidebar-header">
      <div class="sidebar-top">
        <div class="sidebar-logo">MIMIR-BO</div>
        <button class="back-btn" @click="$emit('backToProjects')">⬅ {{ t.backToProjects }}</button>
      </div>
      <div class="sidebar-instance" @click="$emit('select', 'OVERVIEW')">
        {{ config?.instance_name || 'MIMIR-BO' }}
        <span v-if="isInitialized" class="settings-icon" @click.stop="$emit('select', 'INIT_basic')">⚙️</span>
      </div>
    </div>

    <div class="sidebar-tree">
      <!-- INIT -->
      <TreePhase icon="🎯" :label="t.initSettings" nodeId="INIT"
        :status="phaseStatus('INIT')"
        :expanded="expanded.INIT" @toggle="toggle('INIT')">
        <TreeItem icon="📝" :label="t.basicInfo" nodeId="INIT_basic"
          :status="initStepStatus(0)" :selected="selected === 'INIT_basic'"
          @click="$emit('select', 'INIT_basic')" />
        <TreeItem icon="📂" :label="t.dirConfig" nodeId="INIT_dirs"
          :status="initStepStatus(1)" :selected="selected === 'INIT_dirs'"
          @click="$emit('select', 'INIT_dirs')" />
        <TreeItem icon="📦" :label="t.mimirContent" nodeId="INIT_mimir"
          :status="initStepStatus(2)" :selected="selected === 'INIT_mimir'"
          @click="$emit('select', 'INIT_mimir')" />
        <TreeItem icon="🔧" :label="t.customSkills" nodeId="INIT_skills"
          :status="initStepStatus(3)" :selected="selected === 'INIT_skills'"
          @click="$emit('select', 'INIT_skills')" />
      </TreePhase>

      <!-- DESIGN -->
      <TreePhase icon="📐" :label="t.designPhase" nodeId="DESIGN"
        :status="phaseStatus('DESIGN')" :locked="!isInitialized"
        :expanded="expanded.DESIGN" @toggle="isInitialized && toggle('DESIGN')">
        <TreeItem icon="📋" :label="t.docChecklist" nodeId="DESIGN_checklist"
          :status="phaseStatus('DESIGN')" :selected="selected === 'DESIGN_checklist'"
          @click="$emit('select', 'DESIGN_checklist')" />
      </TreePhase>

      <!-- BUILD -->
      <TreePhase icon="⚙️" :label="t.buildPhase" nodeId="BUILD"
        :status="phaseStatus('BUILD')" :locked="!isInitialized"
        :expanded="expanded.BUILD" @toggle="isInitialized && toggle('BUILD')">
        <TreeItem icon="🔍" :label="t.importCheck" nodeId="BUILD_import"
          :status="stepStatus('BUILD', 'import_check')" :selected="selected === 'BUILD_import'"
          @click="$emit('select', 'BUILD_import')" />
        <TreeItem icon="✂️" :label="t.taskDecompose" nodeId="BUILD_decompose"
          :status="stepStatus('BUILD', 'task_decompose')" :selected="selected === 'BUILD_decompose'"
          @click="$emit('select', 'BUILD_decompose')" />
        <TreePhase icon="🔄" :label="t.moduleExec" nodeId="BUILD_modules"
          :status="modulesOverallStatus" :badge="modulesBadge"
          :expanded="expanded.BUILD_modules" @toggle="toggle('BUILD_modules')" :depth="1">
          <TreeItem v-for="mod in modules" :key="mod.id"
            :icon="null" :label="mod.id + '  ' + mod.label" :nodeId="'MODULE_' + mod.id"
            :status="mod.status === 'completed' ? 'completed' : mod.status === 'active' ? 'active' : 'pending'"
            :selected="selected === 'MODULE_' + mod.id" :mono="true" :pulse="mod.status === 'active'"
            @click="$emit('select', 'MODULE_' + mod.id); $emit('selectModule', mod.id)" :depth="2" />
        </TreePhase>
        <TreeItem icon="🏁" :label="t.checkpoint" nodeId="BUILD_checkpoint"
          :status="stepStatus('BUILD', 'checkpoint')" :selected="selected === 'BUILD_checkpoint'"
          @click="$emit('select', 'BUILD_checkpoint')" />
      </TreePhase>

      <!-- VERIFY -->
      <TreePhase icon="✅" :label="t.verifyPhase" nodeId="VERIFY"
        :status="phaseStatus('VERIFY')" :locked="!isInitialized"
        :expanded="expanded.VERIFY" @toggle="isInitialized && toggle('VERIFY')">
        <TreeItem icon="🧪" :label="t.testAccept" nodeId="VERIFY_test" status="pending"
          :selected="selected === 'VERIFY_test'" @click="$emit('select', 'VERIFY_test')" />
        <TreeItem icon="🔒" :label="t.secAudit" nodeId="VERIFY_security" status="pending"
          :selected="selected === 'VERIFY_security'" @click="$emit('select', 'VERIFY_security')" />
        <TreeItem icon="👤" :label="t.uat" nodeId="VERIFY_uat" status="pending"
          :selected="selected === 'VERIFY_uat'" @click="$emit('select', 'VERIFY_uat')" />
      </TreePhase>

      <!-- SHIP -->
      <TreePhase icon="🚢" :label="t.shipPhase" nodeId="SHIP"
        :status="phaseStatus('SHIP')" :locked="!isInitialized"
        :expanded="expanded.SHIP" @toggle="isInitialized && toggle('SHIP')">
        <TreeItem icon="🚀" :label="t.deploy" nodeId="SHIP_deploy" status="pending"
          :selected="selected === 'SHIP_deploy'" @click="$emit('select', 'SHIP_deploy')" />
        <TreeItem icon="📄" :label="t.docSync" nodeId="SHIP_docs" status="pending"
          :selected="selected === 'SHIP_docs'" @click="$emit('select', 'SHIP_docs')" />
        <TreeItem icon="📊" :label="t.opsFeedback" nodeId="SHIP_ops" status="pending"
          :selected="selected === 'SHIP_ops'" @click="$emit('select', 'SHIP_ops')" />
      </TreePhase>
    </div>

    <!-- Project Space -->
    <ProjectSpace :config="config" :initialized="isInitialized" />
  </div>
</template>

<script setup>
import { reactive, computed } from 'vue'
import TreePhase from './TreePhase.vue'
import TreeItem from './TreeItem.vue'
import ProjectSpace from './ProjectSpace.vue'
import { useI18n } from '../composables/useI18n.js'

const { t } = useI18n()

const props = defineProps({
  config: Object,
  state: Object,
  selected: String,
  modules: { type: Array, default: () => [] },
})

defineEmits(['select', 'selectModule', 'backToProjects'])

const expanded = reactive({
  INIT: true,
  DESIGN: false,
  BUILD: true,
  BUILD_modules: true,
  VERIFY: false,
  SHIP: false,
})

function toggle(key) { expanded[key] = !expanded[key] }

const isInitialized = computed(() => {
  return props.state?.phases?.INIT?.status === 'completed'
})

function phaseStatus(phase) {
  const s = props.state?.phases?.[phase]?.status
  if (s === 'completed') return 'completed'
  if (s === 'in_progress') return 'active'
  if (s === 'locked') return 'locked'
  return 'pending'
}

function stepStatus(phase, step) {
  const s = props.state?.phases?.[phase]?.[step]
  if (s === 'completed') return 'completed'
  if (s === 'in_progress') return 'active'
  return 'pending'
}

function initStepStatus(stepIdx) {
  if (props.state?.phases?.INIT?.status === 'completed') return 'completed'
  // During init, show all sub-steps as active
  return 'active'
}

const modulesBadge = computed(() => {
  const mods = props.state?.phases?.BUILD?.modules || {}
  const total = Object.keys(mods).length
  const done = Object.values(mods).filter(m => m.status === 'completed').length
  return total > 0 ? `${done}/${total}` : null
})

const modulesOverallStatus = computed(() => {
  const mods = props.state?.phases?.BUILD?.modules || {}
  const vals = Object.values(mods)
  if (vals.length === 0) return 'pending'
  if (vals.every(m => m.status === 'completed')) return 'completed'
  if (vals.some(m => m.status === 'in_progress')) return 'active'
  return 'pending'
})
</script>

<style scoped>
.sidebar {
  width: var(--sidebar-width); display: flex; flex-direction: column;
  border-right: 1.5px solid var(--border); background: var(--surface);
  flex-shrink: 0; height: 100vh; overflow: hidden;
}
.sidebar-header {
  padding: 14px 12px 10px; border-bottom: 1px solid var(--border-light); flex-shrink: 0;
}
.sidebar-top { display: flex; justify-content: space-between; align-items: center; margin-bottom: 2px; }
.sidebar-logo { font-family: var(--mono); font-size: 11px; font-weight: 700; color: var(--text-muted); letter-spacing: 0.5px; }
.back-btn {
  font-size: 10px; color: var(--text-muted); background: none; border: 1px solid var(--border);
  border-radius: 4px; padding: 2px 6px; cursor: pointer; transition: all 0.1s;
}
.back-btn:hover { color: var(--accent); border-color: var(--accent); }
.sidebar-instance {
  font-family: var(--serif); font-size: 14px; font-weight: 700; color: var(--text);
  cursor: pointer; display: flex; align-items: center; gap: 4px;
}
.settings-icon { font-size: 12px; opacity: 0; transition: opacity 0.1s; }
.sidebar-instance:hover .settings-icon { opacity: 1; }
.sidebar-tree { flex: 1; overflow-y: auto; padding: 6px 0; }
</style>
