import { describe, expect, it } from 'vitest'
import { analyze, clarityAdvice, type AnalysisInput } from '../src/analysis/analyzer'
import { BrewSession, type BrewCue } from '../src/brewing/brewSession'
import { acceptedDose, doseProgress, doseStatus, recipeForDose, stableWeight } from '../src/brewing/dosing'
import { PRESET_RECIPES } from '../src/domain/library'
import { DEFAULT_SETTINGS } from '../src/domain/models'
import type { Recipe } from '../src/domain/recipe'
import { clearerAlternative, matchesMethod } from '../src/domain/recipeFilter'
import type { ScaleCommands } from '../src/scale/scaleManager'

// Same scenarios as DosingAndAdviceTests.swift.

const preset = (id: string): Recipe => PRESET_RECIPES.find((r) => r.id === id)!

describe('weighing the beans', () => {
  it('rates the reading against the dose', () => {
    expect(doseStatus(0.2, 15)).toBe('empty')
    expect(doseStatus(12, 15)).toBe('under')
    expect(doseStatus(14.8, 15)).toBe('onTarget')
    expect(doseStatus(15.2, 15)).toBe('onTarget')
    expect(doseStatus(15.5, 15)).toBe('over')
    expect(doseStatus(NaN, 15)).toBe('empty')
  })

  it('clamps the progress', () => {
    expect(doseProgress(7.5, 15)).toBeCloseTo(0.5)
    expect(doseProgress(20, 15)).toBe(1)
    expect(doseProgress(-2, 15)).toBe(0)
    expect(doseProgress(5, 0)).toBe(0)
  })

  it('keeps the reading or falls back to the planned dose', () => {
    expect(acceptedDose(15.26, 15)).toBe(15.3)
    expect(acceptedDose(0.1, 15)).toBe(15)
    expect(acceptedDose(900, 15)).toBe(15)
    expect(acceptedDose(Infinity, 15)).toBe(15)
  })

  class FakeScale implements ScaleCommands {
    commands: string[] = []
    isReady = true
    tare() { this.commands.push('tare') }
    prepareForBrew() { this.commands.push('prepare') }
    prepareForDosing() { this.commands.push('dose') }
    dosingFinished() { this.commands.push('doseDone') }
    brewStarted() { this.commands.push('start') }
    brewFinished() { this.commands.push('stop') }
  }

  it('starts by weighing, pings once and Ready keeps the settled dose', () => {
    const recipe = preset('everyday-3-pour')
    const scale = new FakeScale()
    const cues: BrewCue[] = []
    let now = 0
    const session = new BrewSession(recipe, scale, () => DEFAULT_SETTINGS, (c) => cues.push(c), () => now)
    session.prepare()
    session.prepare()
    expect(session.phase).toBe('dosing')
    expect(scale.commands).toEqual(['dose'])
    for (let grams = 0; grams <= recipe.dose + 0.1; grams += 0.5) {
      now += 100
      session.ingest(grams, now)
    }
    // Settles 0.1 g over the plan, then the cup is lifted off.
    for (let i = 0; i < 12; i++) { now += 100; session.ingest(recipe.dose + 0.1, now) }
    for (let i = 0; i < 5; i++) { now += 100; session.ingest(0, now) }
    expect(cues).toEqual(['target'])
    // Ready straight from weighing keeps the settled dose; under 0.5 g off the recipe stays.
    session.ready()
    expect(session.phase).toBe('armed')
    expect(session.dose).toBeCloseTo(recipe.dose + 0.1, 5)
    expect(session.recipe).toBe(recipe)
    expect(scale.commands).toEqual(['dose', 'doseDone', 'prepare'])
  })

  it('scales the recipe from half a gram off', () => {
    const recipe = preset('everyday-3-pour')
    const scale = new FakeScale()
    let now = 0
    const session = new BrewSession(recipe, scale, () => DEFAULT_SETTINGS, () => undefined, () => now)
    session.prepare()
    session.tareDose()
    expect(scale.commands).toEqual(['dose', 'tare'])
    for (let i = 0; i < 12; i++) { now += 100; session.ingest(recipe.dose + 1, now) }
    session.ready()
    expect(session.recipe.dose).toBeCloseTo(recipe.dose + 1, 5)
    expect(session.recipe.steps.map((s) => s.time)).toEqual(recipe.steps.map((s) => s.time))
    expect(session.plannedRecipe).toBe(recipe)
    expect(recipeForDose(recipe, recipe.dose + 0.4)).toBe(recipe)
  })

  it('a settled weight ignores lifting the cup', () => {
    const steady: [number, number][] = Array.from({ length: 10 }, (_, i) => [i * 100, i % 2 ? 15.05 : 15.15])
    expect(stableWeight(steady, 900)).toBeCloseTo(15.1, 2)
    const lifting: [number, number][] = Array.from({ length: 10 }, (_, i) => [i * 100, 15 - i * 1.5])
    expect(stableWeight(lifting, 900)).toBeNull()
    expect(stableWeight(steady.slice(0, 3), 200)).toBeNull()
  })

  it('skips weighing when switched off or without a scale', () => {
    const scale = new FakeScale()
    const off = new BrewSession(preset('everyday-3-pour'), scale, () => ({ ...DEFAULT_SETTINGS, weighBeansFirst: false }), () => undefined)
    off.prepare()
    expect(off.phase).toBe('preparing')
    scale.isReady = false
    const noScale = new BrewSession(preset('everyday-3-pour'), scale, () => DEFAULT_SETTINGS, () => undefined)
    noScale.prepare()
    expect(noScale.phase).toBe('preparing')
    expect(noScale.dose).toBe(preset('everyday-3-pour').dose)
  })
})

describe('recipe advice', () => {
  it('never suggests the brewed recipe', () => {
    for (const recipe of PRESET_RECIPES.filter((r) => r.method !== 'espresso')) {
      const alternative = clearerAlternative(recipe, PRESET_RECIPES)
      expect(alternative?.id).not.toBe(recipe.id)
      expect(alternative?.name).not.toBe(recipe.name)
      if (alternative) {
        expect(alternative.id.startsWith('template-')).toBe(false)
        expect(alternative.method).not.toBe('espresso')
        expect(matchesMethod(alternative, recipe.method === 'universal' ? null : recipe.method)).toBe(true)
      }
    }
  })

  it('points Rao V60 to another clear recipe and keeps the Switch on the Switch', () => {
    const rao = preset('rao-v60')
    const fromRao = clearerAlternative(rao, PRESET_RECIPES)!
    expect(fromRao.id).not.toBe(rao.id)
    expect(fromRao.taste.clarity).toBeGreaterThanOrEqual(rao.taste.clarity)
    const immersion = preset('switch-immersion')
    const fromSwitch = clearerAlternative(immersion, PRESET_RECIPES)!
    expect(matchesMethod(fromSwitch, 'switch')).toBe(true)
    expect(fromSwitch.taste.clarity).toBeGreaterThan(immersion.taste.clarity)
  })

  it('ignores a copy of the same recipe and espresso', () => {
    expect(clearerAlternative({ ...preset('rao-v60'), id: 'custom-rao' }, [preset('rao-v60')])).toBeNull()
    expect(clearerAlternative(preset('espresso-classic'), PRESET_RECIPES)).toBeNull()
  })

  const flatInput = (recipe: Recipe, filterFlow: AnalysisInput['filterFlow'], alternatives?: Recipe[]): AnalysisInput => ({
    recipe, samples: [], usedScale: false, totalTime: recipe.targetTime, finalWeight: recipe.water, dose: recipe.dose,
    waterTemp: recipe.temperature, roastLevel: 'light', daysOffRoast: 14, filterName: 'Paper', filterFlow, filterIdealRoast: null,
    grinder: null, feedback: ['flat'], history: [], alternatives,
  })

  it('a flat cup never names the brewed recipe as the fix', () => {
    const rao = preset('rao-v60')
    const clarity = analyze(flatInput(rao, 'fast', PRESET_RECIPES)).suggestions.find((s) => s.key === 'clarity')!
    expect(clarity.title).not.toContain(rao.name)
    expect(clarity.detail.endsWith(`than ${rao.name}.`)).toBe(true)
    expect(clarity.detail).not.toContain('CAFEC')
  })

  it('without alternatives only the paper is suggested', () => {
    expect(clarityAdvice(preset('rao-v60'), flatInput(preset('rao-v60'), 'slow'))?.title).toBe('Try a faster paper')
    expect(clarityAdvice(preset('rao-v60'), flatInput(preset('rao-v60'), 'fast'))).toBeNull()
  })
})
