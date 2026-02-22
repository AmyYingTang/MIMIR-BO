<template>
  <div class="init-layout">
    <div class="panel">
      <h2 class="panel-title">{{ t.initTitle }}</h2>
      <div v-if="isReadonly" class="readonly-banner">{{ t.readonlyBanner }}</div>

      <!-- Step indicators -->
      <div class="steps-bar">
        <div v-for="(s, i) in computedStepLabels" :key="i"
          class="step-ind" :class="{ active: step === i, done: step > i || (isReadonly && i < 3) }"
          @click="goStep(i)">
          <span class="step-num">{{ (step > i || (isReadonly && i < 3)) ? '✓' : i + 1 }}</span>
          <span>{{ s }}</span>
        </div>
      </div>

      <!-- Step 0: Basic Info -->
      <div v-if="step === 0" class="step-content">
        <h3>{{ t.basicInfo }} <span v-if="isReadonly" class="ro-tag">{{ t.readonly }}</span></h3>
        <div class="form-group">
          <label>{{ t.instanceName }}</label>
          <input v-model="config.instance_name" :placeholder="t.instanceHint" class="form-input" :disabled="isReadonly" />
        </div>
        <div class="form-group">
          <label>{{ t.langPref }}</label>
          <select v-model="config.language" class="form-input" :disabled="isReadonly">
            <option value="zh">{{ t.langZh }}</option>
            <option value="en">{{ t.langEn }}</option>
            <option value="bilingual">{{ t.langBi }}</option>
          </select>
        </div>
        <div class="form-group">
          <label>{{ t.projectType }}</label>
          <div class="type-grid">
            <div v-for="pt in computedProjectTypes" :key="pt.id"
              class="type-card" :class="{ selected: config.project_type === pt.id, locked: pt.locked || isReadonly }"
              @click="!pt.locked && !isReadonly && (config.project_type = pt.id)">
              <span class="type-icon">{{ pt.icon }}</span>
              <span class="type-name">{{ pt.label }}</span>
              <span v-if="pt.locked" class="type-badge">{{ t.comingSoon }}</span>
              <span v-else-if="config.project_type === pt.id" class="type-check">✓</span>
            </div>
          </div>
        </div>
      </div>

      <!-- Step 1: Directories -->
      <div v-if="step === 1" class="step-content">
        <h3>{{ t.dirConfigTitle }} <span v-if="isReadonly" class="ro-tag">{{ t.readonly }}</span></h3>
        <div class="inherited-dir">
          <span class="inherited-icon">📁</span>
          <div class="inherited-info">
            <span class="inherited-label">{{ t.projectDir }}</span>
            <code class="inherited-path">{{ config.paths.project }}</code>
          </div>
          <span class="inherited-badge">{{ t.inheritedFromSelector }}</span>
        </div>
        <DirField icon="📦" :label="t.mimirDir" :hint="t.mimirDirHint"
          :value="config.paths.mimir" :disabled="isReadonly" @pick="!isReadonly && openPicker('mimir')" />
        <DirField icon="🔧" :label="t.boToolsDir" :hint="t.boToolsDirHint"
          :value="config.paths.tools" :disabled="isReadonly" @pick="!isReadonly && openPicker('tools')" />
        <div v-if="config.paths.project" class="workspace-info">
          <span class="workspace-label">📂 {{ t.workspaceDir }}</span>
          <code class="workspace-path">{{ config.paths.project }}/.mimir/</code>
          <span class="workspace-hint">{{ t.autoCreated }}</span>
        </div>
      </div>

      <!-- Step 2: MIMIR Content -->
      <div v-if="step === 2" class="step-content">
        <h3>{{ t.mimirContentTitle }} <span v-if="isReadonly" class="ro-tag">{{ t.readonly }}</span></h3>
        <p class="content-intro">{{ t.mimirContentIntro(`MIMIR/${langDir}/`) }}</p>
        <div class="content-category">
          <div class="cat-header">
            <span class="cat-icon">📦</span>
            <span class="cat-label">{{ t.mimirContentTitle }}</span>
            <span class="cat-stats" v-if="mimirScan">
              {{ mimirScan.totalFiles }} {{ t.files }} · {{ (mimirScan.totalSize / 1024).toFixed(1) }}KB
            </span>
          </div>
          <div v-if="!mimirScan || mimirScan.tree.length === 0" class="cat-empty">
            {{ config.paths.mimir ? t.noContent : t.configMimirFirst }}
          </div>
          <div v-else class="file-tree">
            <FileTreeNode v-for="node in mimirScan.tree" :key="node.path"
              :node="node" :selectedPath="previewFile?.path" @select="previewMd" />
          </div>
        </div>
      </div>

      <!-- Step 3: Custom Skills -->
      <div v-if="step === 3" class="step-content">
        <h3>{{ t.customSkillsTitle }}</h3>
        <p class="content-intro">{{ t.customSkillsIntro }}</p>
        <div class="content-category">
          <div class="cat-header">
            <span class="cat-icon">👤</span>
            <span class="cat-label">{{ t.userContent }}</span>
            <span class="cat-stats" v-if="userDirs.length > 0">{{ userDirs.length }} {{ t.dirs }}</span>
          </div>
          <div v-for="(dir, i) in userDirs" :key="dir.path" class="user-dir">
            <div class="user-dir-header">
              <span class="dir-path">{{ dir.path }}</span>
              <span class="cat-stats" v-if="dir.scan">{{ dir.scan.totalFiles }} {{ t.files }}</span>
              <button class="btn-icon del" @click="removeUserDir(i)">✕</button>
            </div>
            <div v-if="dir.scan" class="file-tree nested">
              <FileTreeNode v-for="node in dir.scan.tree" :key="node.path"
                :node="node" :selectedPath="previewFile?.path" @select="previewMd" />
            </div>
          </div>
          <div v-if="userDirs.length === 0" class="cat-empty">{{ t.noCustomSkills }}</div>
          <button class="btn btn-secondary btn-sm" @click="addUserDir" style="margin-top:8px">{{ t.addCustomSkill }}</button>
        </div>
      </div>

      <!-- Navigation -->
      <div class="step-nav">
        <button v-if="step > 0" class="btn btn-secondary" @click="step--">{{ t.prevStep }}</button>
        <div style="flex:1" />
        <template v-if="!isReadonly">
          <button v-if="step < 3" class="btn btn-primary" @click="nextStep" :disabled="!canNext">{{ t.nextStep }}</button>
          <button v-if="step === 3" class="btn btn-primary" @click="finish">{{ t.finishInit }}</button>
        </template>
        <template v-else>
          <button v-if="step < 3" class="btn btn-secondary" @click="nextStep">{{ t.nextStep }}</button>
          <button v-if="step === 3 && userDirsDirty" class="btn btn-primary" @click="saveUserDirs">{{ t.saveCustomSkills }}</button>
        </template>
      </div>

      <!-- Back to project list -->
      <div v-if="isReadonly" class="back-section">
        <div class="back-divider"></div>
        <div class="back-row">
          <span class="back-hint">{{ t.switchProject }}</span>
          <button class="btn btn-secondary btn-sm" @click="emit('backToProjects')">{{ t.backToProjectList }}</button>
        </div>
      </div>
    </div>

    <!-- Preview panel -->
    <div v-if="previewFile" class="preview-panel">
      <div class="preview-header">
        <span class="preview-title">{{ previewFile.name }}</span>
        <span class="preview-path">{{ previewFile.relativePath }}</span>
        <button class="btn-icon" @click="previewFile = null">✕</button>
      </div>
      <div class="preview-body" v-html="previewHtml"></div>
    </div>
  </div>
</template>

<script setup>
import { ref, reactive, computed, watch, onMounted } from 'vue'
import { useApi } from '../composables/useApi.js'
import { useI18n } from '../composables/useI18n.js'
import DirField from './DirField.vue'
import FileTreeNode from './FileTreeNode.vue'

const props = defineProps({
  readonly: { type: Boolean, default: false },
  existingConfig: { type: Object, default: null },
  selected: { type: String, default: '' },
  projectDir: { type: String, default: '' },
})
const emit = defineEmits(['initialized', 'backToProjects'])
const api = useApi()
const { t } = useI18n()

const step = ref(0)
const computedStepLabels = computed(() => [t.value.basicInfo, t.value.dirConfigTitle, t.value.mimirContentTitle, t.value.customSkillsTitle])

const isReadonly = computed(() => props.readonly)

// Sidebar → step sync
const STEP_MAP = { INIT_basic: 0, INIT_dirs: 1, INIT_mimir: 2, INIT_skills: 3 }
watch(() => props.selected, (val) => {
  if (val in STEP_MAP) {
    const target = STEP_MAP[val]
    if (isReadonly.value || target <= step.value) {
      step.value = target
    } else if (target === step.value + 1) {
      nextStep()
    }
  }
}, { immediate: true })

const computedProjectTypes = computed(() => [
  { id: 'enterprise-web', label: t.value.enterpriseWeb, icon: '🏢', locked: false },
  { id: 'lightweight-web', label: t.value.lightweightWeb, icon: '🌐', locked: true },
  { id: 'mobile-app', label: t.value.mobileApp, icon: '📱', locked: true },
  { id: 'cli-tool', label: t.value.cliTool, icon: '⌨️', locked: true },
  { id: 'mvp', label: t.value.quickProto, icon: '🚀', locked: true },
  { id: 'minimal', label: t.value.minConfig, icon: '📦', locked: true },
])

const config = reactive({
  instance_name: '',
  language: 'zh',
  project_type: 'enterprise-web',
  paths: { mimir: '', tools: '', project: '' },
  user_content_dirs: [],
  source_docs: {},
})

const mimirScan = ref(null)
const userDirs = ref([])
const savedUserDirs = ref([]) // for dirty tracking
const userDirsDirty = computed(() => {
  const current = userDirs.value.map(d => d.path).join(',')
  const saved = savedUserDirs.value.join(',')
  return current !== saved
})

const langDir = computed(() => config.language === 'bilingual' ? 'zh' : config.language)

// Step navigation from step indicators
function goStep(i) {
  if (isReadonly.value) { step.value = i; loadStepData(i); return }
  if (i < step.value) step.value = i
}

// File preview
const previewFile = ref(null)
const previewHtml = ref('')

async function previewMd(node) {
  if (node.isDirectory) return
  previewFile.value = node
  previewHtml.value = `<p style="color:var(--text-dim)">${t.value.loading}</p>`
  try {
    const data = await api.readFile(node.path)
    previewHtml.value = renderMarkdown(data.content)
  } catch (e) {
    previewHtml.value = `<p style="color:var(--red)">${t.value.readFailed}: ${e.message}</p>`
  }
}

function renderMarkdown(md) {
  return md
    .replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
    .replace(/```(\w*)\n([\s\S]*?)```/g, '<pre><code class="lang-$1">$2</code></pre>')
    .replace(/`([^`]+)`/g, '<code>$1</code>')
    .replace(/^#### (.+)$/gm, '<h4>$1</h4>')
    .replace(/^### (.+)$/gm, '<h3>$1</h3>')
    .replace(/^## (.+)$/gm, '<h2>$1</h2>')
    .replace(/^# (.+)$/gm, '<h1>$1</h1>')
    .replace(/\*\*(.+?)\*\*/g, '<strong>$1</strong>')
    .replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>')
    .replace(/^- (.+)$/gm, '<li>$1</li>')
    .replace(/((?:<li>.*<\/li>\n?)+)/g, '<ul>$1</ul>')
    .replace(/^(?!<[hupla])((?!<).+)$/gm, '<p>$1</p>')
}

// Native OS folder picker
async function openPicker(target) {
  const titles = {
    mimir: t.value.mimirDir, tools: t.value.boToolsDir,
    project: t.value.projectDir,
  }
  try {
    const result = await api.pickFolder(titles[target] || '')
    if (result.cancelled || !result.selected) return
    config.paths[target] = result.selected
  } catch (e) { /* cancelled */ }
}

async function addUserDir() {
  try {
    const result = await api.pickFolder(t.value.pickCustomSkill)
    if (result.cancelled || !result.selected) return
    const validation = await api.validateSkillDir(result.selected)
    if (!validation.valid) { alert(`${t.value.invalid}: ${validation.reason}`); return }
    const scans = await api.scanUserDirs([result.selected])
    userDirs.value.push({ path: result.selected, name: validation.name, scan: scans[0] || null })
  } catch (e) { /* cancelled */ }
}

function removeUserDir(index) {
  userDirs.value.splice(index, 1)
}

async function saveUserDirs() {
  config.user_content_dirs = userDirs.value.map(d => d.path)
  try {
    await api.saveConfig({ ...config })
    await api.regenerateManifest()
    savedUserDirs.value = [...config.user_content_dirs]
    alert(t.value.savedManifest)
  } catch (e) { alert(t.value.saveFailed + ': ' + e.message) }
}

const canNext = computed(() => {
  if (step.value === 0) return config.instance_name.trim() !== '' && config.project_type
  if (step.value === 1) return config.paths.mimir && config.paths.tools
  return true
})

const lastScannedLang = ref(null)

async function loadStepData(targetStep) {
  if (targetStep === 2 && config.paths.mimir) {
    const lang = config.language === 'bilingual' ? 'zh' : config.language
    if (!mimirScan.value || lastScannedLang.value !== lang) {
      try {
        mimirScan.value = await api.scanMimirContent(config.paths.mimir, config.language)
        lastScannedLang.value = lang
      } catch (e) {}
    }
  }
}

async function nextStep() {
  if (step.value === 1) {
    await loadStepData(2)
  }
  step.value++
}

async function finish() {
  config.user_content_dirs = userDirs.value.map(d => d.path)
  try {
    await api.saveConfig({ ...config })
    emit('initialized')
  } catch (e) { alert(t.value.saveFailed + ': ' + e.message) }
}

onMounted(async () => {
  // Inherit project dir from selector
  if (props.projectDir && !props.readonly) {
    config.paths.project = props.projectDir
  }
  if (props.readonly && props.existingConfig) {
    Object.assign(config, {
      instance_name: props.existingConfig.instance_name || '',
      language: props.existingConfig.language || 'zh',
      project_type: props.existingConfig.project_type || '',
      paths: { ...props.existingConfig.paths },
      user_content_dirs: props.existingConfig.user_content_dirs || [],
      source_docs: props.existingConfig.source_docs || {},
    })
    savedUserDirs.value = [...(config.user_content_dirs || [])]
    // Load MIMIR scan
    if (config.paths.mimir) {
      try { mimirScan.value = await api.scanMimirContent(config.paths.mimir, config.language) } catch (e) {}
    }
    // Load user dirs
    for (const p of config.user_content_dirs) {
      try {
        const scans = await api.scanUserDirs([p])
        if (scans[0]) userDirs.value.push({ path: p, name: scans[0].name, scan: scans[0] })
      } catch (e) {}
    }
  }
})
</script>

<style scoped>
.init-layout { display: flex; height: 100%; overflow: hidden; }
.panel { padding: 24px 28px; overflow-y: auto; flex: 2; }
.panel-title { font-family: var(--serif); font-size: 17px; font-weight: 700; margin-bottom: 8px; }

.readonly-banner {
  font-size: 12px; color: var(--green); background: var(--green-bg);
  padding: 6px 12px; border-radius: 6px; margin-bottom: 16px; border: 1px solid #86efac;
}

.steps-bar { display: flex; gap: 4px; margin-bottom: 20px; padding-bottom: 16px; border-bottom: 1.5px solid var(--border-light); }
.step-ind { flex: 1; display: flex; align-items: center; gap: 5px; padding: 5px 6px; border-radius: 6px; font-size: 11px; color: var(--text-dim); cursor: pointer; }
.step-ind.active { background: var(--accent-bg); color: var(--accent); font-weight: 600; }
.step-ind.done { color: var(--green); }
.step-num { width: 18px; height: 18px; border-radius: 50%; display: flex; align-items: center; justify-content: center; font-size: 10px; font-weight: 700; background: var(--surface-alt); flex-shrink: 0; }
.active .step-num { background: var(--accent); color: #fff; }
.done .step-num { background: var(--green-bg); color: var(--green); }

.step-content { min-height: 240px; }
.step-content h3 { font-family: var(--serif); font-size: 14px; margin-bottom: 14px; display: flex; align-items: center; gap: 8px; }
.ro-tag { font-size: 9px; background: var(--surface-alt); color: var(--text-muted); padding: 1px 6px; border-radius: 8px; font-family: var(--mono); font-weight: 400; }

.form-group { margin-bottom: 14px; }
.form-group label { display: block; font-size: 12px; font-weight: 600; margin-bottom: 4px; color: var(--text-secondary); }
.form-input { width: 100%; padding: 7px 11px; border: 1.5px solid var(--border); border-radius: 6px; font-size: 13px; background: var(--surface); color: var(--text); outline: none; }
.form-input:focus { border-color: var(--accent); }
.form-input:disabled { opacity: 0.65; cursor: not-allowed; }
.form-input.mono { font-family: var(--mono); font-size: 11px; }
.form-hint { display: block; font-size: 11px; color: var(--text-muted); margin-top: 2px; }
.inherited-dir {
  display: flex; align-items: center; gap: 10px; padding: 10px 14px;
  background: var(--surface-alt); border: 1.5px solid var(--border-light); border-radius: 8px;
  margin-bottom: 14px;
}
.inherited-icon { font-size: 18px; flex-shrink: 0; }
.inherited-info { flex: 1; min-width: 0; }
.inherited-label { display: block; font-size: 12px; font-weight: 600; color: var(--text-secondary); margin-bottom: 2px; }
.inherited-path { display: block; font-family: var(--mono); font-size: 11px; color: var(--text); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
.inherited-badge { font-size: 9px; color: var(--text-muted); background: var(--surface); padding: 2px 8px; border-radius: 8px; flex-shrink: 0; white-space: nowrap; }
.workspace-info {
  margin-top: 12px; padding: 8px 12px; background: var(--surface-alt);
  border-radius: 6px; display: flex; align-items: center; gap: 8px; flex-wrap: wrap;
}
.workspace-label { font-size: 12px; font-weight: 600; color: var(--text-secondary); }
.workspace-path { font-family: var(--mono); font-size: 11px; color: var(--text); background: var(--surface); padding: 2px 6px; border-radius: 4px; }
.workspace-hint { font-size: 10px; color: var(--text-muted); }

.type-grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; }
.type-card {
  display: flex; flex-direction: column; align-items: center; gap: 3px;
  padding: 10px 6px; border: 1.5px solid var(--border); border-radius: 8px;
  cursor: pointer; font-size: 11px; text-align: center; transition: all 0.1s; position: relative;
}
.type-card:hover:not(.locked) { border-color: var(--accent-border); }
.type-card.selected { border-color: var(--accent); background: var(--accent-bg); }
.type-card.locked { opacity: 0.4; cursor: not-allowed; }
.type-icon { font-size: 20px; }
.type-name { font-weight: 600; }
.type-badge { font-size: 8px; color: var(--text-dim); background: var(--surface-alt); padding: 1px 5px; border-radius: 6px; }
.type-check { position: absolute; top: 4px; right: 6px; font-size: 12px; color: var(--accent); }

/* Step 2 + 3 content */
.content-intro { font-size: 11px; color: var(--text-muted); margin-bottom: 12px; line-height: 1.5; }
.content-intro code { background: var(--surface-alt); padding: 1px 4px; border-radius: 3px; font-family: var(--mono); font-size: 10px; }
.content-category { margin-bottom: 16px; }
.cat-header { display: flex; align-items: center; gap: 6px; margin-bottom: 5px; padding-bottom: 4px; border-bottom: 1px solid var(--border-light); }
.cat-icon { font-size: 13px; }
.cat-label { font-size: 12px; font-weight: 700; }
.cat-stats { font-size: 10px; color: var(--text-muted); margin-left: auto; font-family: var(--mono); }
.cat-empty { font-size: 11px; color: var(--text-dim); padding: 6px 0 6px 20px; }
.file-tree { padding-left: 4px; }
.file-tree.nested { padding-left: 12px; margin-top: 4px; }

.user-dir { margin-bottom: 8px; }
.user-dir-header {
  display: flex; align-items: center; gap: 6px; padding: 4px 8px;
  background: var(--surface-alt); border-radius: 5px; font-size: 11px;
}
.dir-path { font-family: var(--mono); flex: 1; color: var(--text-secondary); }

.btn-icon { background: none; border: none; font-size: 10px; cursor: pointer; color: var(--text-muted); padding: 2px; }
.btn-icon.del { color: var(--red); opacity: 0.5; }
.btn-icon.del:hover { opacity: 1; }

.step-nav { display: flex; gap: 8px; margin-top: 20px; padding-top: 14px; border-top: 1.5px solid var(--border-light); }
.btn { padding: 7px 18px; border-radius: 6px; font-size: 12px; font-weight: 700; border: none; cursor: pointer; }
.btn-primary { background: var(--accent); color: #fff; }
.btn-primary:disabled { opacity: 0.4; cursor: not-allowed; }
.btn-secondary { background: var(--surface); color: var(--text-secondary); border: 1.5px solid var(--border); }
.btn-sm { padding: 4px 10px; font-size: 11px; }

/* Back to projects */
.back-section { margin-top: 24px; }
.back-divider { border-top: 1.5px dashed var(--border); margin-bottom: 14px; }
.back-row { display: flex; align-items: center; gap: 12px; }
.back-hint { font-size: 12px; color: var(--text-muted); }

/* Preview panel */
.preview-panel {
  flex: 2; min-width: 300px; border-left: 1.5px solid var(--border);
  display: flex; flex-direction: column; overflow: hidden; background: var(--surface);
}
.preview-header {
  padding: 10px 14px; border-bottom: 1px solid var(--border-light);
  display: flex; align-items: center; gap: 8px;
}
.preview-title { font-size: 13px; font-weight: 700; }
.preview-path { font-size: 10px; color: var(--text-muted); font-family: var(--mono); flex: 1; }
.preview-body {
  flex: 1; overflow-y: auto; padding: 14px;
  font-size: 13px; line-height: 1.6; color: var(--text);
}
.preview-body :deep(h1) { font-size: 16px; font-weight: 700; margin: 12px 0 6px; border-bottom: 1px solid var(--border-light); padding-bottom: 4px; }
.preview-body :deep(h2) { font-size: 14px; font-weight: 700; margin: 10px 0 5px; }
.preview-body :deep(h3) { font-size: 13px; font-weight: 700; margin: 8px 0 4px; }
.preview-body :deep(p) { margin: 4px 0; }
.preview-body :deep(ul) { padding-left: 18px; margin: 4px 0; }
.preview-body :deep(li) { margin: 2px 0; }
.preview-body :deep(code) { background: var(--surface-alt); padding: 1px 4px; border-radius: 3px; font-family: var(--mono); font-size: 12px; }
.preview-body :deep(pre) { background: #1e293b; color: #e2e8f0; padding: 10px; border-radius: 6px; overflow-x: auto; margin: 6px 0; }
.preview-body :deep(pre code) { background: none; padding: 0; color: inherit; }
.preview-body :deep(strong) { font-weight: 700; }
.preview-body :deep(a) { color: var(--accent); text-decoration: underline; }
</style>
