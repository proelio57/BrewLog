// Formatting helpers. Swift's String(format:) always uses "." as decimal separator, so these do too.

export const fmt0 = (value: number): string => noiseFreeZero(value.toFixed(0))
export const fmt1 = (value: number): string => noiseFreeZero(value.toFixed(1))

/** "-0" / "-0.0" → "0" / "0.0" */
function noiseFreeZero(text: string): string {
  return /^-0(\.0+)?$/.test(text) ? text.slice(1) : text
}

/** Swift's `.rounded()`: round half away from zero. */
export function roundHalfAway(x: number): number {
  return x >= 0 ? Math.floor(x + 0.5) : -Math.floor(-x + 0.5)
}

/** Seconds as m:ss. */
export function mmss(seconds: number): string {
  const total = Math.floor(seconds)
  const sign = total < 0 ? '-' : ''
  const value = Math.abs(total)
  return `${sign}${Math.floor(value / 60)}:${String(value % 60).padStart(2, '0')}`
}

/** Avoids a flickering "-0.0" from scale noise around zero. */
export const noiseFree = (value: number): number => (Math.abs(value) < 0.05 ? 0 : value)
export const grams = (value: number): string => `${fmt0(noiseFree(value))} g`
export const grams1 = (value: number): string => `${fmt1(noiseFree(value))} g`
export const scaleReadout = (value: number): string => fmt1(noiseFree(value))

export function newId(): string {
  // crypto.randomUUID only exists on https/localhost; getRandomValues also works on plain http (e.g. opened over Wi-Fi).
  const c: Partial<Crypto> | undefined = typeof crypto !== 'undefined' ? crypto : undefined
  if (c?.randomUUID) return c.randomUUID()
  const random = c?.getRandomValues
    ? Array.from(c.getRandomValues(new Uint8Array(12)), (b) => b.toString(16).padStart(2, '0')).join('')
    : Math.random().toString(36).slice(2, 14)
  return `id-${Date.now().toString(36)}-${random}`
}

export function formatDate(millis: number, withTime = false): string {
  return new Date(millis).toLocaleString(undefined, withTime ? { dateStyle: 'medium', timeStyle: 'short' } : { dateStyle: 'medium' })
}

/** Trims "24.50" → "24.5", "24.00" → "24". */
export function formatNumber(value: number, decimals: number): string {
  const text = value.toFixed(decimals)
  return text.includes('.') ? text.replace(/0+$/, '').replace(/\.$/, '') : text
}

/** Accepts "," and "." as decimal separator. */
export function parseNumber(text: string): number | null {
  const value = Number(text.replace(',', '.'))
  return text.trim() !== '' && Number.isFinite(value) ? value : null
}
