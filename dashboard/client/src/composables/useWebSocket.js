import { ref, onMounted, onUnmounted } from 'vue'

export function useWebSocket() {
  const connected = ref(false)
  const lastMessage = ref(null)
  let ws = null
  const handlers = new Map()

  function connect() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
    ws = new WebSocket(`${protocol}//${window.location.host}/ws`)

    ws.onopen = () => { connected.value = true }
    ws.onclose = () => {
      connected.value = false
      // Reconnect after 3s
      setTimeout(connect, 3000)
    }
    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data)
        lastMessage.value = msg
        const handler = handlers.get(msg.type)
        if (handler) handler(msg.data)
      } catch (e) {}
    }
  }

  function on(type, handler) {
    handlers.set(type, handler)
  }

  onMounted(connect)
  onUnmounted(() => { if (ws) ws.close() })

  return { connected, lastMessage, on }
}
