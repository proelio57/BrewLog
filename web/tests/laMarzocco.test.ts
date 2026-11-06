import { describe, expect, it } from 'vitest'
import {
  base64Decode,
  base64Encode,
  derToP1363,
  LaMarzoccoAuth,
  LaMarzoccoProtocol,
} from '../src/machine/laMarzocco'
import type { MachineStatus } from '../src/domain/models'

describe('LaMarzoccoAuth', () => {
  const installationID = '3f2504e0-4f89-41d3-9a0c-0305e82c3301'
  const publicKeyDER = Uint8Array.from({ length: 91 }, (_, i) => i)

  it('computes proof vectors', () => {
    expect(LaMarzoccoAuth.proof('abc', new Uint8Array(32))).toBe('P5ynD3LZU7oRYIN0D2ZtOlbpepJdBXQH9vdqJGOfq/o=')
    const secret = base64Decode('EUWj84o7RXt611rkgsprs36qybfa0ZjAUFSQFvJJ2co=')
    expect(
      LaMarzoccoAuth.proof(
        `${installationID}.00000000-0000-4000-8000-000000000000.1762358400000`,
        secret,
      ),
    ).toBe('4rXwI3Qpk0PhDlJu+HH5iSckHEm4F9GknCUIx3iNarg=')
  })

  it('computes secret and base string matching reference', () => {
    const secret = LaMarzoccoAuth.secret(installationID, publicKeyDER)
    expect(base64Encode(secret)).toBe('EUWj84o7RXt611rkgsprs36qybfa0ZjAUFSQFvJJ2co=')
    const base = LaMarzoccoAuth.baseString(installationID, publicKeyDER)
    expect(base).toBe(`${installationID}.WNKUWbITCi4VElLUCLlebaxCTFZAYuuRHMdkQMuSbKA=`)
    expect(LaMarzoccoAuth.proof(base, secret)).toBe('/gmx2S9P5KtTvJ4RScjIgp96zl4CSPsaVaLcuukpVLs=')
  })

  it('generates signed headers and verifies with ECDSA public key', async () => {
    const key = await LaMarzoccoAuth.makeKey('abc-id')
    expect(key.secret.length).toBe(32)
    const headers = await LaMarzoccoAuth.signedHeaders(key, 'n-1', 1762358400000)
    expect(headers['X-App-Installation-Id']).toBe('abc-id')
    expect(headers['X-Timestamp']).toBe('1762358400000')
    expect(headers['X-Nonce']).toBe('n-1')

    const proof = LaMarzoccoAuth.proof('abc-id.n-1.1762358400000', key.secret)
    const data = new TextEncoder().encode(`abc-id.n-1.1762358400000.${proof}`)
    const derSig = base64Decode(headers['X-Request-Signature'])
    const rawSig = derToP1363(derSig)

    const pubKey = await crypto.subtle.importKey(
      'spki',
      key.publicKeyDer as unknown as BufferSource,
      { name: 'ECDSA', namedCurve: 'P-256' },
      false,
      ['verify'],
    )
    const valid = await crypto.subtle.verify(
      { name: 'ECDSA', hash: { name: 'SHA-256' } },
      pubKey,
      rawSig as unknown as BufferSource,
      data,
    )
    expect(valid).toBe(true)

    const reg = LaMarzoccoAuth.registrationHeaders(key)
    expect(reg['X-App-Installation-Id']).toBe('abc-id')
    expect(reg['X-Request-Proof']).toBe(
      LaMarzoccoAuth.proof(LaMarzoccoAuth.baseString('abc-id', key.publicKeyDer), key.secret),
    )
  })

  it('round-trips key through JSON', async () => {
    const key = await LaMarzoccoAuth.makeKey()
    const json = LaMarzoccoAuth.keyToJson(key)
    const decoded = LaMarzoccoAuth.keyFromJson(json)
    expect(decoded).not.toBeNull()
    expect(decoded!.installationId).toBe(key.installationId)
    expect(Array.from(decoded!.secret)).toEqual(Array.from(key.secret))
    expect(Array.from(decoded!.publicKeyDer)).toEqual(Array.from(key.publicKeyDer))
    expect(Array.from(decoded!.privateKeyPkcs8)).toEqual(Array.from(key.privateKeyPkcs8))
  })
})

describe('LaMarzoccoProtocol', () => {
  function dashboard(
    status: string,
    mode: string,
    boiler = 'Ready',
    target = 94.0,
    connected = true,
    extra = '',
  ): string {
    return JSON.stringify({
      serialNumber: 'MR123456',
      type: 'CoffeeMachine',
      connected,
      widgets: [
        {
          code: 'CMMachineStatus',
          index: 1,
          output: {
            status,
            availableModes: ['BrewingMode', 'StandBy'],
            mode,
            nextStatus: null,
            brewingStartTime: null,
          },
        },
        {
          code: 'CMCoffeeBoiler',
          index: 1,
          output: {
            status: boiler,
            enabled: true,
            enabledSupported: false,
            targetTemperature: target,
            targetTemperatureMin: 80,
            targetTemperatureMax: 100,
            targetTemperatureStep: 0.1,
            readyStartTime: null,
          },
        },
        ...(extra ? JSON.parse(`[${extra}]`) : []),
      ],
      commands: [{ id: 'c-1', status: 'Success', errorCode: null }],
    })
  }

  const emptyStatus: MachineStatus = {
    connected: true,
    online: true,
    temperature: null,
    targetTemperature: null,
    pressure: null,
    targetPressure: null,
    flow: null,
    weight: null,
    mode: null,
    profile: null,
    hasPressure: null,
    processActive: false,
    processKind: null,
    processLabel: null,
    processIsUtility: false,
    scaleConnected: false,
    systemState: null,
    systemMessage: null,
    capabilities: ['power', 'temperatureNudge'],
  }

  it('decodes dashboard brewing status', () => {
    let status = emptyStatus
    const res = LaMarzoccoProtocol.apply(dashboard('Brewing', 'BrewingMode'), status)
    expect(res).not.toBeNull()
    status = res!.status
    expect(res!.connected).toBe(true)
    expect(res!.commandResults['c-1']).toBe('Success')
    expect(status.processActive).toBe(true)
    expect(status.mode).toBe(1) // brew
    expect(status.targetTemperature).toBe(94.0)
    expect(status.hasPressure).toBe(false)
    expect(status.pressure).toBeNull()
  })

  it('decodes dashboard standby status', () => {
    let status = emptyStatus
    status = LaMarzoccoProtocol.apply(dashboard('Brewing', 'BrewingMode'), status)!.status
    const res = LaMarzoccoProtocol.apply(dashboard('StandBy', 'StandBy', 'StandBy'), status)
    expect(res).not.toBeNull()
    status = res!.status
    expect(status.processActive).toBe(false)
    expect(status.mode).toBe(0) // standby
    expect(status.systemState).toBe('standby')
  })

  it('ignores unknown widgets and invalid JSON', () => {
    let status = emptyStatus
    const extra = '{"code":"CMSomethingNew","index":1,"output":{"x":[1,2]}},{"code":"CMNoWater"}'
    const res = LaMarzoccoProtocol.apply(dashboard('PoweredOn', 'BrewingMode', 'Ready', 94.0, true, extra), status)
    expect(res).not.toBeNull()
    status = res!.status
    expect(res!.connected).toBe(true)
    expect(status.processActive).toBe(false)
    expect(status.mode).toBe(1)

    expect(LaMarzoccoProtocol.apply('not json', status)).toBeNull()
    expect(LaMarzoccoProtocol.apply('{"widgets": [ {', status)).toBeNull()
  })

  it('handles offline machine', () => {
    const status = emptyStatus
    const res = LaMarzoccoProtocol.apply(dashboard('Brewing', 'BrewingMode', 'Ready', 94.0, false), status)
    expect(res).not.toBeNull()
    expect(res!.connected).toBe(false)
    expect(res!.status.processActive).toBe(false)
  })

  it('handles missing connected key without clearing', () => {
    const status = emptyStatus
    const res = LaMarzoccoProtocol.apply('{"widgets": [], "commands": []}', status)
    expect(res).not.toBeNull()
    expect(res!.connected).toBeNull()
  })

  it('extracts command id', () => {
    expect(LaMarzoccoProtocol.commandID('[{"id":"abc","status":"Pending"}]')).toBe('abc')
    expect(LaMarzoccoProtocol.commandID('[]')).toBeNull()
    expect(LaMarzoccoProtocol.commandID('{}')).toBeNull()
  })

  it('handles boiler no water error', () => {
    const status = emptyStatus
    const res = LaMarzoccoProtocol.apply(dashboard('PoweredOn', 'BrewingMode', 'NoWater'), status)!
    expect(res.status.systemState).toBe('error')
    expect(res.status.systemMessage).toBe('No water in the tank')
  })

  it('decodes and encodes STOMP frames', () => {
    const connected = LaMarzoccoProtocol.parseStomp('CONNECTED\nversion:1.2\nheart-beat:0,0\n\n\u0000')
    expect(connected).not.toBeNull()
    expect(connected!.command).toBe('CONNECTED')
    expect(connected!.headers['version']).toBe('1.2')

    const message = LaMarzoccoProtocol.parseStomp('MESSAGE\ndestination:/ws/sn/X/dashboard\n\n{"a":1}\u0000')
    expect(message).not.toBeNull()
    expect(message!.command).toBe('MESSAGE')
    expect(message!.body).toBe('{"a":1}')

    const noNul = LaMarzoccoProtocol.parseStomp('ERROR\nmessage:Bad token\n\nboom')
    expect(noNul).not.toBeNull()
    expect(noNul!.command).toBe('ERROR')
    expect(noNul!.headers['message']).toBe('Bad token')
    expect(noNul!.body).toBe('boom')

    expect(LaMarzoccoProtocol.parseStomp('')).toBeNull()
    expect(LaMarzoccoProtocol.parseStomp('\n')).toBeNull()

    const frame = LaMarzoccoProtocol.stompFrame('SUBSCRIBE', [
      ['destination', '/ws/sn/X/dashboard'],
      ['ack', 'auto'],
    ])
    expect(frame).toBe('SUBSCRIBE\ndestination:/ws/sn/X/dashboard\nack:auto\n\n\u0000')
  })

  it('filters machines list and excludes grinders', () => {
    const json = JSON.stringify([
      { serialNumber: 'MR1', type: 'CoffeeMachine', name: 'Micra', modelName: 'LINEA MICRA' },
      { serialNumber: 'G1', type: 'Grinder', name: 'Pico' },
      { type: 'CoffeeMachine', name: 'no serial' },
    ])
    expect(LaMarzoccoProtocol.machines(json)).toEqual([
      { id: 'MR1', name: 'Micra', model: 'LINEA MICRA' },
    ])
    expect(LaMarzoccoProtocol.machines('{}')).toEqual([])
  })

  it('parses tokens', () => {
    const tokens = LaMarzoccoProtocol.tokens('{"accessToken":"a","refreshToken":"r","extra":1}')
    expect(tokens).toEqual(['a', 'r'])
    expect(LaMarzoccoProtocol.tokens('{"accessToken":"a"}')).toBeNull()
  })

  it('checks if token needs refresh', () => {
    const now = 1_000_000_000
    expect(LaMarzoccoProtocol.needsRefresh(now + 11 * 60 * 1000, now)).toBe(false)
    expect(LaMarzoccoProtocol.needsRefresh(now + 9 * 60 * 1000, now)).toBe(true)
    expect(LaMarzoccoProtocol.needsRefresh(now - 60 * 1000, now)).toBe(true)
  })
})
