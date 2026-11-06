import { Check, CheckCircle2, Droplet, TriangleAlert } from 'lucide-react'
import { useState } from 'react'
import { goBack, repository } from '../app'
import { useStore } from '../data/store'
import { fmt1, newId } from '../domain/format'
import { Extraction, type ExtractionReading } from '../domain/extraction'
import { GrindConverter } from '../domain/grindConverter'
import { WaterChemistry } from '../domain/waterChemistry'
import { defaultGrinderSpec, type Equipment, type GrinderSpec, type WaterProfile } from '../domain/models'
import { GRINDER_PRESETS } from '../domain/library'
import { Card, Chip, Field, NumberInput, SectionHeader, TopBar } from '../ui/components'

// MARK: - Extraction Chart

export function ExtractionChart({
  readings,
  espresso,
  height = 200,
}: {
  readings: ExtractionReading[]
  espresso: boolean
  height?: number
}) {
  const zone = Extraction.zone(espresso)
  const validReadings = readings.filter((r) => r.yield > 0 && r.tds > 0)

  const width = 300
  const paddingLeft = 32
  const paddingRight = 16
  const paddingTop = 16
  const paddingBottom = 24
  const innerW = width - paddingLeft - paddingRight
  const innerH = height - paddingTop - paddingBottom

  const minYield = 14
  const maxYield = 26
  const minTds = espresso ? 6.0 : 0.9
  const maxTds = espresso ? 14.0 : 1.7

  const getX = (ey: number) => paddingLeft + ((ey - minYield) / (maxYield - minYield)) * innerW
  const getY = (tds: number) => paddingTop + innerH - ((tds - minTds) / (maxTds - minTds)) * innerH

  const zoneX0 = getX(zone.eyMin)
  const zoneX1 = getX(zone.eyMax)
  const zoneY0 = getY(zone.tdsMax)
  const zoneY1 = getY(zone.tdsMin)

  return (
    <div style={{ position: 'relative' }}>
      <svg viewBox={`0 0 ${width} ${height}`} style={{ width: '100%', height, display: 'block' }}>
        {/* Ideal Zone Box */}
        <rect
          x={zoneX0}
          y={zoneY0}
          width={zoneX1 - zoneX0}
          height={zoneY1 - zoneY0}
          fill="rgba(52, 199, 89, 0.16)"
          stroke="rgba(52, 199, 89, 0.4)"
          strokeWidth={1}
          rx={4}
        />

        {/* Axis lines */}
        <line x1={paddingLeft} x2={width - paddingRight} y1={paddingTop + innerH} y2={paddingTop + innerH} stroke="var(--fill)" strokeWidth={1} />
        <line x1={paddingLeft} x2={paddingLeft} y1={paddingTop} y2={paddingTop + innerH} stroke="var(--fill)" strokeWidth={1} />

        {/* X-axis labels */}
        {[16, 20, 24].map((ey) => (
          <text key={ey} x={getX(ey)} y={height - 4} fontSize={9} fill="var(--muted)" textAnchor="middle">
            {ey}%
          </text>
        ))}

        {/* Y-axis labels */}
        {(espresso ? [8, 10, 12] : [1.1, 1.3, 1.5]).map((tds) => (
          <text key={tds} x={paddingLeft - 4} y={getY(tds) + 3} fontSize={9} fill="var(--muted)" textAnchor="end">
            {fmt1(tds)}
          </text>
        ))}

        {/* Points */}
        {validReadings.map((r, i) => (
          <circle
            key={i}
            cx={getX(r.yield)}
            cy={getY(r.tds)}
            r={i === validReadings.length - 1 ? 6 : 4}
            fill="var(--accent)"
            stroke="#fff"
            strokeWidth={1.5}
          />
        ))}
      </svg>
      <div style={{ position: 'absolute', top: 4, left: 36, fontSize: 10, color: 'var(--muted)' }}>strong</div>
      <div style={{ position: 'absolute', bottom: 20, left: 36, fontSize: 10, color: 'var(--muted)' }}>under</div>
      <div style={{ position: 'absolute', bottom: 20, right: 20, fontSize: 10, color: 'var(--muted)' }}>over</div>
    </div>
  )
}

// MARK: - Extraction Calculator Screen

export function ExtractionCalculatorScreen() {
  const [espresso, setEspresso] = useState(false)
  const [dose, setDose] = useState<number | null>(15)
  const [beverage, setBeverage] = useState<number | null>(220)
  const [tds, setTds] = useState<number | null>(null)

  const reading = tds != null && dose != null && beverage != null
    ? Extraction.evaluate(tds, beverage, dose, espresso)
    : null

  return (
    <div className="screen">
      <TopBar title="Extraction" onBack={() => goBack('/gear')} />
      <div className="content">
        <div className="chips" style={{ marginBottom: 12 }}>
          <Chip title="Filter" selected={!espresso} onClick={() => { setEspresso(false); setBeverage(220); setDose(15) }} />
          <Chip title="Espresso" selected={espresso} onClick={() => { setEspresso(true); setBeverage(36); setDose(18) }} />
        </div>

        <Card>
          <Field label="Coffee dose (g)">
            <NumberInput label="Coffee dose (g)" value={dose} onChange={setDose} max={100} />
          </Field>
          <Field label={espresso ? 'Shot weight in cup (g)' : 'Drink weight in server (g)'}>
            <NumberInput label="Drink weight (g)" value={beverage} onChange={setBeverage} max={2000} />
          </Field>
          <Field label="TDS (%)">
            <NumberInput label="TDS (%)" value={tds} onChange={setTds} max={30} decimals={2} placeholder={espresso ? 'e.g. 9.5' : 'e.g. 1.35'} />
          </Field>
          <div className="small muted">
            {espresso
              ? 'Weigh the shot in the cup and measure a well-stirred sample.'
              : 'Weigh the coffee in the server, not the water poured: the grounds hold back about twice their weight.'}
          </div>
        </Card>

        {reading && (
          <>
            <SectionHeader title="Result" />
            <Card>
              <div className="row">
                <span className="grow muted">Extraction yield</span>
                <span style={{ fontWeight: 600, fontSize: 16 }}>{fmt1(reading.yield)} %</span>
              </div>
              <div className="row">
                <span className="grow muted">Strength</span>
                <span style={{ fontWeight: 600 }}>{fmt1(reading.tds)} % TDS · {reading.strength}</span>
              </div>
              <div className="row" style={{ color: reading.verdict === 'ideal' ? 'var(--good)' : 'var(--warn)' }}>
                {reading.verdict === 'ideal' ? <CheckCircle2 size={18} /> : <TriangleAlert size={18} />}
                <span style={{ fontWeight: 600 }}>{reading.verdict === 'ideal' ? 'Ideal extraction' : reading.verdict === 'under' ? 'Under-extracted' : 'Over-extracted'}</span>
              </div>
              <div className="small muted">{reading.advice}</div>
              <div className="divider" />
              <ExtractionChart readings={[reading]} espresso={espresso} height={180} />
            </Card>
          </>
        )}

        <div className="small muted" style={{ marginTop: 8 }}>
          Extraction yield = drink weight × TDS ÷ coffee dose. The green box is the classic ideal:{' '}
          {espresso ? '8–12' : '1.15–1.45'} % TDS at 18–22 % extraction.
        </div>
      </div>
    </div>
  )
}

// MARK: - Water Calculator Screen

export function WaterCalculatorScreen() {
  const [presetName, setPresetName] = useState<string>(WaterChemistry.presets[0].name)
  const [hardness, setHardness] = useState<number>(WaterChemistry.presets[0].hardness)
  const [alkalinity, setAlkalinity] = useState<number>(WaterChemistry.presets[0].alkalinity)
  const [litres, setLitres] = useState<number>(4)
  const [magnesiumPercent, setMagnesiumPercent] = useState<number>(100)
  const [concentrates, setConcentrates] = useState<boolean>(false)
  const [saveName, setSaveName] = useState<string>('')
  const [saved, setSaved] = useState<boolean>(false)

  const recipe = WaterChemistry.calculate(hardness, alkalinity, litres, magnesiumPercent / 100)

  const choosePreset = (name: string) => {
    setPresetName(name)
    const found = WaterChemistry.presets.find((p) => p.name === name)
    if (found) {
      setHardness(found.hardness)
      setAlkalinity(found.alkalinity)
    }
  }

  const saveProfile = () => {
    const name = (saveName.trim() || presetName || 'My water').slice(0, 50)
    const notes = `${WaterChemistry.summary(hardness, alkalinity)}, ${Math.round(magnesiumPercent)} % magnesium`
    const profile: WaterProfile = {
      id: newId(),
      name,
      hardness,
      alkalinity,
      magnesiumShare: magnesiumPercent / 100,
    }
    const item: Equipment = {
      id: newId(),
      name,
      type: 'water',
      notes,
      method: null,
      filterFlow: null,
      idealRoast: null,
      grinder: defaultGrinderSpec(),
      createdAt: Date.now(),
      waterProfile: profile,
    }
    repository.upsertEquipment(item)
    setSaved(true)
  }

  return (
    <div className="screen">
      <TopBar title="Water recipes" onBack={() => goBack('/gear')} />
      <div className="content">
        <SectionHeader title="Target" />
        <Card>
          <div className="small muted">Recipe preset</div>
          <select className="input" value={presetName} onChange={(e) => choosePreset(e.target.value)}>
            {WaterChemistry.presets.map((p) => (
              <option key={p.name} value={p.name}>
                {p.name} ({p.hardness}/{p.alkalinity})
              </option>
            ))}
            <option value="Custom">Custom</option>
          </select>

          <Field label="Hardness (GH, ppm)">
            <NumberInput label="Hardness" value={hardness} onChange={(v) => { setHardness(v ?? 0); setPresetName('Custom') }} max={500} />
          </Field>
          <Field label="Alkalinity (KH, ppm)">
            <NumberInput label="Alkalinity" value={alkalinity} onChange={(v) => { setAlkalinity(v ?? 0); setPresetName('Custom') }} max={300} />
          </Field>
          <div className="small muted">
            {WaterChemistry.character(hardness, alkalinity)} ppm = mg/L as CaCO3.
          </div>
        </Card>

        <SectionHeader title="Batch" />
        <Card>
          <div className="row">
            <span className="grow muted">Batch volume</span>
            <span style={{ fontWeight: 600 }}>{fmt1(litres)} L</span>
          </div>
          <input className="range" type="range" min={0.5} max={10} step={0.5} value={litres} onChange={(e) => setLitres(Number(e.target.value))} />

          <div className="row" style={{ marginTop: 8 }}>
            <span className="grow muted">Hardness from magnesium</span>
            <span style={{ fontWeight: 600 }}>{Math.round(magnesiumPercent)} %</span>
          </div>
          <input className="range" type="range" min={0} max={100} step={10} value={magnesiumPercent} onChange={(e) => setMagnesiumPercent(Number(e.target.value))} />
          <div className="tiny muted">Magnesium tastes brighter; calcium rounder and scales faster.</div>

          <div className="divider" />
          <div className="chips">
            <Chip title="Dry minerals" selected={!concentrates} onClick={() => setConcentrates(false)} />
            <Chip title="Concentrates" selected={concentrates} onClick={() => setConcentrates(true)} />
          </div>
        </Card>

        <SectionHeader title={`For ${fmt1(litres)} L`} />
        <Card>
          {concentrates ? (
            <>
              {recipe.hardnessConcentrateGrams > 0 && (
                <div className="row">
                  <span className="grow muted">Hardness concentrate (Epsom)</span>
                  <span style={{ fontWeight: 600 }}>{fmt1(recipe.hardnessConcentrateGrams)} g</span>
                </div>
              )}
              {recipe.calciumConcentrateGrams > 0 && (
                <div className="row">
                  <span className="grow muted">Calcium concentrate</span>
                  <span style={{ fontWeight: 600 }}>{fmt1(recipe.calciumConcentrateGrams)} g</span>
                </div>
              )}
              <div className="row">
                <span className="grow muted">Buffer concentrate (baking soda)</span>
                <span style={{ fontWeight: 600 }}>{fmt1(recipe.bufferConcentrateGrams)} g</span>
              </div>
              <div className="row">
                <span className="grow muted">Distilled water</span>
                <span style={{ fontWeight: 600 }}>{Math.round(recipe.distilledGrams)} g</span>
              </div>
              <div className="tiny muted" style={{ marginTop: 6 }}>
                Make concentrates once: {fmt1(WaterChemistry.EPSOM_PER_PPM)} g Epsom salt, {fmt1(WaterChemistry.CALCIUM_CHLORIDE_PER_PPM)} g calcium chloride, or {fmt1(WaterChemistry.BAKING_SODA_PER_PPM)} g baking soda in 1 L distilled water (1000 ppm).
              </div>
            </>
          ) : (
            <>
              {recipe.epsomGrams > 0 && (
                <div className="row">
                  <span className="grow muted">Epsom salt (MgSO4·7H2O)</span>
                  <span style={{ fontWeight: 600 }}>{recipe.epsomGrams.toFixed(3)} g</span>
                </div>
              )}
              {recipe.calciumChlorideGrams > 0 && (
                <div className="row">
                  <span className="grow muted">Calcium chloride (CaCl2·2H2O)</span>
                  <span style={{ fontWeight: 600 }}>{recipe.calciumChlorideGrams.toFixed(3)} g</span>
                </div>
              )}
              <div className="row">
                <span className="grow muted">Baking soda (NaHCO3)</span>
                <span style={{ fontWeight: 600 }}>{recipe.bakingSodaGrams.toFixed(3)} g</span>
              </div>
              <div className="tiny muted" style={{ marginTop: 6 }}>
                Dissolve in distilled or reverse-osmosis water. Small amounts need a 0.01 g scale.
              </div>
            </>
          )}
        </Card>

        <SectionHeader title="Save as gear" />
        <Card>
          <input
            className="input"
            placeholder={`Name, e.g. ${presetName === 'Custom' ? 'My water' : presetName}`}
            value={saveName}
            onChange={(e) => setSaveName(e.target.value)}
          />
          <button className="btn tinted" style={{ marginTop: 8 }} onClick={saveProfile} disabled={saved}>
            {saved ? <Check size={18} /> : <Droplet size={18} />}
            {saved ? 'Saved to gear' : 'Save as water profile'}
          </button>
          <div className="tiny muted">
            Saved water profiles appear under Gear and can be linked to your brews.
          </div>
        </Card>
      </div>
    </div>
  )
}

// MARK: - Grind Converter Screen

interface GrinderOption {
  id: string
  name: string
  spec: GrinderSpec
}

export function GrindConverterScreen() {
  const data = useStore(repository.data)
  const ownGrinders: GrinderOption[] = data.equipment
    .filter((e) => e.type === 'grinder' && e.grinder)
    .map((e) => ({
      id: e.id,
      name: e.name,
      spec: GrindConverter.calibrated(e.grinder!, e.name),
    }))
    .filter((o) => GrindConverter.canConvert(o.spec))

  const presetGrinders: GrinderOption[] = GRINDER_PRESETS
    .map((p) => {
      const spec = p.grinder ? GrindConverter.calibrated(p.grinder, p.name) : null
      return spec && GrindConverter.canConvert(spec) ? { id: `preset:${p.name}`, name: p.name, spec } : null
    })
    .filter((p): p is GrinderOption => p !== null && !ownGrinders.some((o) => o.name === p.name))

  const allOptions: GrinderOption[] = [...ownGrinders, ...presetGrinders]

  const [fromId, setFromId] = useState<string>(allOptions[0]?.id ?? '')
  const [toId, setToId] = useState<string>(allOptions[1]?.id ?? allOptions[0]?.id ?? '')
  const [value, setValue] = useState<number | null>(null)

  const fromOption = allOptions.find((o) => o.id === fromId)
  const toOption = allOptions.find((o) => o.id === toId)

  const inputValue = value ?? fromOption?.spec.defaultGrind ?? 0
  const result = fromOption && toOption ? GrindConverter.convert(inputValue, fromOption.spec, toOption.spec) : null
  const microns = fromOption ? GrindConverter.microns(inputValue, fromOption.spec) : null

  return (
    <div className="screen">
      <TopBar title="Grind converter" onBack={() => goBack('/gear')} />
      <div className="content">
        <Card>
          <Field label="From grinder">
            <select className="input" value={fromId} onChange={(e) => { setFromId(e.target.value); setValue(null) }}>
              {allOptions.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.name}
                </option>
              ))}
            </select>
          </Field>
          <Field label={`Setting (${fromOption?.spec.unit ?? 'clicks'})`}>
            <NumberInput
              label="Setting"
              value={inputValue}
              onChange={setValue}
              max={10000}
              decimals={fromOption && fromOption.spec.step < 1 ? 2 : 0}
            />
          </Field>
          <Field label="To grinder">
            <select className="input" value={toId} onChange={(e) => setToId(e.target.value)}>
              {allOptions.map((o) => (
                <option key={o.id} value={o.id}>
                  {o.name}
                </option>
              ))}
            </select>
          </Field>
        </Card>

        {fromOption && toOption && result != null && (
          <>
            <SectionHeader title="Result" />
            <Card>
              <div className="row">
                <span className="grow muted">
                  {inputValue} on {fromOption.name}
                </span>
                <span style={{ fontWeight: 700, fontSize: 18 }}>
                  ≈ {result} {toOption.spec.unit}
                </span>
              </div>
              {microns != null && (
                <div className="row">
                  <span className="grow muted">Grind size</span>
                  <span style={{ fontWeight: 600 }}>≈ {Math.round(microns)} µm</span>
                </div>
              )}
            </Card>
          </>
        )}

        <div className="small muted" style={{ marginTop: 8 }}>
          A starting point, not an exact match: burrs and zero points differ between grinders, even of the same model. Taste and adjust from there.
        </div>
      </div>
    </div>
  )
}
