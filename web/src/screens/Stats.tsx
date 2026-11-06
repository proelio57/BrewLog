import { ArrowDownRight, ArrowRight, ArrowUpRight, Sparkles } from 'lucide-react'
import { useMemo, useState } from 'react'
import { repository } from '../app'
import { BrewStats, type StatsGroup, type StatsPoint, type StatsSummary, type StatsTrend, type StatsWeek } from '../analysis/brewStats'
import { useStore } from '../data/store'
import { fmt1, formatDate, mmss } from '../domain/format'
import { Card, Chip, SectionHeader, Stat } from '../ui/components'

export function StatsScreen() {
  const data = useStore(repository.data)
  const [method, setMethod] = useState<'pourOver' | 'espresso'>('pourOver')
  const [rangeDays, setRangeDays] = useState<number>(90)

  const espresso = method === 'espresso'
  const beansMap = useMemo(() => new Map(data.beans.map((b) => [b.id, b.name])), [data.beans])

  const summary: StatsSummary = useMemo(() => {
    const entries = data.brews.map((b) => BrewStats.fromBrew(b, b.beanId ? beansMap.get(b.beanId) ?? '' : ''))
    const now = Date.now()
    const since = rangeDays > 0 ? now - rangeDays * 86_400_000 : null
    return BrewStats.summary(entries, espresso, since, now)
  }, [data.brews, espresso, rangeDays, beansMap])

  return (
    <div className="stats-screen">
      <div className="chips" style={{ marginBottom: 8 }}>
        <Chip title="Pour-over" selected={!espresso} onClick={() => setMethod('pourOver')} />
        <Chip title="Espresso" selected={espresso} onClick={() => setMethod('espresso')} />
      </div>
      <div className="chips" style={{ marginBottom: 16 }}>
        <Chip title="30 days" selected={rangeDays === 30} onClick={() => setRangeDays(30)} />
        <Chip title="90 days" selected={rangeDays === 90} onClick={() => setRangeDays(90)} />
        <Chip title="All" selected={rangeDays === 0} onClick={() => setRangeDays(0)} />
      </div>

      <Card>
        <div className="stats">
          <Stat value={String(summary.brews)} label={espresso ? 'Shots' : 'Brews'} />
          <Stat value={summary.averageRating != null ? `${fmt1(summary.averageRating)}★` : '–'} label="Avg rating" />
          <TrendStat trend={summary.trend} />
        </div>
      </Card>

      <SectionHeader title="Activity" />
      <Card>
        {summary.brews === 0 ? <EmptyStats /> : <WeeklyBrewsChart weeks={summary.weeks} />}
      </Card>

      <SectionHeader title="Rating" />
      <Card>
        {summary.brews === 0 ? <EmptyStats /> : <RatingTrendChart weeks={summary.weeks} trend={summary.trend} />}
      </Card>

      <SectionHeader title={espresso ? 'Shots' : 'Brewing'} />
      <Card>
        {summary.brews === 0 ? (
          <EmptyStats />
        ) : espresso ? (
          <EspressoStatsSection summary={summary} />
        ) : (
          <PourOverStatsSection summary={summary} />
        )}
      </Card>

      <SectionHeader title="Beans" />
      <Card>
        <GroupList groups={summary.beans} showsBest={true} />
      </Card>

      <SectionHeader title="Recipes" />
      <Card>
        <GroupList groups={summary.recipes} showsBest={false} />
      </Card>
    </div>
  )
}

function TrendStat({ trend }: { trend: StatsTrend | null }) {
  if (!trend) return <Stat value="–" label="Trend" />
  const icon = trend === 'improving' ? ArrowUpRight : trend === 'steady' ? ArrowRight : ArrowDownRight
  const title = trend === 'improving' ? 'Improving' : trend === 'steady' ? 'Steady' : 'Declining'
  return <Stat value={title} label="Trend" icon={icon} />
}

function PourOverStatsSection({ summary }: { summary: StatsSummary }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      <StatRow title="Average time" value={summary.averageTime != null ? mmss(summary.averageTime) : '–'} />
      <StatRow
        title="Against the recipe"
        value={summary.averageTimeDelta != null ? BrewStats.signedSeconds(summary.averageTimeDelta) : '–'}
      />
      <StatRow title="Average ratio" value={summary.averageRatio != null ? `1:${fmt1(summary.averageRatio)}` : '–'} />
      <StatRow
        title="Extraction"
        value={summary.averageExtraction != null ? `${fmt1(summary.averageExtraction)} %` : '–'}
        detail={summary.extractionCount > 0 ? `${summary.extractionCount} with TDS` : 'Log TDS to see it'}
      />
    </div>
  )
}

function EspressoStatsSection({ summary }: { summary: StatsSummary }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
      <StatRow title="Shot time" value={summary.averageTime != null ? `${Math.round(summary.averageTime)} s` : '–'} />
      <StatRow title="Ratio" value={summary.averageRatio != null ? `1:${fmt1(summary.averageRatio)}` : '–'} />
      <StatRow
        title="First drops"
        value={summary.averageFirstDrops != null ? `${Math.round(summary.averageFirstDrops)} s` : '–'}
        detail={`${summary.firstDropsCount} of ${summary.brews} shots`}
      />
      <StatRow
        title="Peak pressure"
        value={summary.averagePeakPressure != null ? `${fmt1(summary.averagePeakPressure)} bar` : '–'}
        detail={`${summary.pressureCount} of ${summary.brews} shots`}
      />
      <StatRow
        title="Signs of channeling"
        value={`${summary.channelingShots} shot${summary.channelingShots === 1 ? '' : 's'}`}
        detail="Sudden pressure drop or first drops under 3 s"
      />
      {summary.points.length > 0 && (
        <>
          <div className="divider" />
          <ShotScatterChart points={summary.points} />
        </>
      )}
    </div>
  )
}

function StatRow({ title, value, detail }: { title: string; value: string; detail?: string }) {
  return (
    <div className="row" style={{ alignItems: 'baseline' }}>
      <div className="grow">
        <div style={{ fontSize: 14 }}>{title}</div>
        {detail && <div className="small muted">{detail}</div>}
      </div>
      <div style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{value}</div>
    </div>
  )
}

function GroupList({ groups, showsBest }: { groups: StatsGroup[]; showsBest: boolean }) {
  if (groups.length === 0) return <EmptyStats />
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
      {groups.slice(0, 10).map((g, i) => {
        const parts = [`${g.brews} brew${g.brews === 1 ? '' : 's'}`]
        if (showsBest) {
          if (g.bestRecipe) parts.push(`best: ${g.bestRecipe}`)
          if (g.bestGrind) parts.push(`grind ${g.bestGrind}`)
        }
        parts.push(`last ${formatDate(g.lastBrewed)}`)
        return (
          <div key={g.id || i} style={{ borderBottom: i < groups.length - 1 ? '1px solid var(--fill)' : 'none', paddingBottom: 8 }}>
            <div className="row">
              <span className="grow" style={{ fontWeight: 600, fontSize: 14 }}>
                {g.name}
              </span>
              <span style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>
                {g.averageRating != null ? `${fmt1(g.averageRating)}★` : '–'}
              </span>
            </div>
            <div className="tiny muted">{parts.join(' · ')}</div>
          </div>
        )
      })}
    </div>
  )
}

function EmptyStats() {
  return <div className="small muted">No brews in this range yet.</div>
}

/** 12-week activity bar chart */
export function WeeklyBrewsChart({ weeks }: { weeks: StatsWeek[] }) {
  const [selectedIdx, setSelectedIdx] = useState<number | null>(null)
  const maxBrews = Math.max(1, ...weeks.map((w) => w.brews))
  const height = 120
  const width = 300
  const paddingLeft = 24
  const paddingRight = 12
  const paddingTop = 20
  const paddingBottom = 22
  const innerW = width - paddingLeft - paddingRight
  const innerH = height - paddingTop - paddingBottom
  const barWidth = (innerW / weeks.length) * 0.65
  const step = innerW / weeks.length

  const selectedWeek = selectedIdx != null ? weeks[selectedIdx] : null

  return (
    <div>
      {selectedWeek && (
        <div className="tiny muted" style={{ textAlign: 'center', marginBottom: 4, fontWeight: 600 }}>
          {formatDate(selectedWeek.start)}: {selectedWeek.brews} brew{selectedWeek.brews === 1 ? '' : 's'}
        </div>
      )}
      <svg viewBox={`0 0 ${width} ${height}`} style={{ width: '100%', height, display: 'block' }}>
        {/* Horizontal grid line */}
        <line x1={paddingLeft} x2={width - paddingRight} y1={paddingTop + innerH} y2={paddingTop + innerH} stroke="var(--fill)" strokeWidth={1} />
        {/* Bars */}
        {weeks.map((week, i) => {
          const barH = (week.brews / maxBrews) * innerH
          const x = paddingLeft + i * step + (step - barWidth) / 2
          const y = paddingTop + innerH - barH
          const isSelected = selectedIdx === i
          const fill = isSelected || selectedIdx == null ? 'var(--accent)' : 'var(--accent-soft)'
          return (
            <g key={week.start} onClick={() => setSelectedIdx(selectedIdx === i ? null : i)} style={{ cursor: 'pointer' }}>
              <rect x={x} y={y} width={barWidth} height={Math.max(barH, 2)} rx={3} fill={fill} />
              {i % 3 === 0 && (
                <text x={x + barWidth / 2} y={height - 4} fontSize={9} fill="var(--muted)" textAnchor="middle">
                  {new Date(week.start).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })}
                </text>
              )}
            </g>
          )
        })}
      </svg>
    </div>
  )
}

/** Weekly average rating trend chart */
export function RatingTrendChart({ weeks, trend }: { weeks: StatsWeek[]; trend: StatsTrend | null }) {
  const [selectedIdx, setSelectedIdx] = useState<number | null>(null)
  const ratedWeeks = useMemo(() => weeks.map((w, idx) => ({ ...w, origIdx: idx })).filter((w) => w.averageRating != null), [weeks])

  if (ratedWeeks.length < 3) {
    return <div className="small muted">Rate brews in 3 different weeks to see a trend.</div>
  }

  const height = 130
  const width = 300
  const paddingLeft = 24
  const paddingRight = 16
  const paddingTop = 16
  const paddingBottom = 22
  const innerW = width - paddingLeft - paddingRight
  const innerH = height - paddingTop - paddingBottom

  // Rating 1 to 5
  const getY = (rating: number) => paddingTop + innerH - ((rating - 1) / 4) * innerH
  const getX = (origIdx: number) => paddingLeft + (origIdx / (weeks.length - 1)) * innerW

  const points = ratedWeeks.map((w) => ({
    x: getX(w.origIdx),
    y: getY(w.averageRating ?? 0),
    rating: w.averageRating ?? 0,
    origIdx: w.origIdx,
    start: w.start,
  }))

  const pathD = points.map((p, i) => `${i === 0 ? 'M' : 'L'} ${p.x.toFixed(1)} ${p.y.toFixed(1)}`).join(' ')
  const selectedPoint = selectedIdx != null ? points.find((p) => p.origIdx === selectedIdx) : null

  return (
    <div>
      <div className="row" style={{ marginBottom: 6 }}>
        <Sparkles size={16} className="accent" />
        <span className="small muted" style={{ fontWeight: 600 }}>
          {trend === 'improving' ? 'Rating is improving' : trend === 'steady' ? 'Rating is steady' : 'Rating is declining'}
        </span>
      </div>
      {selectedPoint && (
        <div className="tiny muted" style={{ textAlign: 'center', marginBottom: 4, fontWeight: 600 }}>
          {formatDate(selectedPoint.start)}: {fmt1(selectedPoint.rating)}★
        </div>
      )}
      <svg viewBox={`0 0 ${width} ${height}`} style={{ width: '100%', height, display: 'block' }}>
        {/* Y-axis grid lines (1, 3, 5) */}
        {[1, 3, 5].map((r) => {
          const y = getY(r)
          return (
            <g key={r}>
              <line x1={paddingLeft} x2={width - paddingRight} y1={y} y2={y} stroke="var(--fill)" strokeWidth={1} />
              <text x={paddingLeft - 6} y={y + 3} fontSize={9} fill="var(--muted)" textAnchor="end">
                {r}
              </text>
            </g>
          )
        })}
        {/* Line */}
        <path d={pathD} fill="none" stroke="var(--accent)" strokeWidth={2} strokeLinecap="round" strokeLinejoin="round" />
        {/* Points */}
        {points.map((p) => (
          <circle
            key={p.origIdx}
            cx={p.x}
            cy={p.y}
            r={selectedIdx === p.origIdx ? 6 : 4}
            fill="var(--accent)"
            stroke="#fff"
            strokeWidth={1.5}
            onClick={() => setSelectedIdx(selectedIdx === p.origIdx ? null : p.origIdx)}
            style={{ cursor: 'pointer' }}
          />
        ))}
        {/* X axis labels */}
        {weeks.map((week, i) => {
          if (i % 3 !== 0) return null
          const x = getX(i)
          return (
            <text key={week.start} x={x} y={height - 4} fontSize={9} fill="var(--muted)" textAnchor="middle">
              {new Date(week.start).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })}
            </text>
          )
        })}
      </svg>
    </div>
  )
}

/** Scatter plot for espresso shots: time vs ratio, colored by rating */
export function ShotScatterChart({ points }: { points: StatsPoint[] }) {
  const [selectedIdx, setSelectedIdx] = useState<number | null>(null)
  if (points.length === 0) return null

  const height = 150
  const width = 300
  const paddingLeft = 32
  const paddingRight = 16
  const paddingTop = 16
  const paddingBottom = 24
  const innerW = width - paddingLeft - paddingRight
  const innerH = height - paddingTop - paddingBottom

  const times = points.map((p) => p.time)
  const ratios = points.map((p) => p.ratio)
  const minTime = Math.max(10, Math.floor(Math.min(...times) / 5) * 5)
  const maxTime = Math.max(45, Math.ceil(Math.max(...times) / 5) * 5)
  const minRatio = Math.max(1.0, Math.floor(Math.min(...ratios) * 2) / 2)
  const maxRatio = Math.max(3.0, Math.ceil(Math.max(...ratios) * 2) / 2)

  const getX = (t: number) => paddingLeft + ((t - minTime) / (maxTime - minTime || 1)) * innerW
  const getY = (r: number) => paddingTop + innerH - ((r - minRatio) / (maxRatio - minRatio || 1)) * innerH

  const colorFor = (rating: number) => {
    if (rating >= 5) return 'var(--good)'
    if (rating === 4) return 'var(--accent)'
    if (rating === 3) return 'var(--warn)'
    if (rating > 0) return 'var(--danger)'
    return 'var(--muted)'
  }

  const selected = selectedIdx != null ? points[selectedIdx] : null

  return (
    <div>
      <div className="small muted" style={{ fontWeight: 600, marginBottom: 4 }}>
        Shot time vs ratio (darker = higher rating)
      </div>
      {selected && (
        <div className="tiny muted" style={{ textAlign: 'center', marginBottom: 4 }}>
          {Math.round(selected.time)}s · 1:{fmt1(selected.ratio)} {selected.rating > 0 ? `· ${selected.rating}★` : ''}
        </div>
      )}
      <svg viewBox={`0 0 ${width} ${height}`} style={{ width: '100%', height, display: 'block' }}>
        {/* Grid lines */}
        <line x1={paddingLeft} x2={width - paddingRight} y1={paddingTop + innerH} y2={paddingTop + innerH} stroke="var(--fill)" strokeWidth={1} />
        <line x1={paddingLeft} x2={paddingLeft} y1={paddingTop} y2={paddingTop + innerH} stroke="var(--fill)" strokeWidth={1} />
        {/* Y ticks (ratios) */}
        {[minRatio, (minRatio + maxRatio) / 2, maxRatio].map((r) => {
          const y = getY(r)
          return (
            <text key={r} x={paddingLeft - 4} y={y + 3} fontSize={9} fill="var(--muted)" textAnchor="end">
              1:{fmt1(r)}
            </text>
          )
        })}
        {/* X ticks (time) */}
        {[minTime, (minTime + maxTime) / 2, maxTime].map((t) => {
          const x = getX(t)
          return (
            <text key={t} x={x} y={height - 4} fontSize={9} fill="var(--muted)" textAnchor="middle">
              {Math.round(t)}s
            </text>
          )
        })}
        {/* Scatter dots */}
        {points.map((p, i) => (
          <circle
            key={i}
            cx={getX(p.time)}
            cy={getY(p.ratio)}
            r={selectedIdx === i ? 6 : 4}
            fill={colorFor(p.rating)}
            stroke="#fff"
            strokeWidth={1}
            onClick={() => setSelectedIdx(selectedIdx === i ? null : i)}
            style={{ cursor: 'pointer', opacity: selectedIdx == null || selectedIdx === i ? 0.9 : 0.4 }}
          />
        ))}
      </svg>
    </div>
  )
}
