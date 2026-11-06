import type { MachineStatus } from '../domain/models'

// Synchronous SHA-256 implementation so proof vectors and key derivation can be pure and synchronous.
const K = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
])

export function sha256(input: Uint8Array | string): Uint8Array {
  const bytes = typeof input === 'string' ? new TextEncoder().encode(input) : input
  const len = bytes.length
  const bitLen = len * 8
  const padLen = (len + 9 + 63) & ~63
  const buf = new Uint8Array(padLen)
  buf.set(bytes)
  buf[len] = 0x80
  const view = new DataView(buf.buffer)
  view.setBigUint64(padLen - 8, BigInt(bitLen), false)

  let h0 = 0x6a09e667
  let h1 = 0xbb67ae85
  let h2 = 0x3c6ef372
  let h3 = 0xa54ff53a
  let h4 = 0x510e527f
  let h5 = 0x9b05688c
  let h6 = 0x1f83d9ab
  let h7 = 0x5be0cd19

  const w = new Uint32Array(64)
  for (let i = 0; i < padLen; i += 64) {
    for (let t = 0; t < 16; t++) {
      w[t] = view.getUint32(i + t * 4, false)
    }
    for (let t = 16; t < 64; t++) {
      const s0 = ((w[t - 15] >>> 7) | (w[t - 15] << 25)) ^ ((w[t - 15] >>> 18) | (w[t - 15] << 14)) ^ (w[t - 15] >>> 3)
      const s1 = ((w[t - 2] >>> 17) | (w[t - 2] << 15)) ^ ((w[t - 2] >>> 19) | (w[t - 2] << 13)) ^ (w[t - 2] >>> 10)
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) | 0
    }

    let a = h0
    let b = h1
    let c = h2
    let d = h3
    let e = h4
    let f = h5
    let g = h6
    let h = h7

    for (let t = 0; t < 64; t++) {
      const S1 = ((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7))
      const ch = (e & f) ^ (~e & g)
      const temp1 = (h + S1 + ch + K[t] + w[t]) | 0
      const S0 = ((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10))
      const maj = (a & b) ^ (a & c) ^ (b & c)
      const temp2 = (S0 + maj) | 0

      h = g
      g = f
      f = e
      e = (d + temp1) | 0
      d = c
      c = b
      b = a
      a = (temp1 + temp2) | 0
    }

    h0 = (h0 + a) | 0
    h1 = (h1 + b) | 0
    h2 = (h2 + c) | 0
    h3 = (h3 + d) | 0
    h4 = (h4 + e) | 0
    h5 = (h5 + f) | 0
    h6 = (h6 + g) | 0
    h7 = (h7 + h) | 0
  }

  const out = new Uint8Array(32)
  const outView = new DataView(out.buffer)
  outView.setUint32(0, h0, false)
  outView.setUint32(4, h1, false)
  outView.setUint32(8, h2, false)
  outView.setUint32(12, h3, false)
  outView.setUint32(16, h4, false)
  outView.setUint32(20, h5, false)
  outView.setUint32(24, h6, false)
  outView.setUint32(28, h7, false)
  return out
}

export function base64Encode(bytes: Uint8Array): string {
  let binary = ''
  for (let i = 0; i < bytes.length; i++) {
    binary += String.fromCharCode(bytes[i])
  }
  return btoa(binary)
}

export function base64Decode(str: string): Uint8Array {
  const binary = atob(str.trim())
  const bytes = new Uint8Array(binary.length)
  for (let i = 0; i < binary.length; i++) {
    bytes[i] = binary.charCodeAt(i)
  }
  return bytes
}

/** Converts an IEEE P1363 raw ECDSA signature (64 bytes r || s) to ASN.1 DER format. */
export function p1363ToDer(p1363: Uint8Array): Uint8Array {
  if (p1363.length !== 64) return p1363
  const r = p1363.slice(0, 32)
  const s = p1363.slice(32, 64)

  function encodeInt(bytes: Uint8Array): number[] {
    let start = 0
    while (start < bytes.length - 1 && bytes[start] === 0) start++
    const trimmed = bytes.slice(start)
    if (trimmed[0] & 0x80) {
      return [0x02, trimmed.length + 1, 0x00, ...trimmed]
    }
    return [0x02, trimmed.length, ...trimmed]
  }

  const rEncoded = encodeInt(r)
  const sEncoded = encodeInt(s)
  const totalLen = rEncoded.length + sEncoded.length
  return Uint8Array.from([0x30, totalLen, ...rEncoded, ...sEncoded])
}

/** Converts an ASN.1 DER ECDSA signature to raw IEEE P1363 (64 bytes r || s) format. */
export function derToP1363(der: Uint8Array): Uint8Array {
  if (der.length === 64) return der
  let offset = 2
  if (der[0] !== 0x30) throw new Error('Invalid DER signature')
  if (der[1] & 0x80) offset += der[1] & 0x7f

  function decodeInt(pos: number): { val: Uint8Array; nextPos: number } {
    if (der[pos] !== 0x02) throw new Error('Expected integer tag')
    const len = der[pos + 1]
    let intBytes = der.slice(pos + 2, pos + 2 + len)
    if (intBytes.length > 32 && intBytes[0] === 0x00) {
      intBytes = intBytes.slice(1)
    }
    const out = new Uint8Array(32)
    out.set(intBytes, 32 - intBytes.length)
    return { val: out, nextPos: pos + 2 + len }
  }

  const rDecoded = decodeInt(offset)
  const sDecoded = decodeInt(rDecoded.nextPos)
  const p1363 = new Uint8Array(64)
  p1363.set(rDecoded.val, 0)
  p1363.set(sDecoded.val, 32)
  return p1363
}

export interface InstallationKey {
  installationId: string
  privateKeyPkcs8: Uint8Array
  secret: Uint8Array
  publicKeyDer: Uint8Array
}

export const LaMarzoccoAuth = {
  secret(installationId: string, publicKeyDer: Uint8Array): Uint8Array {
    const idHash = base64Encode(sha256(installationId))
    const pubB64 = base64Encode(publicKeyDer)
    const triple = `${installationId}.${pubB64}.${idHash}`
    return sha256(triple)
  },

  baseString(installationId: string, publicKeyDer: Uint8Array): string {
    const pubHash = base64Encode(sha256(publicKeyDer))
    return `${installationId}.${pubHash}`
  },

  proof(input: string, secret: Uint8Array): string {
    if (secret.length !== 32) return ''
    const work = new Uint8Array(secret)
    const inputBytes = new TextEncoder().encode(input)
    for (let i = 0; i < inputBytes.length; i++) {
      const byteVal = inputBytes[i]
      const index = byteVal % 32
      const shift = work[(index + 1) % 32] & 7
      const mixed = (byteVal ^ work[index]) & 0xff
      const rotated = shift === 0 ? mixed : ((mixed << shift) | (mixed >>> (8 - shift))) & 0xff
      work[index] = rotated
    }
    return base64Encode(sha256(work))
  },

  async makeKey(installationId?: string): Promise<InstallationKey> {
    const id = (installationId || crypto.randomUUID()).toLowerCase()
    const keyPair = await crypto.subtle.generateKey(
      { name: 'ECDSA', namedCurve: 'P-256' },
      true,
      ['sign', 'verify'],
    )
    const privPkcs8 = new Uint8Array(await crypto.subtle.exportKey('pkcs8', keyPair.privateKey))
    const pubDer = new Uint8Array(await crypto.subtle.exportKey('spki', keyPair.publicKey))
    const sec = LaMarzoccoAuth.secret(id, pubDer)
    return {
      installationId: id,
      privateKeyPkcs8: privPkcs8,
      secret: sec,
      publicKeyDer: pubDer,
    }
  },

  async signedHeaders(
    key: InstallationKey,
    nonce = crypto.randomUUID().toLowerCase(),
    nowMs = Date.now(),
  ): Promise<Record<string, string>> {
    const timestamp = String(nowMs)
    const input = `${key.installationId}.${nonce}.${timestamp}`
    const proofVal = LaMarzoccoAuth.proof(input, key.secret)
    const data = new TextEncoder().encode(`${input}.${proofVal}`)

    const privateKey = await crypto.subtle.importKey(
      'pkcs8',
      key.privateKeyPkcs8 as unknown as BufferSource,
      { name: 'ECDSA', namedCurve: 'P-256' },
      false,
      ['sign'],
    )
    const rawSig = new Uint8Array(
      await crypto.subtle.sign({ name: 'ECDSA', hash: { name: 'SHA-256' } }, privateKey, data),
    )
    const derSig = p1363ToDer(rawSig)
    const signature = base64Encode(derSig)

    return {
      'X-App-Installation-Id': key.installationId,
      'X-Timestamp': timestamp,
      'X-Nonce': nonce,
      'X-Request-Signature': signature,
    }
  },

  registrationHeaders(key: InstallationKey): Record<string, string> {
    return {
      'X-App-Installation-Id': key.installationId,
      'X-Request-Proof': LaMarzoccoAuth.proof(
        LaMarzoccoAuth.baseString(key.installationId, key.publicKeyDer),
        key.secret,
      ),
    }
  },

  keyToJson(key: InstallationKey): string {
    return JSON.stringify({
      installationId: key.installationId,
      privateKeyPkcs8: base64Encode(key.privateKeyPkcs8),
      secret: base64Encode(key.secret),
      publicKeyDer: base64Encode(key.publicKeyDer),
    })
  },

  keyFromJson(json: string): InstallationKey | null {
    try {
      const obj = JSON.parse(json)
      const id = String(obj.installationId || obj.installationID || '').toLowerCase()
      if (!id) return null
      return {
        installationId: id,
        privateKeyPkcs8: base64Decode(obj.privateKeyPkcs8),
        secret: base64Decode(obj.secret),
        publicKeyDer: base64Decode(obj.publicKeyDer),
      }
    } catch {
      return null
    }
  },
}

export interface LaMarzoccoMachine {
  id: string
  name: string
  model: string
}

export interface DashboardResult {
  connected: boolean | null
  commandResults: Record<string, string>
  status: MachineStatus
}

export interface StompFrame {
  command: string
  headers: Record<string, string>
  body: string
}

type JsonObj = Record<string, unknown>
const isObj = (v: unknown): v is JsonObj => typeof v === 'object' && v !== null && !Array.isArray(v)

export const LaMarzoccoProtocol = {
  HOST: 'lion.lamarzocco.io',
  API_BASE: 'https://lion.lamarzocco.io/api/customer-app',
  SOCKET_URL: 'wss://lion.lamarzocco.io/ws/connect',
  REFRESH_MARGIN_MS: 10 * 60 * 1000,
  TOKEN_LIFETIME_MS: 60 * 60 * 1000,

  machines(json: Uint8Array | string): LaMarzoccoMachine[] {
    const text = typeof json === 'string' ? json : new TextDecoder().decode(json)
    if (text.length > 1_000_000) return []
    try {
      const array = JSON.parse(text)
      if (!Array.isArray(array)) return []
      const list: LaMarzoccoMachine[] = []
      for (const thing of array.slice(0, 20)) {
        if (!isObj(thing)) continue
        const type = typeof thing.type === 'string' ? thing.type : 'CoffeeMachine'
        if (type !== 'CoffeeMachine') continue
        const rawSerial = typeof thing.serialNumber === 'string' ? thing.serialNumber.slice(0, 40) : ''
        if (!rawSerial) continue
        const rawName = typeof thing.name === 'string' ? thing.name.slice(0, 60) : ''
        const rawModel = typeof thing.modelName === 'string' ? thing.modelName.slice(0, 60) : ''
        const name = rawName || rawModel || rawSerial
        list.push({ id: rawSerial, name, model: rawModel })
      }
      return list
    } catch {
      return []
    }
  },

  tokens(json: Uint8Array | string): [string, string] | null {
    const text = typeof json === 'string' ? json : new TextDecoder().decode(json)
    if (text.length > 100_000) return null
    try {
      const obj = JSON.parse(text)
      if (!isObj(obj)) return null
      const access = typeof obj.accessToken === 'string' ? obj.accessToken : ''
      const refresh = typeof obj.refreshToken === 'string' ? obj.refreshToken : ''
      if (!access || !refresh) return null
      return [access, refresh]
    } catch {
      return null
    }
  },

  commandID(json: Uint8Array | string): string | null {
    const text = typeof json === 'string' ? json : new TextDecoder().decode(json)
    if (text.length > 100_000) return null
    try {
      const array = JSON.parse(text)
      if (!Array.isArray(array) || array.length === 0) return null
      const first = array[0]
      if (!isObj(first) || typeof first.id !== 'string' || !first.id) return null
      return first.id
    } catch {
      return null
    }
  },

  needsRefresh(expiresAtMs: number, nowMs = Date.now()): boolean {
    return expiresAtMs - nowMs < LaMarzoccoProtocol.REFRESH_MARGIN_MS
  },

  apply(dashboard: Uint8Array | string, currentStatus: MachineStatus): DashboardResult | null {
    const text = typeof dashboard === 'string' ? dashboard : new TextDecoder().decode(dashboard)
    if (text.length > 1_000_000) return null
    let obj: JsonObj
    try {
      const parsed = JSON.parse(text)
      if (!isObj(parsed)) return null
      obj = parsed
    } catch {
      return null
    }

    const connected = typeof obj.connected === 'boolean' ? obj.connected : null
    const commandResults: Record<string, string> = {}
    if (Array.isArray(obj.commands)) {
      for (const cmd of obj.commands.slice(0, 50)) {
        if (isObj(cmd) && typeof cmd.id === 'string' && typeof cmd.status === 'string') {
          if (cmd.id && cmd.status) commandResults[cmd.id] = cmd.status
        }
      }
    }

    let next: MachineStatus = {
      ...currentStatus,
      hasPressure: false,
      pressure: null,
      flow: null,
    }

    if (Array.isArray(obj.widgets)) {
      for (const w of obj.widgets.slice(0, 100)) {
        if (!isObj(w) || typeof w.code !== 'string' || !isObj(w.output)) continue
        if (w.code === 'CMMachineStatus') {
          const out = w.output
          const state = typeof out.status === 'string' ? out.status : ''
          const modeStr = typeof out.mode === 'string' ? out.mode : ''
          if (modeStr === 'StandBy') next.mode = 0
          else if (modeStr === 'BrewingMode' || modeStr === 'EcoMode') next.mode = 1

          if (state === 'StandBy' || state === 'Off') {
            next.mode = 0
            next.systemState = 'standby'
            next.systemMessage = null
          } else if (next.systemState === 'standby') {
            next.systemState = 'ready'
          }
          const isBrewing = connected !== false && state === 'Brewing'
          next.processActive = isBrewing
          next.processKind = isBrewing ? 'brew' : null
          next.processLabel = isBrewing ? 'Brewing' : null
          next.processIsUtility = false
        } else if (w.code === 'CMCoffeeBoiler') {
          const out = w.output
          const target = typeof out.targetTemperature === 'number' ? out.targetTemperature : null
          if (target != null && Number.isFinite(target) && target >= 50 && target <= 130) {
            next.targetTemperature = target
          }
          const boilerStatus = typeof out.status === 'string' ? out.status : ''
          if (boilerStatus === 'NoWater') {
            next.systemState = 'error'
            next.systemMessage = 'No water in the tank'
          } else if (boilerStatus === 'HeatingUp') {
            next.systemState = 'heating'
            next.systemMessage = null
          } else if (boilerStatus === 'Ready') {
            next.systemState = 'ready'
            next.systemMessage = null
          }
        }
      }
    }

    if (connected === false) {
      next.processActive = false
      next.processKind = null
      next.processLabel = null
      next.processIsUtility = false
    }

    return { connected, commandResults, status: next }
  },

  stompFrame(command: string, headers: [string, string][], body = ''): string {
    let out = command + '\n'
    for (const [k, v] of headers) {
      out += `${k}:${v}\n`
    }
    out += '\n' + body + '\0'
    return out
  },

  parseStomp(text: string): StompFrame | null {
    let frame = text
    if (frame.endsWith('\0')) frame = frame.slice(0, -1)
    let startIdx = 0
    while (startIdx < frame.length && (frame[startIdx] === '\n' || frame[startIdx] === '\r')) {
      startIdx++
    }
    const trimmed = frame.slice(startIdx)
    if (!trimmed) return null

    const splitPos = trimmed.indexOf('\n\n')
    const headPart = splitPos >= 0 ? trimmed.slice(0, splitPos) : trimmed
    const body = splitPos >= 0 ? trimmed.slice(splitPos + 2) : ''

    const lines = headPart.split('\n')
    const command = lines[0].trim()
    if (!command) return null

    const headers: Record<string, string> = {}
    for (let i = 1; i < lines.length; i++) {
      const colon = lines[i].indexOf(':')
      if (colon >= 0) {
        const k = lines[i].slice(0, colon).trim()
        const v = lines[i].slice(colon + 1).trim()
        headers[k] = v
      }
    }
    return { command, headers, body }
  },
}
