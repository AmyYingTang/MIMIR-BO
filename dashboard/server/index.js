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
let registryDir = null;   // Where projects.yml lives
let activeWorkspace = null; // Currently loaded workspace path
let boConfig = null;
let projectState = null;

// === Registry (projects.yml) ===

function getDefaultRegistryDir() {
  // Default: BO_TOOLS_DIR/.workspaces or fallback to sample
  return process.env.BO_REGISTRY_DIR || path.join(__dirname, '..', '.workspaces');
}

function getRegistryPath() {
  if (!registryDir) registryDir = getDefaultRegistryDir();
  return path.join(registryDir, 'projects.yml');
}

function loadRegistry() {
  const p = getRegistryPath();
  if (!fs.existsSync(p)) return { registry_path: registryDir, projects: [] };
  try { return yaml.load(fs.readFileSync(p, 'utf8')) || { registry_path: registryDir, projects: [] }; }
  catch (e) { return { registry_path: registryDir, projects: [] }; }
}

function saveRegistry(reg) {
  const dir = registryDir || getDefaultRegistryDir();
  fs.mkdirSync(dir, { recursive: true });
  reg.registry_path = dir;
  fs.writeFileSync(path.join(dir, 'projects.yml'), yaml.dump(reg, { lineWidth: -1 }), 'utf8');
}

function enrichProject(proj) {
  // Read live phase from project-state.json
  const statePath = path.join(proj.workspace, 'project-state.json');
  const configPath = path.join(proj.workspace, 'bo-config.yml');
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

function setActiveWorkspace(wsPath) {
  activeWorkspace = wsPath;
  boConfig = null;
  projectState = null;
  if (wsPath) { loadConfig(); loadState(); }
}

function getWorkspacePath() {
  return activeWorkspace;
}

function loadConfig() {
  if (!activeWorkspace) { boConfig = null; return null; }
  const p = path.join(activeWorkspace, 'bo-config.yml');
  boConfig = fs.existsSync(p) ? yaml.load(fs.readFileSync(p, 'utf8')) : null;
  return boConfig;
}

function saveConfig(config) {
  if (!activeWorkspace) return;
  fs.mkdirSync(activeWorkspace, { recursive: true });
  fs.writeFileSync(path.join(activeWorkspace, 'bo-config.yml'), yaml.dump(config, { lineWidth: -1 }), 'utf8');
  boConfig = config;
}

function loadState() {
  if (!activeWorkspace) { projectState = null; return null; }
  const p = path.join(activeWorkspace, 'project-state.json');
  projectState = fs.existsSync(p) ? JSON.parse(fs.readFileSync(p, 'utf8')) : null;
  return projectState;
}

function saveState(state) {
  if (!activeWorkspace) return;
  fs.mkdirSync(activeWorkspace, { recursive: true });
  state.updated_at = new Date().toISOString();
  fs.writeFileSync(path.join(activeWorkspace, 'project-state.json'), JSON.stringify(state, null, 2), 'utf8');
  projectState = state;
  broadcastWs({ type: 'state_updated', data: state });
}

// Register/update project in projects.yml
function registerProject(name, workspace) {
  const reg = loadRegistry();
  const idx = reg.projects.findIndex(p => p.workspace === workspace);
  const entry = { name, workspace, phase: 'INIT', updated_at: new Date().toISOString(), pinned: false };
  if (idx >= 0) { reg.projects[idx] = { ...reg.projects[idx], name, updated_at: entry.updated_at }; }
  else { reg.projects.unshift(entry); }
  saveRegistry(reg);
}

function updateRegistryPhase(workspace, phase) {
  const reg = loadRegistry();
  const proj = reg.projects.find(p => p.workspace === workspace);
  if (proj) { proj.phase = phase; proj.updated_at = new Date().toISOString(); saveRegistry(reg); }
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
  if (!boConfig?.paths?.mimir || !activeWorkspace) return;
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
  fs.writeFileSync(path.join(activeWorkspace, 'skill-manifest.md'), lines.join('\n'), 'utf8');
}

// === File tree / design docs ===

function scanDirectory(dirPath, maxDepth = 3, depth = 0) {
  if (depth >= maxDepth || !fs.existsSync(dirPath)) return [];
  try {
    return fs.readdirSync(dirPath, { withFileTypes: true })
      .filter(e => (!e.name.startsWith('.') || ['.user','.workspace','.workspaces'].includes(e.name))
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

app.get('/api/health', (_, res) => res.json({ status: 'ok', workspace: activeWorkspace, registryDir }));

// Get project list
app.get('/api/projects', (_, res) => {
  const reg = loadRegistry();
  const projects = reg.projects.map(enrichProject);
  res.json({ registryDir, projects });
});

// Open/switch to a project
app.post('/api/projects/open', (req, res) => {
  const { workspace } = req.body;
  if (!workspace) return res.status(400).json({ error: 'workspace required' });
  if (!fs.existsSync(path.join(workspace, 'bo-config.yml'))) {
    return res.status(404).json({ error: '目录中没有 bo-config.yml，不是有效的项目 workspace' });
  }
  setActiveWorkspace(workspace);
  // Update registry (touch updated_at)
  const reg = loadRegistry();
  const proj = reg.projects.find(p => p.workspace === workspace);
  if (proj) { proj.updated_at = new Date().toISOString(); saveRegistry(reg); }
  else { registerProject(boConfig?.instance_name || path.basename(workspace), workspace); }
  res.json({ success: true, config: boConfig, state: projectState });
});

// Create new project workspace
app.post('/api/projects/create', (req, res) => {
  const { workspace } = req.body;
  if (!workspace) return res.status(400).json({ error: 'workspace required' });
  fs.mkdirSync(workspace, { recursive: true });
  setActiveWorkspace(workspace);
  res.json({ success: true });
});

// Close current project (go back to selector)
app.post('/api/projects/close', (_, res) => {
  setActiveWorkspace(null);
  res.json({ success: true });
});

// Remove from registry (not delete files)
app.post('/api/projects/unregister', (req, res) => {
  const { workspace } = req.body;
  const reg = loadRegistry();
  reg.projects = reg.projects.filter(p => p.workspace !== workspace);
  saveRegistry(reg);
  res.json({ success: true });
});

// Delete project (remove files + unregister)
app.post('/api/projects/delete', (req, res) => {
  const { workspace } = req.body;
  if (!workspace) return res.status(400).json({ error: 'workspace required' });
  // Unregister
  const reg = loadRegistry();
  reg.projects = reg.projects.filter(p => p.workspace !== workspace);
  saveRegistry(reg);
  // Delete workspace files
  try {
    for (const f of ['bo-config.yml', 'project-state.json', 'skill-manifest.md']) {
      const fp = path.join(workspace, f);
      if (fs.existsSync(fp)) fs.unlinkSync(fp);
    }
    // Try to remove dir if empty
    try { fs.rmdirSync(workspace); } catch (e) {}
  } catch (e) {}
  if (activeWorkspace === workspace) setActiveWorkspace(null);
  res.json({ success: true });
});

// Pin/unpin project
app.post('/api/projects/pin', (req, res) => {
  const { workspace, pinned } = req.body;
  const reg = loadRegistry();
  const proj = reg.projects.find(p => p.workspace === workspace);
  if (proj) { proj.pinned = pinned; saveRegistry(reg); }
  res.json({ success: true });
});

// Update registry dir
app.post('/api/projects/registry-dir', (req, res) => {
  const { dir } = req.body;
  if (!dir) return res.status(400).json({ error: 'dir required' });
  registryDir = dir;
  fs.mkdirSync(dir, { recursive: true });
  res.json({ success: true, registryDir: dir });
});

// === API: Active project ===

app.get('/api/active', (_, res) => {
  res.json({ workspace: activeWorkspace, hasProject: !!boConfig });
});

app.get('/api/config', (_, res) => {
  loadConfig();
  boConfig ? res.json(boConfig) : res.status(404).json({ error: 'Not initialized' });
});

app.post('/api/config', (req, res) => {
  if (!activeWorkspace) return res.status(400).json({ error: 'No active project' });
  try {
    saveConfig(req.body);
    if (req.body.paths?.mimir) generateSkillManifest();
    loadState();
    if (!projectState) {
      saveState({
        project: req.body.instance_name || 'untitled',
        current_phase: 'DESIGN',
        phases: {
          INIT: { status: 'completed' },
          DESIGN: { status: 'in_progress', checklist: {} },
          BUILD: { status: 'pending', import_check: 'pending', task_decompose: 'pending', modules: {}, checkpoint: 'pending' },
          VERIFY: { status: 'pending' },
          SHIP: { status: 'pending' },
        },
      });
    }
    // Update registry
    registerProject(req.body.instance_name || 'untitled', activeWorkspace);
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
    if (activeWorkspace) updateRegistryPhase(activeWorkspace, req.body.current_phase);
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
registryDir = getDefaultRegistryDir();
server.listen(PORT, () => {
  console.log(`\n  🚀 MIMIR-BO Dashboard Server`);
  console.log(`  📡 http://localhost:${PORT}/api`);
  console.log(`  📋 Registry: ${getRegistryPath()}\n`);
});
