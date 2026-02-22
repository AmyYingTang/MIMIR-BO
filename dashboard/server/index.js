const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');
const { WebSocketServer } = require('ws');
const http = require('http');

const app = express();
const server = http.createServer(app);
const PORT = 3001;

app.use(cors());
app.use(express.json());

// === Multi-project state ===
let registryPath = null;       // Full path to projects.yml
let activeProjectDir = null;   // Currently loaded project directory
let boConfig = null;
let projectState = null;

// Helper: get .mimir/ workspace path from project dir
function getMimirDir(projectDir) {
  return path.join(projectDir, '.mimir');
}

// === Registry (projects.yml) ===

function getDefaultRegistryPath() {
  // Default: {BO tools dir}/projects.yml
  return process.env.BO_REGISTRY_PATH || path.join(__dirname, '..', 'projects.yml');
}

function getRegistryPath() {
  if (!registryPath) registryPath = getDefaultRegistryPath();
  return registryPath;
}

function getRegistryDir() {
  return path.dirname(getRegistryPath());
}

function loadRegistry() {
  const p = getRegistryPath();
  if (!fs.existsSync(p)) return { projects: [] };
  try { return yaml.load(fs.readFileSync(p, 'utf8')) || { projects: [] }; }
  catch (e) { return { projects: [] }; }
}

function saveRegistry(reg) {
  const dir = path.dirname(getRegistryPath());
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(getRegistryPath(), yaml.dump(reg, { lineWidth: -1 }), 'utf8');
}

function enrichProject(proj) {
  // Read live phase from .mimir/state.json
  const mimirDir = getMimirDir(proj.project_dir);
  const statePath = path.join(mimirDir, 'state.json');
  const configPath = path.join(mimirDir, 'config.yml');
  let phase = proj.phase || 'INIT';
  let updatedAt = proj.updated_at;
  let exists = fs.existsSync(configPath);
  if (fs.existsSync(statePath)) {
    try {
      const st = JSON.parse(fs.readFileSync(statePath, 'utf8'));
      phase = st.current_phase || phase;
      updatedAt = st.updated_at || updatedAt;
    } catch (e) {}
  }
  return { ...proj, phase, updated_at: updatedAt, exists };
}

// === Active project ===

function setActiveProject(projectDir) {
  activeProjectDir = projectDir;
  boConfig = null;
  projectState = null;
  if (projectDir) { loadConfig(); loadState(); }
}

function getWorkspacePath() {
  return activeProjectDir ? getMimirDir(activeProjectDir) : null;
}

function loadConfig() {
  if (!activeProjectDir) { boConfig = null; return null; }
  const p = path.join(getMimirDir(activeProjectDir), 'config.yml');
  boConfig = fs.existsSync(p) ? yaml.load(fs.readFileSync(p, 'utf8')) : null;
  return boConfig;
}

function saveConfig(config) {
  if (!activeProjectDir) return;
  const mimirDir = getMimirDir(activeProjectDir);
  fs.mkdirSync(mimirDir, { recursive: true });
  // Also create subdirectories
  for (const sub of ['conventions', 'prompts', 'reports']) {
    fs.mkdirSync(path.join(mimirDir, sub), { recursive: true });
  }
  fs.writeFileSync(path.join(mimirDir, 'config.yml'), yaml.dump(config, { lineWidth: -1 }), 'utf8');
  boConfig = config;
}

function loadState() {
  if (!activeProjectDir) { projectState = null; return null; }
  const p = path.join(getMimirDir(activeProjectDir), 'state.json');
  projectState = fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, 'utf8')) : null;
  return projectState;
}

function saveState(state) {
  if (!activeProjectDir) return;
  const mimirDir = getMimirDir(activeProjectDir);
  fs.mkdirSync(mimirDir, { recursive: true });
  state.updated_at = new Date().toISOString();
  fs.writeFileSync(path.join(mimirDir, 'state.json'), JSON.stringify(state, null, 2), 'utf8');
  projectState = state;
  broadcastWs({ type: 'state_updated', data: state });
}

// Register/update project in projects.yml
function registerProject(name, projectDir) {
  const reg = loadRegistry();
  const idx = reg.projects.findIndex(p => p.project_dir === projectDir);
  const entry = { name, project_dir: projectDir, phase: 'INIT', updated_at: new Date().toISOString(), pinned: false };
  if (idx >= 0) { reg.projects[idx] = { ...reg.projects[idx], name, updated_at: entry.updated_at }; }
  else { reg.projects.unshift(entry); }
  saveRegistry(reg);
}

function updateRegistryPhase(projectDir, phase) {
  const reg = loadRegistry();
  const proj = reg.projects.find(p => p.project_dir === projectDir);
  if (proj) { proj.phase = phase; proj.updated_at = new Date().toISOString(); saveRegistry(reg); }
}

// === CLAUDE.md generation ===

function generateClaudeMd(config, state) {
  if (!activeProjectDir) return;
  const currentPhase = state?.current_phase || 'INIT';
  const currentModule = Object.entries(state?.phases?.BUILD?.modules || {})
    .find(([, m]) => m.status === 'in_progress');
  const moduleId = currentModule ? currentModule[0] : null;
  const moduleStep = currentModule ? currentModule[1].sub_step : null;

  const lines = [
    `# Project: ${config.instance_name || 'Untitled'}`,
    '# 由 MIMIR-BO 自动生成，请勿手动编辑',
    `# 最后更新: ${new Date().toISOString()}`,
    '',
    '## 项目规范',
    '',
    '执行任务前，按需读取以下文件：',
    '- 📋 MIMIR Skill Manifest: .mimir/skill-manifest.md',
    '- 📐 Convention Snapshot: .mimir/conventions/latest.md',
    '',
    'Skill Manifest 中列出了本项目需要遵循的所有 MIMIR 规范文件路径。',
    '按当前任务的相关性选择性读取，不需要全部加载。',
    'Convention Snapshot 记录了前序模块中提取的代码约定，新模块必须遵循。',
    '',
    '## 当前任务',
    '',
    `当前阶段: ${currentPhase}`,
  ];

  if (moduleId) {
    lines.push(`当前模块: ${moduleId}`);
    lines.push(`模块状态: ${moduleStep || 'pending'}`);
    lines.push('');
    lines.push('### 模块 Prompt');
    lines.push(`读取并执行: .mimir/prompts/${moduleId}/${moduleId}-prompt.md`);
  }

  // Design docs reference
  const designDir = path.join(activeProjectDir, 'docs', 'design');
  if (fs.existsSync(designDir)) {
    lines.push('');
    lines.push('### 设计文档参考');
    try {
      const files = fs.readdirSync(designDir).filter(f => f.endsWith('.md'));
      files.forEach(f => lines.push(`- docs/design/${f}`));
    } catch (e) {}
  }

  lines.push('');
  lines.push('## Git 规范');
  if (moduleId) {
    lines.push(`- commit message: feat(${moduleId}): <描述>`);
  } else {
    lines.push('- commit message: feat(<module>): <描述>');
  }
  lines.push('- 不要修改不属于当前模块的文件');
  lines.push('');
  lines.push('## 用户自定义指令');
  lines.push('如有个人编码偏好，请同时读取: .claude-user.md');
  lines.push('');

  fs.writeFileSync(path.join(activeProjectDir, 'CLAUDE.md'), lines.join('\n'), 'utf8');
}

// === Language-aware MIMIR path ===

function getMimirSkillsBase(mimirPath, language) {
  const lang = language === 'bilingual' ? 'zh' : (language || 'zh');
  return path.join(mimirPath, lang, 'skills');
}

// === Full MIMIR content scanning ===

function scanMimirContent(basePath) {
  if (!basePath || !fs.existsSync(basePath)) return { files: [], dirs: [], tree: [], totalFiles: 0, totalSize: 0 };
  const files = []; const dirs = [];
  function walk(dir, relDir) {
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return []; }
    const children = [];
    for (const e of entries) {
      if (e.name.startsWith('.') || ['node_modules','__pycache__','.git','.venv'].includes(e.name)) continue;
      const full = path.join(dir, e.name);
      const rel = relDir ? `${relDir}/${e.name}` : e.name;
      if (e.isDirectory()) {
        const sub = walk(full, rel);
        if (sub.length > 0 || e.name === 'templates') {
          dirs.push({ name: e.name, path: full, relativePath: rel });
          children.push({ name: e.name, path: full, relativePath: rel, isDirectory: true, children: sub });
        }
      } else if (e.name.endsWith('.md') || e.name.endsWith('.yml') || e.name.endsWith('.yaml')) {
        let size = 0;
        try { size = fs.statSync(full).size; } catch (e) {}
        files.push({ name: e.name, path: full, relativePath: rel, size });
        children.push({ name: e.name, path: full, relativePath: rel, isDirectory: false, size });
      }
    }
    return children.sort((a, b) => (a.isDirectory === b.isDirectory) ? a.name.localeCompare(b.name) : a.isDirectory ? -1 : 1);
  }
  const tree = walk(basePath, '');
  return { files, dirs, tree, totalFiles: files.length, totalSize: files.reduce((s, f) => s + f.size, 0) };
}

function scanFullMimir(mimirPath, language) {
  const lang = language === 'bilingual' ? 'zh' : (language || 'zh');
  return scanMimirContent(path.join(mimirPath, lang));
}

function scanUserDirs(dirPaths) {
  return (dirPaths || []).filter(p => fs.existsSync(p)).map(p => ({ path: p, name: path.basename(p), ...scanMimirContent(p) }));
}

function validateSkillDir(dirPath) {
  if (!dirPath || !fs.existsSync(dirPath)) return { valid: false, reason: '目录不存在' };
  try {
    if (!fs.readdirSync(dirPath).some(f => f.endsWith('.md'))) return { valid: false, reason: '目录中没有 .md 文件' };
  } catch (e) { return { valid: false, reason: '无法读取目录' }; }
  return { valid: true, name: path.basename(dirPath), path: dirPath };
}

// === Skill Manifest ===

function generateSkillManifest() {
  if (!boConfig?.paths?.mimir || !activeProjectDir) return;
  const mimirDir = getMimirDir(activeProjectDir);
  const lang = boConfig.language === 'bilingual' ? 'zh' : (boConfig.language || 'zh');
  const base = path.join(boConfig.paths.mimir, lang);
  const scan = scanMimirContent(base);
  const lines = [
    '# MIMIR Skill Manifest', '# 自动生成，请勿手动编辑',
    `# 生成时间: ${new Date().toISOString()}`,
    `# 项目: ${boConfig.instance_name || ''} | 类型: ${boConfig.project_type || ''} | 语言: ${boConfig.language || 'zh'}`,
    `# MIMIR 路径: ${base}`, '',
    '本项目加载了以下 MIMIR 内容，执行任务时根据当前阶段按需读取。', '',
    `## MIMIR 内容（${scan.totalFiles} 个文件，${(scan.totalSize / 1024).toFixed(1)}KB）`, '',
    '| # | 文件路径 | 大小 |', '|---|---------|------|',
  ];
  scan.files.forEach((f, i) => lines.push(`| ${i+1} | ${f.relativePath} | ${(f.size / 1024).toFixed(1)}KB |`));
  const userDirs = boConfig.user_content_dirs || [];
  if (userDirs.length > 0) {
    lines.push('', '## 用户自定义内容', '', '| # | 文件路径 | 大小 |', '|---|---------|------|');
    let idx = 1;
    for (const dir of userDirs) { scanMimirContent(dir).files.forEach(f => lines.push(`| ${idx++} | ${f.path} | ${(f.size / 1024).toFixed(1)}KB |`)); }
  }
  lines.push('', '## 使用说明', '', '执行任务前，根据当前任务阶段和内容相关性，选择性读取上述文件。', '不需要全部读取，按需加载以节省 context window。', '');
  fs.writeFileSync(path.join(mimirDir, 'skill-manifest.md'), lines.join('\n'), 'utf8');
}

// === File tree / design docs ===

function scanDirectory(dirPath, maxDepth = 3, depth = 0) {
  if (depth >= maxDepth || !fs.existsSync(dirPath)) return [];
  try {
    return fs.readdirSync(dirPath, { withFileTypes: true })
      .filter(e => (!e.name.startsWith('.') || ['.mimir','.claude-user.md'].includes(e.name))
        && !['node_modules','__pycache__','.git','.venv'].includes(e.name))
      .map(e => {
        const full = path.join(dirPath, e.name);
        const item = { name: e.name, path: full, isDirectory: e.isDirectory() };
        if (e.isDirectory()) item.children = scanDirectory(full, maxDepth, depth + 1);
        return item;
      })
      .sort((a, b) => (a.isDirectory === b.isDirectory) ? a.name.localeCompare(b.name) : a.isDirectory ? -1 : 1);
  } catch (e) { return []; }
}

function scanDesignDocs(projectPath) {
  if (!projectPath) return [];
  const types = [
    { id: 'prd', label: 'PRD 产品需求文档', patterns: ['prd','product-requirements'] },
    { id: 'api_design', label: 'API 设计', patterns: ['api-design','api-spec'] },
    { id: 'database_design', label: '数据库设计', patterns: ['database-design','db-design'] },
    { id: 'state_machines', label: '状态机定义', patterns: ['state-machine','state-machines'] },
    { id: 'business_rules', label: '业务规则', patterns: ['business-rules','business-rule'] },
    { id: 'security_arch', label: '安全架构', patterns: ['security-arch','security-architecture'] },
    { id: 'tech_stack', label: '技术选型', patterns: ['tech-stack','tech-selection'] },
  ];
  const docsDir = path.join(projectPath, 'docs', 'design');
  return types.map(dt => {
    let found = null;
    if (fs.existsSync(docsDir)) {
      try {
        const files = fs.readdirSync(docsDir);
        for (const p of dt.patterns) { const m = files.find(f => f.toLowerCase().includes(p) && f.endsWith('.md')); if (m) { found = path.join('docs','design',m); break; } }
      } catch (e) {}
    }
    return { id: dt.id, label: dt.label, status: found ? 'found' : 'missing', path: found };
  });
}

// === API: Project Registry ===

app.get('/api/health', (_, res) => res.json({ status: 'ok', projectDir: activeProjectDir, registryPath: getRegistryPath() }));

// Get project list
app.get('/api/projects', (_, res) => {
  const reg = loadRegistry();
  const projects = reg.projects.map(enrichProject);
  res.json({ registryDir: getRegistryDir(), projects });
});

// Open/switch to a project
app.post('/api/projects/open', (req, res) => {
  const { project_dir } = req.body;
  if (!project_dir) return res.status(400).json({ error: 'project_dir required' });
  const mimirDir = getMimirDir(project_dir);
  if (!fs.existsSync(path.join(mimirDir, 'config.yml'))) {
    return res.status(404).json({ error: '目录中没有 .mimir/config.yml，不是有效的 MIMIR 项目' });
  }
  setActiveProject(project_dir);
  // Update registry (touch updated_at)
  const reg = loadRegistry();
  const proj = reg.projects.find(p => p.project_dir === project_dir);
  if (proj) { proj.updated_at = new Date().toISOString(); saveRegistry(reg); }
  else { registerProject(boConfig?.instance_name || path.basename(project_dir), project_dir); }
  res.json({ success: true, config: boConfig, state: projectState });
});

// Create new project
app.post('/api/projects/create', (req, res) => {
  const { project_dir } = req.body;
  if (!project_dir) return res.status(400).json({ error: 'project_dir required' });
  const mimirDir = getMimirDir(project_dir);
  fs.mkdirSync(mimirDir, { recursive: true });
  setActiveProject(project_dir);
  res.json({ success: true });
});

// Close current project (go back to selector)
app.post('/api/projects/close', (_, res) => {
  setActiveProject(null);
  res.json({ success: true });
});

// Remove from registry (not delete files)
app.post('/api/projects/unregister', (req, res) => {
  const { project_dir } = req.body;
  const reg = loadRegistry();
  reg.projects = reg.projects.filter(p => p.project_dir !== project_dir);
  saveRegistry(reg);
  res.json({ success: true });
});

// Delete project (remove .mimir/ + CLAUDE.md + unregister)
app.post('/api/projects/delete', (req, res) => {
  const { project_dir } = req.body;
  if (!project_dir) return res.status(400).json({ error: 'project_dir required' });
  // Unregister
  const reg = loadRegistry();
  reg.projects = reg.projects.filter(p => p.project_dir !== project_dir);
  saveRegistry(reg);
  // Delete .mimir/ directory
  const mimirDir = getMimirDir(project_dir);
  try { fs.rmSync(mimirDir, { recursive: true, force: true }); } catch (e) {}
  // Delete CLAUDE.md
  try { const cm = path.join(project_dir, 'CLAUDE.md'); if (fs.existsSync(cm)) fs.unlinkSync(cm); } catch (e) {}
  if (activeProjectDir === project_dir) setActiveProject(null);
  res.json({ success: true });
});

// Pin/unpin project
app.post('/api/projects/pin', (req, res) => {
  const { project_dir, pinned } = req.body;
  const reg = loadRegistry();
  const proj = reg.projects.find(p => p.project_dir === project_dir);
  if (proj) { proj.pinned = pinned; saveRegistry(reg); }
  res.json({ success: true });
});

// Update registry path
app.post('/api/projects/registry-dir', (req, res) => {
  const { dir } = req.body;
  if (!dir) return res.status(400).json({ error: 'dir required' });
  registryPath = path.join(dir, 'projects.yml');
  fs.mkdirSync(dir, { recursive: true });
  res.json({ success: true, registryDir: dir });
});

// === API: Active project ===

app.get('/api/active', (_, res) => {
  res.json({ project_dir: activeProjectDir, hasProject: !!boConfig });
});

app.get('/api/config', (_, res) => {
  loadConfig();
  boConfig ? res.json(boConfig) : res.status(404).json({ error: 'Not initialized' });
});

app.post('/api/config', (req, res) => {
  if (!activeProjectDir) return res.status(400).json({ error: 'No active project' });
  try {
    saveConfig(req.body);
    if (req.body.paths?.mimir) generateSkillManifest();
    loadState();
    if (!projectState) {
      const initialState = {
        project: req.body.instance_name || 'untitled',
        current_phase: 'DESIGN',
        phases: {
          INIT: { status: 'completed' },
          DESIGN: { status: 'in_progress', checklist: {} },
          BUILD: { status: 'pending', import_check: 'pending', task_decompose: 'pending', modules: {}, checkpoint: 'pending' },
          VERIFY: { status: 'pending' },
          SHIP: { status: 'pending' },
        },
      };
      saveState(initialState);
      // Generate CLAUDE.md on first init
      generateClaudeMd(req.body, initialState);
    }
    // Update registry
    registerProject(req.body.instance_name || 'untitled', activeProjectDir);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.get('/api/state', (_, res) => {
  loadState();
  res.json(projectState || {
    project: null, current_phase: 'INIT',
    phases: { INIT: { status: 'in_progress' }, DESIGN: { status: 'locked' }, BUILD: { status: 'locked', modules: {} }, VERIFY: { status: 'locked' }, SHIP: { status: 'locked' } },
  });
});

app.post('/api/state', (req, res) => {
  try {
    saveState(req.body);
    if (activeProjectDir) updateRegistryPhase(activeProjectDir, req.body.current_phase);
    res.json({ success: true });
  } catch (e) { res.status(500).json({ error: e.message }); }
});

app.patch('/api/state', (req, res) => {
  loadState();
  if (!projectState) return res.status(404).json({ error: 'No state' });
  try { const m = deepMerge(projectState, req.body); saveState(m); res.json({ success: true, state: m }); }
  catch (e) { res.status(500).json({ error: e.message }); }
});

// === API: Files ===

app.get('/api/files/tree', (req, res) => {
  const p = req.query.path;
  res.json(p ? { path: p, tree: scanDirectory(p, 3) } : { path: null, tree: [] });
});

app.get('/api/files/read', (req, res) => {
  const p = req.query.path;
  if (!p) return res.status(400).json({ error: 'path required' });
  try { res.json({ path: p, content: fs.readFileSync(p, 'utf8') }); }
  catch (e) { res.status(404).json({ error: 'File not found' }); }
});

// === API: Scanning ===

app.get('/api/scan/mimir-content', (req, res) => {
  const { mimirPath, language } = req.query;
  res.json(scanFullMimir(mimirPath, language));
});

app.get('/api/scan/user-dirs', (req, res) => {
  const dirs = req.query.dirs ? JSON.parse(req.query.dirs) : [];
  res.json(scanUserDirs(dirs));
});

app.get('/api/scan/design-docs', (_, res) => { loadConfig(); res.json(scanDesignDocs(boConfig?.paths?.project)); });
app.get('/api/validate-skill-dir', (req, res) => res.json(validateSkillDir(req.query.path)));
app.get('/api/validate-path', (req, res) => {
  const p = req.query.path;
  if (!p) return res.json({ valid: false });
  const exists = fs.existsSync(p);
  res.json({ valid: exists, isDirectory: exists && fs.statSync(p).isDirectory() });
});

app.post('/api/skills/regenerate-manifest', (_, res) => {
  loadConfig();
  if (!boConfig) return res.status(404).json({ error: 'Not initialized' });
  try { generateSkillManifest(); res.json({ success: true }); }
  catch (e) { res.status(500).json({ error: e.message }); }
});

// Regenerate CLAUDE.md (triggered on sub-step changes)
app.post('/api/claude-md/regenerate', (_, res) => {
  loadConfig(); loadState();
  if (!boConfig || !projectState) return res.status(404).json({ error: 'Not initialized' });
  try { generateClaudeMd(boConfig, projectState); res.json({ success: true }); }
  catch (e) { res.status(500).json({ error: e.message }); }
});

// === API: OS folder picker ===

app.get('/api/pick-folder', (req, res) => {
  const { execSync } = require('child_process');
  const prompt = req.query.prompt || '选择目录';
  try {
    let selected = '';
    if (process.platform === 'darwin') {
      selected = execSync(`osascript -e 'set f to choose folder with prompt "${prompt}"' -e 'return POSIX path of f'`, { encoding: 'utf8', timeout: 60000 }).trim();
    } else if (process.platform === 'linux') {
      selected = execSync(`zenity --file-selection --directory --title="${prompt}" 2>/dev/null`, { encoding: 'utf8', timeout: 60000 }).trim();
    } else if (process.platform === 'win32') {
      selected = execSync(`powershell -Command "Add-Type -AssemblyName System.Windows.Forms; $f = New-Object System.Windows.Forms.FolderBrowserDialog; $f.Description = '${prompt}'; if ($f.ShowDialog() -eq 'OK') { $f.SelectedPath }"`, { encoding: 'utf8', timeout: 60000 }).trim();
    }
    if (selected && selected !== '') {
      if (selected.endsWith('/') && selected !== '/') selected = selected.slice(0, -1);
      res.json({ selected, cancelled: false });
    } else { res.json({ selected: null, cancelled: true }); }
  } catch (e) { res.json({ selected: null, cancelled: true }); }
});

// === WebSocket ===
const wss = new WebSocketServer({ server, path: '/ws' });
const wsClients = new Set();
wss.on('connection', ws => { wsClients.add(ws); ws.on('close', () => wsClients.delete(ws)); });
function broadcastWs(msg) { const d = JSON.stringify(msg); for (const c of wsClients) if (c.readyState === 1) c.send(d); }

function deepMerge(t, s) {
  const r = { ...t };
  for (const k of Object.keys(s)) {
    if (s[k] && typeof s[k] === 'object' && !Array.isArray(s[k])) r[k] = deepMerge(r[k] || {}, s[k]);
    else r[k] = s[k];
  }
  return r;
}

// Startup
registryPath = getDefaultRegistryPath();
server.listen(PORT, () => {
  console.log(`\n  🚀 MIMIR-BO Dashboard Server`);
  console.log(`  📡 http://localhost:${PORT}/api`);
  console.log(`  📋 Registry: ${getRegistryPath()}\n`);
});
