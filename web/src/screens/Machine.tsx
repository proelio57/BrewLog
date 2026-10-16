import { Coffee, Gauge, Minus, Plus, Send, TriangleAlert } from 'lucide-react'
import { useState } from 'react'
import { machine, navigate, pressure } from '../app'
import { useStore } from '../data/store'
import { fmt1 } from '../domain/format'
import type { Recipe } from '../domain/recipe'
import { MACHINE_MODES, gaggiMateUrl, isBrewing } from '../machine/gaggimate'
import { type MachineKind, machineBlockedByHttps } from '../machine/machineManager'
import { CONNECTION_LABELS, bluetoothSupported } from '../scale/scaleManager'
import { Card, Chip, SectionHeader, Stat, Toggle } from '../ui/components'

// Espresso machine (GaggiMate) and pressure sensor (BOOKOO Espresso Monitor). Port of MachineCard.swift,
// PressureViews.swift and the espresso part of SettingsView.

function connectionText(): string {
  const state = machine.state.get()
  switch (state.connection) {
    case 'off': return 'Off'
    case 'connecting': return 'Connecting…'
    case 'connected': return isBrewing(state.status) ? 'Brewing' : 'Connected'
    case 'unreachable': return 'Offline'
  }
}

/** Status and controls on the Brew tab for espresso recipes. */
export function MachineCard({ recipe, dose, temperature }: { recipe: Recipe; dose: number; temperature: number }) {
  const state = useStore(machine.state)
  const status = state.status
  const connected = state.connection === 'connected'
  return (
    <Card>
      <div className="row">
        <Coffee size={20} className="accent" />
        <span className="title grow">{machine.displayName}</span>
        <span className="badge">{connectionText()}</span>
      </div>
      <PressureRow />
      {state.kind === 'none' && (
        <>
          <div className="small muted">Connect a GaggiMate to record pressure and temperature, start shots from here and send recipes as profiles. Without one, BrewLog times the shot with your scale.</div>
          <button className="link" onClick={() => navigate('/settings')}>Set up machine</button>
        </>
      )}
      {state.kind !== 'none' && !connected && (
        <>
          <div className="small muted">{machineBlockedByHttps() ? httpsHint
            : state.connection === 'connecting' ? `Connecting to ${state.host}…` : `Can't reach ${state.host}. Is the machine on and in the same Wi-Fi?`}</div>
          <button className="link" onClick={() => navigate('/settings')}>Machine settings</button>
        </>
      )}
      {connected && (
        <>
          <div className="stats">
            <Stat value={status.temperature != null ? `${fmt1(status.temperature)}°` : '–'} label="Boiler" />
            <Stat value={status.targetTemperature != null ? `${Math.round(status.targetTemperature)}°` : '–'} label="Target" />
            <Stat value={status.profile ?? '–'} label="Profile" />
          </div>
          <div className="chips">
            {MACHINE_MODES.map((m) => <Chip key={m.mode} title={m.title} selected={(status.mode ?? 0) === m.mode} onClick={() => machine.setMode(m.mode)} />)}
          </div>
          <div className="row">
            <span className="grow muted">Temperature</span>
            <button className="icon-btn filled" aria-label="1 °C cooler" onClick={() => machine.nudgeTemperature(false)}><Minus size={18} /></button>
            <button className="icon-btn filled" aria-label="1 °C hotter" onClick={() => machine.nudgeTemperature(true)}><Plus size={18} /></button>
          </div>
          <button className="btn tinted" onClick={() => machine.sendProfile(recipe, dose, temperature)}><Send size={16} />Send recipe to machine</button>
          {state.notice && <div className="small muted">{state.notice}</div>}
          {status.systemMessage && <div className="row small" style={{ color: 'var(--warn)', gap: 4 }}><TriangleAlert size={14} />{status.systemMessage}</div>}
        </>
      )}
    </Card>
  )
}

const httpsHint = 'Browsers block the unencrypted connection to GaggiMate from an https page. Open BrewLog from your computer (npm start) or its LAN address to use GaggiMate.'

function PressureRow() {
  const state = useStore(pressure.state)
  if (!state.enabled) return null
  return (
    <div className="row small">
      <Gauge size={16} className="accent" />
      <span className="grow">Pressure sensor</span>
      <span className="muted tnum">{pressure.isReady ? `${fmt1(state.pressure)} bar` : CONNECTION_LABELS[state.connection]}</span>
    </div>
  )
}

/** Settings: espresso machine and pressure sensor. */
export function EspressoSettings() {
  const state = useStore(machine.state)
  const sensor = useStore(pressure.state)
  const [host, setHost] = useState(state.host)
  const valid = gaggiMateUrl(host) != null
  const choose = (kind: MachineKind) => machine.configure(kind, valid ? host : state.host)
  return (
    <>
      <SectionHeader title="Espresso machine" />
      <Card>
        <div className="chips">
          <Chip title="None" selected={state.kind === 'none'} onClick={() => choose('none')} />
          <Chip title="GaggiMate" selected={state.kind === 'gaggimate'} onClick={() => choose('gaggimate')} />
          <Chip title="Demo machine" selected={state.kind === 'demo'} onClick={() => choose('demo')} />
        </div>
        {state.kind === 'gaggimate' && (
          <>
            <label className="row">
              <span className="grow">Address</span>
              <input className="input" style={{ maxWidth: 200, textAlign: 'right' }} value={host} placeholder="gaggimate.local"
                autoCapitalize="none" autoCorrect="off" spellCheck={false} inputMode="url"
                onChange={(e) => setHost(e.target.value)} onBlur={() => { if (valid && host !== state.host) machine.configure('gaggimate', host) }} />
            </label>
            {!valid && <div className="small" style={{ color: 'var(--warn)' }}>Enter a host name like gaggimate.local or an IP address like 192.168.1.20.</div>}
            {machineBlockedByHttps() && <div className="small" style={{ color: 'var(--warn)' }}>{httpsHint}</div>}
          </>
        )}
        {state.kind !== 'none' && <div className="row"><span className="grow">Status</span><span className="muted">{connectionText()}
          {state.connection === 'connected' && state.status.temperature != null ? ` · ${fmt1(state.status.temperature)} °C` : ''}</span></div>}
        <div className="small muted">GaggiMate: BrewLog connects over your Wi-Fi, records pressure, temperature and flow, follows the shot and can start it, switch modes and send recipes as profiles. Use the address from GaggiMate's web interface. Your scale can stay connected to GaggiMate; BrewLog then reads the weight from there.</div>
      </Card>

      <SectionHeader title="Pressure sensor" />
      <Card>
        <Toggle label="BOOKOO Espresso Monitor" checked={sensor.enabled} onChange={(v) => pressure.configure(v, sensor.isDemo)}
          detail="Measures the pressure at the group head, works with any machine. BrewLog records it with every shot and starts the timer when the pressure rises." />
        {sensor.enabled && (
          <>
            <div className="row">
              <span className="grow">{sensor.isDemo ? 'Demo sensor' : CONNECTION_LABELS[sensor.connection]}</span>
              {pressure.isReady && <span className="muted tnum">{fmt1(sensor.pressure)} bar{sensor.battery != null ? ` · ${sensor.battery}%` : ''}</span>}
            </div>
            {!sensor.isDemo && bluetoothSupported() && sensor.connection !== 'connected' && (
              <button className="btn tinted" onClick={() => void pressure.connect()}>Connect sensor</button>
            )}
            {!sensor.isDemo && sensor.connection === 'connected' && <button className="btn" onClick={() => void pressure.disconnect()}>Disconnect</button>}
            {sensor.error && <div className="small" style={{ color: 'var(--warn)' }}>{sensor.error}</div>}
            <Toggle label="Demo sensor" checked={sensor.isDemo} onChange={(v) => pressure.configure(true, v)} detail="Simulates the pressure of a shot." />
          </>
        )}
      </Card>
    </>
  )
}
