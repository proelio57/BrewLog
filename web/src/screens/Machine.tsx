import { Check, Coffee, Gauge, Minus, Plus, RefreshCw, Send, Star, TriangleAlert, WifiOff } from 'lucide-react'
import { useEffect, useState } from 'react'
import { machine, navigate, pressure, settings, setup } from '../app'
import { useStore } from '../data/store'
import { fmt1 } from '../domain/format'
import type { MachineProfileSummary } from '../domain/models'
import type { Recipe } from '../domain/recipe'
import { MACHINE_MODES, gaggiMateUrl, isBrewing } from '../machine/gaggimate'
import { type MachineKind, machineBlockedByHttps } from '../machine/machineManager'
import { CONNECTION_LABELS, bluetoothSupported } from '../scale/scaleManager'
import { Card, Chip, SectionHeader, Sheet, Stat, Toggle } from '../ui/components'

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
          <div className="small muted">
            Connect a GaggiMate, Decent DE1 or La Marzocco to record pressure and temperature, start shots and follow profiles.
          </div>
          <button className="link" onClick={() => navigate('/settings')}>
            Set up machine
          </button>
        </>
      )}
      {state.kind !== 'none' && !connected && (
        <>
          <div className="small muted">
            {state.kind === 'gaggimate' && machineBlockedByHttps()
              ? httpsHint
              : state.connection === 'connecting'
                ? `Connecting to ${machine.displayName}…`
                : `Can't reach ${machine.displayName}. Is it switched on?`}
          </div>
          <button className="link" onClick={() => navigate('/settings')}>
            Machine settings
          </button>
        </>
      )}
      {connected && (
        <>
          <div className="stats">
            <Stat value={status.temperature != null ? `${fmt1(status.temperature)}°` : '–'} label="Boiler" />
            <Stat value={status.targetTemperature != null ? `${Math.round(status.targetTemperature)}°` : '–'} label="Target" />
            <Stat value={status.profile ?? '–'} label="Profile" />
          </div>
          {state.kind === 'gaggimate' && (
            <div className="chips">
              {MACHINE_MODES.map((m) => (
                <Chip key={m.mode} title={m.title} selected={(status.mode ?? 0) === m.mode} onClick={() => machine.setMode(m.mode)} />
              ))}
            </div>
          )}
          <div className="row">
            <span className="grow muted">Temperature</span>
            <button className="icon-btn filled" aria-label="1 °C cooler" onClick={() => machine.nudgeTemperature(false)}>
              <Minus size={18} />
            </button>
            <button className="icon-btn filled" aria-label="1 °C hotter" onClick={() => machine.nudgeTemperature(true)}>
              <Plus size={18} />
            </button>
          </div>
          {state.kind === 'gaggimate' && (
            <button className="btn tinted" onClick={() => machine.sendProfile(recipe, dose, temperature)}>
              <Send size={16} />Send recipe to machine
            </button>
          )}
          {state.notice && <div className="small muted">{state.notice}</div>}
          {status.systemMessage && (
            <div className="row small" style={{ color: 'var(--warn)', gap: 4 }}>
              <TriangleAlert size={14} />{status.systemMessage}
            </div>
          )}
        </>
      )}
    </Card>
  )
}

const httpsHint =
  'Browsers block unencrypted connections to local devices from https pages. Open BrewLog via localhost or http to connect to local hardware.'

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
  const appSettings = useStore(settings)
  const [host, setHost] = useState(state.host)
  const [lmUser, setLmUser] = useState(appSettings.laMarzoccoUser)
  const [lmPassword, setLmPassword] = useState(appSettings.laMarzoccoPassword)
  const [lmSerial, setLmSerial] = useState(appSettings.laMarzoccoSerial)

  const valid = gaggiMateUrl(host) != null
  const choose = (kind: MachineKind) => machine.configure(kind, valid ? host : state.host)

  return (
    <>
      <SectionHeader title="Espresso machine" />
      <Card>
        <div className="chips">
          <Chip title="None" selected={state.kind === 'none'} onClick={() => choose('none')} />
          <Chip title="GaggiMate" selected={state.kind === 'gaggimate'} onClick={() => choose('gaggimate')} />
          <Chip title="Decent DE1" selected={state.kind === 'decent'} onClick={() => choose('decent')} />
          <Chip title="La Marzocco" selected={state.kind === 'laMarzocco'} onClick={() => choose('laMarzocco')} />
          <Chip title="Demo machine" selected={state.kind === 'demo'} onClick={() => choose('demo')} />
        </div>

        {state.kind === 'gaggimate' && (
          <>
            <label className="row">
              <span className="grow">Address</span>
              <input
                className="input"
                style={{ maxWidth: 200, textAlign: 'right' }}
                value={host}
                placeholder="gaggimate.local"
                autoCapitalize="none"
                autoCorrect="off"
                spellCheck={false}
                inputMode="url"
                onChange={(e) => setHost(e.target.value)}
                onBlur={() => {
                  if (valid && host !== state.host) machine.configure('gaggimate', host)
                }}
              />
            </label>
            {!valid && (
              <div className="small" style={{ color: 'var(--warn)' }}>
                Enter a host name like gaggimate.local or an IP address like 192.168.1.20.
              </div>
            )}
            {machineBlockedByHttps() && <div className="small" style={{ color: 'var(--warn)' }}>{httpsHint}</div>}
          </>
        )}

        {state.kind === 'decent' && (
          <>
            <div className="small muted">
              Connect to your Decent DE1 over Web Bluetooth to read real-time pressure, flow, and temperature, and trigger auto-stop.
            </div>
            {bluetoothSupported() ? (
              <button
                className="btn tinted"
                style={{ marginTop: 8 }}
                onClick={() => void machine.decent.connect()}
                disabled={state.connection === 'connecting'}
              >
                {state.connection === 'connected' ? 'Connected' : 'Search for Decent DE1'}
              </button>
            ) : (
              <div className="small" style={{ color: 'var(--warn)' }}>
                Web Bluetooth is not supported in this browser. Use Chrome or Edge.
              </div>
            )}
          </>
        )}

        {state.kind === 'laMarzocco' && (
          <>
            <div className="small muted">
              Connect to your La Marzocco machine (Micra, Mini, GS3) using your La Marzocco cloud account.
            </div>
            <label className="row">
              <span className="grow">Email</span>
              <input
                className="input"
                style={{ maxWidth: 200, textAlign: 'right' }}
                value={lmUser}
                placeholder="email@example.com"
                onChange={(e) => {
                  setLmUser(e.target.value)
                  settings.change((s) => ({ ...s, laMarzoccoUser: e.target.value }))
                }}
              />
            </label>
            <label className="row">
              <span className="grow">Password</span>
              <input
                type="password"
                className="input"
                style={{ maxWidth: 200, textAlign: 'right' }}
                value={lmPassword}
                placeholder="Password"
                onChange={(e) => {
                  setLmPassword(e.target.value)
                  settings.change((s) => ({ ...s, laMarzoccoPassword: e.target.value }))
                }}
              />
            </label>
            <label className="row">
              <span className="grow">Serial number</span>
              <input
                className="input"
                style={{ maxWidth: 200, textAlign: 'right' }}
                value={lmSerial}
                placeholder="LM012345"
                onChange={(e) => {
                  setLmSerial(e.target.value)
                  settings.change((s) => ({ ...s, laMarzoccoSerial: e.target.value }))
                }}
              />
            </label>
          </>
        )}

        {state.kind !== 'none' && (
          <div className="row" style={{ marginTop: 8 }}>
            <span className="grow">Status</span>
            <span className="muted">
              {connectionText()}
              {state.connection === 'connected' && state.status.temperature != null
                ? ` · ${fmt1(state.status.temperature)} °C`
                : ''}
            </span>
          </div>
        )}
      </Card>

      <SectionHeader title="Pressure sensor" />
      <Card>
        <Toggle
          label="BOOKOO Espresso Monitor"
          checked={sensor.enabled}
          onChange={(v) => pressure.configure(v, sensor.isDemo)}
          detail="Measures pressure at the group head. Works with any espresso machine."
        />
        {sensor.enabled && (
          <>
            <div className="row">
              <span className="grow">{sensor.isDemo ? 'Demo sensor' : CONNECTION_LABELS[sensor.connection]}</span>
              {pressure.isReady && (
                <span className="muted tnum">
                  {fmt1(sensor.pressure)} bar{sensor.battery != null ? ` · ${sensor.battery}%` : ''}
                </span>
              )}
            </div>
            {!sensor.isDemo && bluetoothSupported() && sensor.connection !== 'connected' && (
              <button className="btn tinted" onClick={() => void pressure.connect()}>
                Connect sensor
              </button>
            )}
            {!sensor.isDemo && sensor.connection === 'connected' && (
              <button className="btn" onClick={() => void pressure.disconnect()}>
                Disconnect
              </button>
            )}
            {sensor.error && <div className="small" style={{ color: 'var(--warn)' }}>{sensor.error}</div>}
            <Toggle label="Demo sensor" checked={sensor.isDemo} onChange={(v) => pressure.configure(true, v)} detail="Simulates the pressure of a shot." />
          </>
        )}
      </Card>
    </>
  )
}

/** Sheet to browse and pick profiles from the connected machine */
export function MachineProfilesSheet({ onClose }: { onClose: () => void }) {
  const state = useStore(machine.state)
  const [selectingId, setSelectingId] = useState<string | null>(null)

  useEffect(() => {
    machine.refreshProfiles()
  }, [])

  const choose = (p: MachineProfileSummary) => {
    setSelectingId(p.id)
    machine.selectProfile(p.id)
    if (p.recipe) {
      setup.select(p.recipe)
    }
    setTimeout(() => {
      setSelectingId(null)
      onClose()
    }, 250)
  }

  return (
    <Sheet onClose={onClose}>
      <div className="row">
        <span className="title grow" style={{ fontSize: 20 }}>
          Machine profiles
        </span>
        <button className="icon-btn" aria-label="Refresh profiles" onClick={() => machine.refreshProfiles()}>
          <RefreshCw size={18} />
        </button>
      </div>

      {state.connection !== 'connected' ? (
        <div className="row small" style={{ color: 'var(--warn)', margin: '12px 0' }}>
          <WifiOff size={18} />
          <span>The machine is not connected.</span>
        </div>
      ) : state.profilesLoading ? (
        <div className="small muted" style={{ textAlign: 'center', padding: 20 }}>
          Loading profiles…
        </div>
      ) : state.profiles.length === 0 ? (
        <div className="small muted" style={{ padding: 20 }}>
          No profiles found on the machine.
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6, margin: '12px 0' }}>
          {state.profiles.map((p) => {
            const isSelected = p.isSelected || selectingId === p.id
            return (
              <button
                key={p.id}
                className="row"
                onClick={() => choose(p)}
                style={{
                  background: isSelected ? 'var(--accent-soft)' : 'var(--fill)',
                  border: 'none',
                  borderRadius: 12,
                  padding: '10px 14px',
                  textAlign: 'left',
                  cursor: 'pointer',
                  color: 'inherit',
                }}
              >
                <span className="grow" style={{ fontWeight: isSelected ? 600 : 400 }}>
                  {p.label}
                </span>
                {p.isFavorite && <Star size={16} fill="var(--warn)" color="var(--warn)" />}
                {isSelected && <Check size={18} className="accent" />}
              </button>
            )
          })}
        </div>
      )}

      <div className="small muted">
        Selecting a profile sets it on the machine and uses its target yield, time, and pressure in BrewLog.
      </div>
    </Sheet>
  )
}
