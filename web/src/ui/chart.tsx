import { useEffect, useMemo, useRef, useState } from 'react'
import { centeredFlows } from '../analysis/analyzer'
import { useStore } from '../data/store'
import { fmt1, mmss } from '../domain/format'
import type { MachineSample, WeightSample } from '../domain/models'
import { targetCurve, type Recipe } from '../domain/recipe'
import { settings } from '../app'

/** Precomputed series and axis scaling. Port of BrewChartModel (BrewChart.swift / BrewChart.kt). */
function buildModel(samples: WeightSample[], recipe: Recipe | null, currentTime: number | null) {
  const flows = centeredFlows(samples)
  const lastT = samples.length ? samples[samples.length - 1].t : 0
  const maxT = Math.max((recipe?.targetTime ?? 0) + 15, lastT + 5, currentTime ?? 0, 30)
  const maxW = Math.max((recipe?.water ?? 0) * 1.08, Math.max(0, ...samples.map((s) => s.w)) * 1.05, 10)
  // Flow axis: room for the recipe's range, scaled to the 98th percentile so one bump doesn't squash the graph.
  const sorted = [...flows].sort((a, b) => a - b)
  const typicalPeak = sorted.length ? sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * 0.98))] : 0
  const rawMax = Math.min(Math.max(Math.max(recipe?.flowMax ?? 8, 4) * 1.3, typicalPeak * 1.1), 30)
  const step = [1, 2, 2.5, 5, 10, 20].find((c) => c >= rawMax / 3) ?? 20
  const maxFlow = Math.max(Math.ceil(rawMax / step) * step, step)
  const flowTicks: number[] = []
  for (let f = 0; f <= maxFlow + 0.001; f += step) flowTicks.push(f)
  const weightStep = niceStep(maxW / 4)
  const weightTicks: number[] = []
  for (let w = 0; w <= maxW; w += weightStep) weightTicks.push(w)
  // Downsample for drawing (≤ ~400 points), keeping the last sample.
  const stride = Math.max(Math.floor(samples.length / 400), 1)
  const indices: number[] = []
  for (let i = 0; i < samples.length; i += stride) indices.push(i)
  if (samples.length && indices[indices.length - 1] !== samples.length - 1) indices.push(samples.length - 1)
  return {
    maxT, maxW, maxFlow, flowTicks, weightTicks,
    weight: indices.map((i) => [samples[i].t, Math.max(samples[i].w, 0)] as const),
    flow: indices.map((i) => [samples[i].t, Math.min(Math.max(flows[i], 0), maxFlow)] as const),
    target: recipe ? targetCurve(recipe) : [],
    stepTimes: recipe?.steps.map((s) => s.time) ?? [],
  }
}

function niceStep(raw: number): number {
  if (raw <= 0) return 1
  const base = 10 ** Math.floor(Math.log10(raw))
  const f = raw / base
  return (f <= 1 ? 1 : f <= 2 ? 2 : f <= 2.5 ? 2.5 : f <= 5 ? 5 : 10) * base
}

export const flowLabel = (v: number): string => (Number.isInteger(v) ? String(v) : fmt1(v))

/**
 * Weight (left axis) and flow in g/s (right axis) on one chart, with the recipe's ideal curve and step markers.
 * Tap "Flow" in the legend to show or hide the flow overlay (remembered).
 */
export function BrewChart({ samples, recipe, currentTime = null, height = 200, showFlowRange = false }:
  { samples: WeightSample[]; recipe: Recipe | null; currentTime?: number | null; height?: number; showFlowRange?: boolean }) {
  const ref = useRef<HTMLDivElement>(null)
  const [width, setWidth] = useState(320)
  const flowVisible = useStore(settings).chartShowsFlow
  const model = useMemo(() => buildModel(samples, recipe, currentTime), [samples, recipe, currentTime])

  useEffect(() => {
    const element = ref.current
    if (!element) return
    const observer = new ResizeObserver(([entry]) => setWidth(Math.max(entry.contentRect.width, 100)))
    observer.observe(element)
    return () => observer.disconnect()
  }, [])

  const left = 30
  const right = flowVisible ? 26 : 6
  const top = 6
  const bottom = 18
  const x0 = left
  const x1 = width - right
  const y1 = height - bottom
  const x = (t: number) => x0 + (t / model.maxT) * (x1 - x0)
  const yW = (w: number) => y1 - (w / model.maxW) * (y1 - top)
  const yF = (f: number) => y1 - (f / model.maxFlow) * (y1 - top)
  const line = (points: readonly (readonly [number, number])[], y: (v: number) => number) =>
    points.map(([t, v], i) => `${i ? 'L' : 'M'}${x(t).toFixed(1)},${y(v).toFixed(1)}`).join('')
  const area = (points: readonly (readonly [number, number])[], y: (v: number) => number) =>
    points.length < 2 ? '' : `${line(points, y)}L${x(points[points.length - 1][0]).toFixed(1)},${y1}L${x(points[0][0]).toFixed(1)},${y1}Z`
  const timeTicks: number[] = []
  for (let t = 0; t <= model.maxT; t += model.maxT > 300 ? 60 : 30) timeTicks.push(t)

  return (
    <div ref={ref}>
      <svg width={width} height={height} role="img" aria-label="Pour curve: weight and flow over time" style={{ display: 'block' }}>
        <defs>
          <linearGradient id="weightFill" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="var(--accent)" stopOpacity={flowVisible ? 0.16 : 0.26} />
            <stop offset="1" stopColor="var(--accent)" stopOpacity={0.02} />
          </linearGradient>
        </defs>
        {model.weightTicks.map((w) => (
          <g key={`w${w}`}>
            <line x1={x0} x2={x1} y1={yW(w)} y2={yW(w)} stroke="var(--muted)" strokeOpacity={0.15} />
            <text x={x0 - 4} y={yW(w) + 3} fontSize={10} textAnchor="end" fill="var(--muted)">{Math.round(w)}</text>
          </g>
        ))}
        {timeTicks.map((t) => (
          <g key={`t${t}`}>
            <line x1={x(t)} x2={x(t)} y1={top} y2={y1} stroke="var(--muted)" strokeOpacity={0.15} />
            <text x={x(t)} y={height - 4} fontSize={10} textAnchor="middle" fill="var(--muted)">{mmss(t)}</text>
          </g>
        ))}
        {model.stepTimes.map((t, i) => <line key={`s${i}`} x1={x(t)} x2={x(t)} y1={top} y2={y1} stroke="var(--muted)" strokeOpacity={0.22} />)}
        {flowVisible && (
          <>
            {showFlowRange && recipe && (
              <rect x={x0} width={x1 - x0} y={yF(Math.min(recipe.flowMax, model.maxFlow))}
                height={Math.max(yF(Math.min(recipe.flowMin, model.maxFlow)) - yF(Math.min(recipe.flowMax, model.maxFlow)), 0)}
                fill="var(--flow)" fillOpacity={0.08} />
            )}
            <path d={area(model.flow, yF)} fill="var(--flow)" fillOpacity={0.16} />
            <path d={line(model.flow, yF)} fill="none" stroke="var(--flow)" strokeWidth={1.5} strokeLinejoin="round" />
            {model.flowTicks.map((f) => (
              <text key={`f${f}`} x={x1 + 4} y={yF(f) + 3} fontSize={10} fill="var(--flow)">{flowLabel(f)}</text>
            ))}
          </>
        )}
        {model.target.length > 1 && (
          <path d={line(model.target, yW)} fill="none" stroke="var(--muted)" strokeOpacity={0.55} strokeWidth={2} strokeDasharray="7 5" />
        )}
        <path d={area(model.weight, yW)} fill="url(#weightFill)" />
        <path d={line(model.weight, yW)} fill="none" stroke="var(--accent)" strokeWidth={3} strokeLinecap="round" strokeLinejoin="round" />
        {currentTime != null && (
          <line x1={x(currentTime)} x2={x(currentTime)} y1={top} y2={y1} stroke="var(--accent)" strokeOpacity={0.5} strokeWidth={1.5} strokeDasharray="2 3" />
        )}
      </svg>
      <div className="legend" style={{ marginTop: 6 }}>
        <span className="item"><span style={{ width: 14, height: 3, borderRadius: 2, background: 'var(--accent)' }} />Weight g</span>
        {recipe && <span className="item"><span style={{ width: 14, borderTop: '2px dashed var(--muted)' }} />Recipe</span>}
        <button className="item" style={{ opacity: flowVisible ? 1 : 0.45, fontSize: 11, color: 'var(--muted)' }} aria-pressed={flowVisible}
          onClick={() => settings.change((s) => ({ ...s, chartShowsFlow: !s.chartShowsFlow }))}>
          <span style={{ width: 14, height: 8, borderRadius: 2, border: '1px solid var(--flow)', background: `color-mix(in srgb, var(--flow) ${flowVisible ? 50 : 15}%, transparent)` }} />
          Flow g/s
        </button>
      </div>
      {flowVisible && showFlowRange && recipe && (
        <div className="tiny muted" style={{ marginTop: 2 }}>Shaded band: the recipe's target pour rate ({flowLabel(recipe.flowMin)}–{flowLabel(recipe.flowMax)} g/s)</div>
      )}
    </div>
  )
}

/** Espresso: pressure (bar) and pump flow (ml/s) on one 0–12 axis. Port of MachineChart.swift. */
export function MachineChart({ samples, targetPressure = null, currentTime = null, height = 140 }:
  { samples: MachineSample[]; targetPressure?: number | null; currentTime?: number | null; height?: number }) {
  const ref = useRef<HTMLDivElement>(null)
  const [width, setWidth] = useState(320)
  useEffect(() => {
    const element = ref.current
    if (!element) return
    const observer = new ResizeObserver(([entry]) => setWidth(Math.max(entry.contentRect.width, 100)))
    observer.observe(element)
    return () => observer.disconnect()
  }, [])
  const maxT = Math.max(samples.length ? samples[samples.length - 1].t : 0, currentTime ?? 0, 25) + 2
  const left = 24
  const top = 6
  const bottom = 18
  const x1 = width - 6
  const y1 = height - bottom
  const x = (t: number) => left + (t / maxT) * (x1 - left)
  const y = (v: number) => y1 - (Math.min(Math.max(v, 0), 12) / 12) * (y1 - top)
  const path = (points: [number, number][]) => points.map(([t, v], i) => `${i ? 'L' : 'M'}${x(t).toFixed(1)},${y(v).toFixed(1)}`).join('')
  const pressureLine = path(samples.map((s) => [s.t, s.p]))
  const flowLine = path(samples.filter((s) => s.f != null).map((s) => [s.t, s.f as number]))
  const temps = samples.map((s) => s.c).filter((c): c is number => c != null)
  const avgTemp = temps.length ? temps.reduce((a, b) => a + b, 0) / temps.length : null
  const peak = samples.reduce((m, s) => Math.max(m, s.p), 0)
  const timeTicks: number[] = []
  for (let t = 0; t <= maxT; t += 10) timeTicks.push(t)
  return (
    <div ref={ref}>
      <svg width={width} height={height} role="img" aria-label={`Pressure curve, peak ${fmt1(peak)} bar`} style={{ display: 'block' }}>
        {[0, 3, 6, 9, 12].map((v) => (
          <g key={`p${v}`}>
            <line x1={left} x2={x1} y1={y(v)} y2={y(v)} stroke="var(--muted)" strokeOpacity={0.15} />
            <text x={left - 4} y={y(v) + 3} fontSize={10} textAnchor="end" fill="var(--muted)">{v}</text>
          </g>
        ))}
        {timeTicks.map((t) => <text key={`t${t}`} x={x(t)} y={height - 4} fontSize={10} textAnchor="middle" fill="var(--muted)">{mmss(t)}</text>)}
        {targetPressure != null && (
          <line x1={left} x2={x1} y1={y(targetPressure)} y2={y(targetPressure)} stroke="var(--accent)" strokeOpacity={0.35} strokeDasharray="4 4" />
        )}
        {flowLine && <path d={flowLine} fill="none" stroke="var(--flow)" strokeWidth={1.5} strokeLinejoin="round" />}
        {pressureLine && <path d={pressureLine} fill="none" stroke="var(--accent)" strokeWidth={2.5} strokeLinejoin="round" strokeLinecap="round" />}
        {currentTime != null && <line x1={x(currentTime)} x2={x(currentTime)} y1={top} y2={y1} stroke="var(--accent)" strokeOpacity={0.5} strokeDasharray="2 3" />}
      </svg>
      <div className="legend" style={{ marginTop: 6 }}>
        <span className="item"><span style={{ width: 14, height: 3, borderRadius: 2, background: 'var(--accent)' }} />Pressure bar</span>
        {flowLine && <span className="item"><span style={{ width: 14, height: 3, borderRadius: 2, background: 'var(--flow)' }} />Pump flow ml/s</span>}
        {avgTemp != null && <span className="item tnum">Ø {fmt1(avgTemp)} °C</span>}
      </div>
    </div>
  )
}
