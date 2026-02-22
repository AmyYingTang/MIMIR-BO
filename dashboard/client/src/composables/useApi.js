import { ref } from 'vue'

const BASE = '/api'

async function fetchJson(url, options = {}) {
  const res = await fetch(BASE + url, {
    headers: { 'Content-Type': 'application/json' },
    ...options,
  })
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: res.statusText }))
    throw new Error(err.error || res.statusText)
  }
  return res.json()
}

export function useApi() {
  const loading = ref(false)
  const error = ref(null)

  async function call(fn) {
    loading.value = true
    error.value = null
    try { return await fn() }
    catch (e) { error.value = e.message; throw e }
    finally { loading.value = false }
  }

  return {
    loading, error,

    // Project registry
    getProjects: () => call(() => fetchJson('/projects')),
    openProject: (workspace) => call(() => fetchJson('/projects/open', { method: 'POST', body: JSON.stringify({ workspace }) })),
    createProject: (workspace) => call(() => fetchJson('/projects/create', { method: 'POST', body: JSON.stringify({ workspace }) })),
    closeProject: () => call(() => fetchJson('/projects/close', { method: 'POST' })),
    unregisterProject: (workspace) => call(() => fetchJson('/projects/unregister', { method: 'POST', body: JSON.stringify({ workspace }) })),
    deleteProject: (workspace) => call(() => fetchJson('/projects/delete', { method: 'POST', body: JSON.stringify({ workspace }) })),
    pinProject: (workspace, pinned) => call(() => fetchJson('/projects/pin', { method: 'POST', body: JSON.stringify({ workspace, pinned }) })),
    setRegistryDir: (dir) => call(() => fetchJson('/projects/registry-dir', { method: 'POST', body: JSON.stringify({ dir }) })),
    getActive: () => call(() => fetchJson('/active')),

    // Config
    getConfig: () => call(() => fetchJson('/config')),
    saveConfig: (config) => call(() => fetchJson('/config', { method: 'POST', body: JSON.stringify(config) })),

    // State
    getState: () => call(() => fetchJson('/state')),
    saveState: (state) => call(() => fetchJson('/state', { method: 'POST', body: JSON.stringify(state) })),
    patchState: (patch) => call(() => fetchJson('/state', { method: 'PATCH', body: JSON.stringify(patch) })),

    // File tree
    getFileTree: (dirPath) => call(() => fetchJson(`/files/tree?path=${encodeURIComponent(dirPath)}`)),
    readFile: (filePath) => call(() => fetchJson(`/files/read?path=${encodeURIComponent(filePath)}`)),

    // Native OS folder picker
    pickFolder: (prompt) => call(() => fetchJson(`/pick-folder?prompt=${encodeURIComponent(prompt || '选择目录')}`)),

    // Scanning
    scanDesignDocs: () => call(() => fetchJson('/scan/design-docs')),
    scanMimirContent: (mimirPath, language) => call(() =>
      fetchJson(`/scan/mimir-content?mimirPath=${encodeURIComponent(mimirPath || '')}&language=${encodeURIComponent(language || 'zh')}`)
    ),
    scanUserDirs: (dirs) => call(() =>
      fetchJson(`/scan/user-dirs?dirs=${encodeURIComponent(JSON.stringify(dirs || []))}`)
    ),
    validateSkillDir: (dirPath) => call(() => fetchJson(`/validate-skill-dir?path=${encodeURIComponent(dirPath)}`)),
    validatePath: (dirPath) => call(() => fetchJson(`/validate-path?path=${encodeURIComponent(dirPath)}`)),

    // Skills
    regenerateManifest: () => call(() => fetchJson('/skills/regenerate-manifest', { method: 'POST' })),
  }
}
