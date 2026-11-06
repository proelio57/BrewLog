import { describe, expect, it } from 'vitest'
import { StepAnnouncement } from '../src/audio/voicePrompter'
import { BrewSession, type BrewCue } from '../src/brewing/brewSession'
import { DEFAULT_SETTINGS, type AppSettings } from '../src/domain/models'
import { valveChange, type Recipe, type RecipeStep } from '../src/domain/recipe'
import type { ScaleCommands } from '../src/scale/scaleManager'

describe('StepAnnouncement and Valve Changes', () => {
  it('formats step announcements', () => {
    expect(StepAnnouncement.text({ kind: 'bloom', time: 0, target: 45 })).toBe('Bloom to 45 grams.')
    expect(
      StepAnnouncement.text({
        kind: 'pour',
        time: 45,
        target: 150.4,
        note: 'Slow spiral',
      }),
    ).toBe('Pour to 150 grams. Slow spiral.')
    expect(StepAnnouncement.text({ kind: 'swirl', time: 90 })).toBe('Swirl gently.')
    expect(StepAnnouncement.text({ kind: 'openValve', time: 120 })).toBe('Open the valve.')
    expect(
      StepAnnouncement.preview({
        kind: 'pour',
        time: 75,
        target: 250,
        note: 'Long note is not read ahead',
      }),
    ).toBe('Next, pour to 250 grams.')
    expect(
      StepAnnouncement.text({
        kind: 'stir',
        time: 10,
        note: 'word '.repeat(30),
      }),
    ).toBe('Stir.')
    expect(StepAnnouncement.grams(1.0)).toBe('1 gram')
    expect(StepAnnouncement.grams(2.0)).toBe('2 grams')
  })

  it('detects valve changes between steps', () => {
    const switchRecipe: Recipe = {
      id: 's',
      name: 'Switch Recipe',
      author: 'Author',
      method: 'switch',
      summary: '',
      tasteNotes: '',
      taste: { acidity: 3, sweetness: 3, body: 3, clarity: 3 },
      dose: 15,
      water: 250,
      temperature: 94,
      grind: '',
      targetTime: 120,
      flowMin: 1,
      flowMax: 3,
      steps: [
        { kind: 'bloom', time: 0, target: 60, valve: 'open' },
        { kind: 'pour', time: 30, target: 120, valve: 'open' },
        { kind: 'pour', time: 75, target: 280, valve: 'closed' },
        { kind: 'swirl', time: 90 },
        { kind: 'openValve', time: 105, valve: 'open' },
      ],
      tips: [],
    }

    expect(valveChange(switchRecipe, 0)).toBeNull()
    expect(valveChange(switchRecipe, 1)).toBeNull()
    expect(valveChange(switchRecipe, 2)).toBe('closed')
    expect(valveChange(switchRecipe, 3)).toBeNull()
    expect(valveChange(switchRecipe, 4)).toBe('open')
    expect(valveChange(switchRecipe, 9)).toBeNull()
  })

  class FakeScale implements ScaleCommands {
    isReady = false
    tare() {}
    prepareForBrew() {}
    prepareForDosing() {}
    dosingFinished() {}
    brewStarted() {}
    brewFinished() {}
  }

  function runSession(
    recipe: Recipe,
    settings: AppSettings,
    untilSec: number,
  ): { cues: [number, BrewCue][]; spoken: string[] } {
    let now = 0
    const cues: [number, BrewCue][] = []
    const spoken: string[] = []
    const session = new BrewSession(
      recipe,
      new FakeScale(),
      () => settings,
      (cue) => cues.push([now, cue]),
      () => now,
      null,
      null,
      (text) => spoken.push(text),
    )
    session.prepare()
    session.ready()
    session.startManually()
    while (now < untilSec * 1000) {
      now += 50
      session.tick()
    }
    return { cues, spoken }
  }

  it('ticks before valve changes even if countdown ticks are disabled', () => {
    const switchRecipe: Recipe = {
      id: 's',
      name: 'Switch',
      author: '',
      method: 'switch',
      summary: '',
      tasteNotes: '',
      taste: { acidity: 3, sweetness: 3, body: 3, clarity: 3 },
      dose: 15,
      water: 250,
      temperature: 94,
      grind: '',
      targetTime: 70,
      flowMin: 1,
      flowMax: 3,
      steps: [
        { kind: 'bloom', time: 0, target: 60, valve: 'closed' },
        { kind: 'pour', time: 30, target: 120, valve: 'closed' },
        { kind: 'openValve', time: 60, valve: 'open' },
      ],
      tips: [],
    }

    const { cues } = runSession(
      switchRecipe,
      { ...DEFAULT_SETTINGS, countdownTicks: false, valveCountdown: true, weighBeansFirst: false },
      62.0,
    )
    const ticks = cues.filter((c) => c[1] === 'tick').map((c) => c[0])
    // 3-2-1 before 1:00 (valve opens), nothing before 0:30 (valve stays closed)
    expect(ticks).toHaveLength(3)
    expect(ticks.every((t) => t >= 57000 && t <= 60000)).toBe(true)

    const { cues: quiet } = runSession(
      switchRecipe,
      { ...DEFAULT_SETTINGS, countdownTicks: false, valveCountdown: false, weighBeansFirst: false },
      62.0,
    )
    expect(quiet.filter((c) => c[1] === 'tick')).toHaveLength(0)
  })

  it('speaks step announcements and previews ahead', () => {
    const steps: RecipeStep[] = [
      { kind: 'bloom', time: 0, target: 45 },
      { kind: 'pour', time: 45, target: 150 },
      { kind: 'pour', time: 75, target: 250 },
    ]
    const recipe: Recipe = {
      id: 'v',
      name: 'V60',
      author: '',
      method: 'v60',
      summary: '',
      tasteNotes: '',
      taste: { acidity: 3, sweetness: 3, body: 3, clarity: 3 },
      dose: 15,
      water: 250,
      temperature: 94,
      grind: '',
      targetTime: 120,
      flowMin: 1,
      flowMax: 3,
      steps,
      tips: [],
    }

    const { spoken } = runSession(
      recipe,
      { ...DEFAULT_SETTINGS, voicePrompts: true, voiceAnnounceAhead: true, weighBeansFirst: false },
      80.0,
    )
    expect(spoken).toEqual([
      'Bloom to 45 grams.',
      'Next, pour to 150 grams.',
      'Pour to 150 grams.',
      'Next, pour to 250 grams.',
      'Pour to 250 grams.',
    ])

    const { spoken: silent } = runSession(
      recipe,
      { ...DEFAULT_SETTINGS, voicePrompts: false, weighBeansFirst: false },
      80.0,
    )
    expect(silent).toHaveLength(0)
  })
})
