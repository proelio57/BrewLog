import { describe, expect, it } from 'vitest'
import { GaggiMateProfileImport } from '../src/machine/gaggimateProfileImport'

const gaggiMateProfile = {
  id: 'abc123',
  label: 'Blooming Shot',
  type: 'pro',
  description: 'Slow bloom, then 9 bar.',
  temperature: 94,
  dose: 18.5,
  phases: [
    {
      name: 'Fill',
      phase: 'preinfusion',
      valve: 1,
      duration: 4,
      pump: { target: 'flow', pressure: 3, flow: 4 },
    },
    { name: 'Bloom', phase: 'preinfusion', valve: 0, duration: 6, pump: 0 },
    {
      name: 'Extraction',
      phase: 'brew',
      valve: 1,
      duration: 40,
      pump: { target: 'pressure', pressure: 9, flow: 0 },
      targets: [{ type: 'volumetric', operator: 'gte', value: 40 }],
    },
  ],
}

const brewPhase = { name: 'Brew', phase: 'brew', valve: 1, duration: 28, pump: 100 }

describe('GaggiMateProfileImport', () => {
  it('converts GaggiMate profile into espresso recipe', () => {
    expect(GaggiMateProfileImport.looksLikeProfiles(gaggiMateProfile)).toBe(true)
    const recipes = GaggiMateProfileImport.recipes(gaggiMateProfile)
    expect(recipes).toHaveLength(1)
    const recipe = recipes[0]
    expect(recipe.id).toBe('gaggimate-abc123')
    expect(recipe.name).toBe('Blooming Shot')
    expect(recipe.method).toBe('espresso')
    expect(recipe.dose).toBe(18.5)
    expect(recipe.water).toBe(40.0)
    expect(recipe.temperature).toBe(94.0)
    expect(recipe.pressure).toBe(9.0)
    expect(recipe.isCustom).toBe(true)
    expect(recipe.steps.map((s) => s.kind)).toEqual(['preinfuse', 'extract'])
    expect(recipe.steps[recipe.steps.length - 1].time).toBe(10.0) // after both pre-infusions
    expect(recipe.steps[recipe.steps.length - 1].target).toBe(40.0)
    expect(recipe.targetTime).toBe(35.0) // with a target weight the duration is only a cap: 10 + 25 = 35
    expect(recipe.tips).toHaveLength(3)
    expect(recipe.tips[0]).toBe('Phase 1: Fill · 4 s · 4 ml/s, max 3 bar')
    expect(recipe.tips[2]).toBe('Phase 3: Extraction · 40 s · 9 bar · to 40 g')
  })

  it('skips utility profiles and strips BrewLog prefix', () => {
    const json = {
      profiles: [
        { id: 'f1', label: 'Flush', utility: true, phases: [{ phase: 'brew', duration: 5, pump: 100 }] },
        {
          label: 'BrewLog · Classic',
          type: 'standard',
          phases: [{ name: 'Brew', phase: 'brew', duration: 28, pump: 100 }],
        },
      ],
    }
    expect(GaggiMateProfileImport.looksLikeProfiles(json)).toBe(true)
    const recipes = GaggiMateProfileImport.recipes(json)
    expect(recipes.map((r) => r.name)).toEqual(['Classic'])
    const recipe = recipes[0]
    expect(recipe.id).toBe('gaggimate-classic')
    expect(recipe.dose).toBe(18.0)
    expect(recipe.water).toBe(36.0)
    expect(recipe.targetTime).toBe(28.0)
    expect(recipe.pressure).toBe(9.0)
    expect(recipe.steps.map((s) => s.kind)).toEqual(['extract'])
    expect(recipe.tips).toEqual(['Phase 1: Brew · 28 s · pump 100 %'])
  })

  it('leaves non-profile JSON alone', () => {
    expect(GaggiMateProfileImport.looksLikeProfiles({})).toBe(false)
    expect(GaggiMateProfileImport.looksLikeProfiles({ BREWS: [] })).toBe(false)
    expect(GaggiMateProfileImport.looksLikeProfiles([])).toBe(false)
  })

  it('orders summaries using selected flag and favorite', () => {
    const response = {
      tp: 'res:profiles:list',
      profiles: [
        { id: 'a', label: 'Turbo', phases: [brewPhase] },
        { id: 'b', label: 'Turbo', selected: true, phases: [brewPhase] },
      ],
    }
    const summaries = GaggiMateProfileImport.summaries(response)
    expect(summaries[0].id).toBe('b')
    expect(summaries.filter((s) => s.isSelected).map((s) => s.id)).toEqual(['b'])
  })

  it('orders summaries and skips utilities and missing ids', () => {
    const response = {
      profiles: [
        { id: 'x', label: 'Plain', phases: [brewPhase] },
        { id: 'y', label: 'Fav', favorite: true, phases: [brewPhase] },
        { id: 'z', label: 'Flush', utility: true, phases: [brewPhase] },
        { label: 'No id', phases: [brewPhase] },
        { id: 'c', label: 'BrewLog · Classic', phases: [brewPhase] },
      ],
    }
    const summaries = GaggiMateProfileImport.summaries(response)
    expect(summaries.map((s) => s.id)).toEqual(['y', 'x', 'c'])
    const own = summaries[summaries.length - 1]
    expect(own.isBrewLogs).toBe(true)
    expect(own.label).toBe('Classic')
    expect(summaries[0].isFavorite).toBe(true)
    expect(summaries[0].recipe).not.toBeNull()
  })

  it('sets yield from ratio target', () => {
    const profile = {
      label: 'Long',
      dose: 18,
      phases: [
        {
          name: 'Brew',
          phase: 'brew',
          valve: 1,
          duration: 40,
          pump: { target: 'pressure', pressure: 9, flow: 0 },
          targets: [{ type: 'ratio', value: 2.5 }],
        },
      ],
    }
    const recipe = GaggiMateProfileImport.recipe(profile)
    expect(recipe).not.toBeNull()
    expect(recipe!.water).toBe(45.0)
    expect(recipe!.targetTime).toBe(25.0)
  })

  it('does not round yield to whole grams', () => {
    const profile = {
      label: 'Exact',
      dose: 18.3,
      phases: [
        {
          name: 'Brew',
          phase: 'brew',
          valve: 1,
          duration: 30,
          pump: 100,
          targets: [{ type: 'volumetric', value: 36.5 }],
        },
      ],
    }
    expect(GaggiMateProfileImport.recipe(profile)!.water).toBe(36.5)

    const ratio = {
      label: 'Ratio',
      dose: 18.3,
      phases: [
        {
          name: 'Brew',
          phase: 'brew',
          valve: 1,
          duration: 30,
          pump: 100,
          targets: [{ type: 'ratio', value: 2 }],
        },
      ],
    }
    expect(GaggiMateProfileImport.recipe(ratio)!.water).toBe(36.6)
  })

  it('labels flow hold as flow', () => {
    const profile = {
      label: 'Flow',
      phases: [
        {
          name: 'Steady',
          phase: 'brew',
          valve: 1,
          duration: 20,
          pump: { target: 'flow', pressure: 9, flow: -1 },
        },
      ],
    }
    const tip = GaggiMateProfileImport.recipe(profile)!.tips[0]
    expect(tip).toContain('hold flow')
    expect(tip).not.toContain('hold pressure')
  })

  it('ignores hold pressure for maximum pressure calculation', () => {
    const profile = {
      label: 'Hold',
      phases: [
        {
          name: 'Pre',
          phase: 'preinfusion',
          valve: 1,
          duration: 5,
          pump: { target: 'pressure', pressure: 3, flow: 0 },
        },
        {
          name: 'Hold',
          phase: 'brew',
          valve: 1,
          duration: 10,
          pump: { target: 'pressure', pressure: -1, flow: -1 },
        },
        {
          name: 'Ramp',
          phase: 'brew',
          valve: 1,
          duration: 20,
          pump: { target: 'pressure', pressure: 6, flow: 0 },
        },
      ],
    }
    const recipe = GaggiMateProfileImport.recipe(profile)!
    expect(recipe.pressure).toBe(6.0)
    const tip = recipe.tips.find((t) => t.includes('Hold ·'))!
    expect(tip).toContain('hold')
  })
})
