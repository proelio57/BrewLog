import { Coffee, Search, Trash2 } from 'lucide-react'
import { useState } from 'react'
import { navigate, repository } from '../app'
import { useStore } from '../data/store'
import { fmt1, formatDate, mmss } from '../domain/format'
import { beanDisplayName, grindDisplay, isReviewed } from '../domain/models'
import { Card, EmptyState, FEEDBACK_ICONS, Stars, Stat, TopBar } from '../ui/components'

export function Journal() {
  const data = useStore(repository.data)
  const [search, setSearch] = useState('')
  const beans = new Map(data.beans.map((b) => [b.id, b]))
  const brews = [...data.brews].sort((a, b) => b.date - a.date)
  const query = search.trim().toLowerCase()
  const filtered = query ? brews.filter((brew) => {
    const bean = brew.beanId ? beans.get(brew.beanId) : undefined
    return [brew.recipeName, bean?.name, bean?.roaster, brew.notes].some((text) => text?.toLowerCase().includes(query))
  }) : brews
  const rated = brews.filter((b) => b.rating > 0)
  const weekAgo = Date.now() - 7 * 86_400_000

  return (
    <div className="screen with-tabs">
      <TopBar title="Journal" />
      {brews.length === 0 ? (
        <EmptyState icon={Coffee} title="No brews yet" message="Every brew you finish is saved here with its pour curve, rating and suggestions." />
      ) : (
        <div className="content">
          <div className="card search-bar">
            <Search size={18} className="muted" />
            <input className="input" style={{ border: 'none', background: 'transparent' }} aria-label="Search" placeholder="Recipe, bean, roaster, notes"
              value={search} onChange={(e) => setSearch(e.target.value.slice(0, 80))} />
          </div>
          {!query && (
            <Card>
              <div className="stats">
                <Stat value={String(brews.length)} label="Brews" />
                <Stat value={String(brews.filter((b) => b.date > weekAgo).length)} label="This week" />
                <Stat value={rated.length ? `${fmt1(rated.reduce((s, b) => s + b.rating, 0) / rated.length)}★` : '–'} label="Avg rating" />
              </div>
            </Card>
          )}
          {filtered.map((brew) => {
            const bean = brew.beanId ? beans.get(brew.beanId) : undefined
            const perfect = brew.feedback.includes('perfect')
            const tint = perfect ? 'var(--good)' : brew.feedback.length ? 'var(--warn)' : 'var(--accent)'
            const Icon = brew.feedback.length ? FEEDBACK_ICONS[brew.feedback[0]] : Coffee
            return (
              <Card key={brew.id} onClick={() => navigate(`/brews/${brew.id}`)}>
                <div className="row">
                  <span className="icon-circle" style={{ width: 46, height: 46, borderRadius: 12, background: `color-mix(in srgb, ${tint} 15%, transparent)`, color: tint }}>
                    <Icon size={22} />
                  </span>
                  <div className="grow">
                    <div className="title">{brew.recipeName}</div>
                    <div className="small muted ellipsis">{bean ? beanDisplayName(bean) : 'No beans'}</div>
                    <div className="tiny muted">{[formatDate(brew.date), mmss(brew.totalTime), grindDisplay(brew) || null].filter(Boolean).join(' · ')}</div>
                  </div>
                  <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', gap: 6 }}>
                    {brew.rating > 0 && <Stars rating={brew.rating} />}
                    {!isReviewed(brew) && <span className="tiny accent" style={{ fontWeight: 700 }}>Review</span>}
                    <button className="icon-btn" aria-label="Delete brew" onClick={(e) => {
                      e.stopPropagation()
                      if (window.confirm(`Delete this brew (${brew.recipeName}, ${formatDate(brew.date, true)})?`)) repository.deleteBrew(brew.id)
                    }}><Trash2 size={16} className="muted" /></button>
                  </div>
                </div>
              </Card>
            )
          })}
        </div>
      )}
    </div>
  )
}
