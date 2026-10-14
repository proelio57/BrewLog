import {
  ArrowUp, BadgeCheck, CalendarDays, ChartLine, ChevronLeft, CircleCheck, CircleMinus, Coffee, Crosshair, Droplet, FileText, Flame,
  FlaskConical, Grip, Hourglass, Info, Leaf, Lock, LockOpen, Minus, Plus, RefreshCw, SlidersHorizontal, Sparkles, Star, Thermometer,
  Timer, TriangleAlert, Wind, Zap, type LucideIcon,
} from 'lucide-react'
import { type ReactNode, useEffect, useState } from 'react'
import type { FindingLevel } from '../analysis/analyzer'
import { formatNumber, parseNumber } from '../domain/format'
import type { TasteFeedback } from '../domain/models'
import type { StepKind, TasteProfile } from '../domain/recipe'
import { clamped } from '../domain/validation'

export function Card({ children, onClick, className = '', style }: { children: ReactNode; onClick?: () => void; className?: string; style?: React.CSSProperties }) {
  return (
    <div className={`card ${onClick ? 'clickable' : ''} ${className}`} onClick={onClick} style={style}
      role={onClick ? 'button' : undefined} tabIndex={onClick ? 0 : undefined}
      onKeyDown={onClick ? (e) => { if (e.key === 'Enter') onClick() } : undefined}>
      {children}
    </div>
  )
}

export function SectionHeader({ title, trailing }: { title: string; trailing?: string }) {
  return (
    <div className="section-header">
      <span>{title}</span>
      {trailing && <span>{trailing}</span>}
    </div>
  )
}

export function TopBar({ title, onBack, actions, center }: { title: string; onBack?: () => void; actions?: ReactNode; center?: boolean }) {
  return (
    <header className={`topbar ${center ? 'center' : ''}`}>
      {onBack && <button className="icon-btn" onClick={onBack} aria-label="Back"><ChevronLeft size={26} /></button>}
      <h1>{title}</h1>
      {actions}
    </header>
  )
}

export function Stat({ value, label, icon: Icon }: { value: string; label: string; icon?: LucideIcon }) {
  return (
    <div className="stat">
      <div className="value">{Icon && <Icon size={14} className="muted" />}<span className="ellipsis tnum">{value}</span></div>
      <div className="label">{label}</div>
    </div>
  )
}

const TASTE_COLORS = { acidity: '#FFCC00', sweetness: '#FF9500', body: '#A2845E', clarity: '#30B0C7' }

export function TasteBars({ profile }: { profile: TasteProfile }) {
  const rows: [string, keyof TasteProfile][] = [['Acidity', 'acidity'], ['Sweetness', 'sweetness'], ['Body', 'body'], ['Clarity', 'clarity']]
  return (
    <div className="row" style={{ flexDirection: 'column', alignItems: 'stretch', gap: 8 }}>
      {rows.map(([label, key]) => (
        <div className="taste-row" key={key}>
          <span className="name">{label}</span>
          <span className="bars">
            {[1, 2, 3, 4, 5].map((i) => <span key={i} style={i <= profile[key] ? { background: TASTE_COLORS[key] } : undefined} />)}
          </span>
        </div>
      ))}
    </div>
  )
}

export function StarRating({ rating, onChange }: { rating: number; onChange: (rating: number) => void }) {
  return (
    <div className="row" style={{ justifyContent: 'center', gap: 10 }}>
      {[1, 2, 3, 4, 5].map((i) => (
        <button key={i} aria-label={`${i} stars`} onClick={() => onChange(rating === i ? 0 : i)}>
          <Star size={32} fill={i <= rating ? 'var(--star)' : 'none'} color={i <= rating ? 'var(--star)' : 'var(--muted)'} strokeWidth={1.5} />
        </button>
      ))}
    </div>
  )
}

export function Stars({ rating }: { rating: number }) {
  return (
    <span className="row" style={{ gap: 1 }}>
      {[1, 2, 3, 4, 5].map((i) => <Star key={i} size={11} fill={i <= rating ? 'var(--star)' : 'none'} color={i <= rating ? 'var(--star)' : 'var(--muted)'} />)}
    </span>
  )
}

export function Chip({ title, selected, onClick, icon: Icon, green }: { title: string; selected: boolean; onClick: () => void; icon?: LucideIcon; green?: boolean }) {
  return (
    <button className={`chip ${selected ? 'selected' : ''} ${green ? 'green' : ''}`} onClick={onClick} aria-pressed={selected}>
      {Icon && <Icon size={16} />}{title}
    </button>
  )
}

export interface Option { id: string; name: string }

/** "Label ……… Selection ⌃⌄" using a native select (accessible, native picker on phones). */
export function SelectRow({ label, icon: Icon, options, value, onChange, noneLabel = 'None' }:
  { label: string; icon: LucideIcon; options: Option[]; value: string | null; onChange: (id: string | null) => void; noneLabel?: string }) {
  return (
    <div className="select-row">
      <span className="label"><Icon size={18} />{label}</span>
      <select aria-label={label} value={value ?? ''} onChange={(e) => onChange(e.target.value || null)}>
        <option value="">{noneLabel}</option>
        {options.map((o) => <option key={o.id} value={o.id}>{o.name}</option>)}
      </select>
    </div>
  )
}

export function Stepper({ label, value, onMinus, onPlus, icon: Icon }: { label: string; value: string; onMinus: () => void; onPlus: () => void; icon?: LucideIcon }) {
  return (
    <div className="row">
      {Icon && <Icon size={18} className="muted" />}
      <span className="grow">{label}</span>
      <div className="stepper">
        <button className="round" onClick={onMinus} aria-label={`Less ${label}`}><Minus size={18} /></button>
        <span className="value tnum">{value}</span>
        <button className="round" onClick={onPlus} aria-label={`More ${label}`}><Plus size={18} /></button>
      </div>
    </div>
  )
}

export function Toggle({ label, detail, checked, onChange }: { label: string; detail?: string; checked: boolean; onChange: (checked: boolean) => void }) {
  return (
    <label className="row" style={{ cursor: 'pointer' }}>
      <span className="grow">
        <span>{label}</span>
        {detail && <span className="small muted" style={{ display: 'block' }}>{detail}</span>}
      </span>
      <span className="switch">
        <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} />
        <span />
      </span>
    </label>
  )
}

/** Decimal input that accepts "," and "." and reports parsed, clamped values. */
export function NumberInput({ label, value, onChange, min = 0, max = 100_000, decimals = 1, className = 'input', style, placeholder }:
  { label: string; value: number | null; onChange: (value: number | null) => void; min?: number; max?: number; decimals?: number; className?: string; style?: React.CSSProperties; placeholder?: string }) {
  const [text, setText] = useState(value != null ? formatNumber(value, decimals) : '')
  useEffect(() => {
    if (parseNumber(text) !== value) setText(value != null ? formatNumber(value, decimals) : '')
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [value])
  return (
    <input className={className} style={style} aria-label={label} placeholder={placeholder ?? label} inputMode="decimal" value={text}
      onChange={(e) => {
        const next = e.target.value.replace(/[^0-9.,]/g, '').slice(0, 10)
        setText(next)
        const parsed = parseNumber(next)
        onChange(parsed == null ? null : clamped(parsed, min, max))
      }} />
  )
}

export function Field({ label, children }: { label: string; children: ReactNode }) {
  return <div className="field"><label>{label}</label>{children}</div>
}

export function TextInput({ label, value, onChange, max = 80, multiline }: { label: string; value: string; onChange: (value: string) => void; max?: number; multiline?: boolean }) {
  return multiline
    ? <textarea className="input" aria-label={label} placeholder={label} value={value} onChange={(e) => onChange(e.target.value.slice(0, max))} />
    : <input className="input" aria-label={label} placeholder={label} value={value} onChange={(e) => onChange(e.target.value.slice(0, max))} />
}

export function Sheet({ children, onClose }: { children: ReactNode; onClose: () => void }) {
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [onClose])
  return (
    <div className="sheet-backdrop" onClick={onClose}>
      <div className="sheet" onClick={(e) => e.stopPropagation()} role="dialog" aria-modal="true">
        <div className="grabber" />
        {children}
      </div>
    </div>
  )
}

export function EmptyState({ icon: Icon, title, message, action }: { icon: LucideIcon; title: string; message: string; action?: ReactNode }) {
  return (
    <div className="empty">
      <Icon size={40} className="muted" />
      <div className="headline">{title}</div>
      <div className="muted">{message}</div>
      {action}
    </div>
  )
}

export function IconCircle({ icon: Icon, color, size = 40, strong }: { icon: LucideIcon; color: string; size?: number; strong?: boolean }) {
  return (
    <span className="icon-circle" style={{ width: size, height: size, background: `color-mix(in srgb, ${color} ${strong ? 22 : 14}%, transparent)`, color }}>
      <Icon size={size * 0.5} />
    </span>
  )
}

export function confirmAction(message: string): boolean {
  return window.confirm(message)
}

// Icon mapping (SF Symbols on iOS → lucide)

export const FEEDBACK_ICONS: Record<TasteFeedback, LucideIcon> = {
  perfect: BadgeCheck, sour: FlaskConical, bitter: Flame, weak: Droplet, strong: Zap, astringent: Leaf, flat: CircleMinus,
}

export const STEP_ICONS: Record<StepKind, LucideIcon> = {
  bloom: Sparkles, pour: Droplet, swirl: RefreshCw, stir: Wind, closeValve: Lock, openValve: LockOpen, remove: ArrowUp,
}

export const FINDING_STYLE: Record<FindingLevel, { icon: LucideIcon; color: string }> = {
  good: { icon: CircleCheck, color: 'var(--good)' },
  info: { icon: Info, color: 'var(--info)' },
  warning: { icon: TriangleAlert, color: 'var(--warn)' },
}

export function suggestionIcon(key: string): LucideIcon {
  if (key === 'grind') return SlidersHorizontal
  if (key.startsWith('temp')) return Thermometer
  if (key === 'bloom') return Sparkles
  if (key.startsWith('ratio') || key === 'dose-up') return Droplet
  if (key === 'evenness' || key === 'walls') return Crosshair
  if (key === 'fines') return Grip
  if (key.startsWith('filter')) return FileText
  if (key === 'drawdown') return Hourglass
  if (key === 'rest' || key === 'fresh') return CalendarDays
  if (key.startsWith('steep')) return Timer
  if (key === 'history' || key === 'repeat') return Star
  if (key === 'agitation-up') return RefreshCw
  if (key === 'gentle' || key === 'rinse' || key === 'water') return Droplet
  if (key === 'clarity') return ChartLine
  return Coffee
}
