import { STEP_TITLES, type RecipeStep } from '../domain/recipe'

/** What the voice prompts say during a brew, so you don't need to look at the screen while pouring. */
export const StepAnnouncement = {
  LEAD_TIME: 5.0,
  FINISHED: 'Brew time reached.',

  /** Spoken at the start of a step, e.g. "Pour to 150 grams." */
  text(step: RecipeStep): string {
    const target = step.target
    let sentence = ''
    switch (step.kind) {
      case 'bloom':
      case 'pour':
      case 'extract':
        if (target != null) {
          const verb = step.kind === 'bloom' ? 'Bloom to' : step.kind === 'extract' ? 'Extract to' : 'Pour to'
          sentence = `${verb} ${StepAnnouncement.grams(target)}.`
        } else {
          sentence = `${STEP_TITLES[step.kind]}.`
        }
        break
      case 'swirl':
        sentence = 'Swirl gently.'
        break
      case 'stir':
        sentence = 'Stir.'
        break
      case 'closeValve':
        sentence = 'Close the valve.'
        break
      case 'openValve':
        sentence = 'Open the valve.'
        break
      case 'remove':
        sentence = 'Remove the dripper.'
        break
      case 'preinfuse':
        sentence = 'Pre-infusion.'
        break
    }
    const note = StepAnnouncement.spokenNote(step.note)
    if (note) sentence += ` ${note}`
    return sentence
  },

  /** Spoken a few seconds before a step, e.g. "Next, pour to 250 grams." */
  preview(step: RecipeStep): string {
    const action = StepAnnouncement.text({ ...step, note: null })
    return `Next, ${action.slice(0, 1).toLowerCase()}${action.slice(1, -1)}.`
  },

  grams(value: number): string {
    const rounded = Math.round(value)
    return rounded === 1 ? '1 gram' : `${rounded} grams`
  },

  /** Short notes are read out, long ones would run into the next step. */
  spokenNote(note?: string | null): string | null {
    const trimmed = note?.trim()
    if (!trimmed || trimmed.length > 80) return null
    return trimmed.endsWith('.') || trimmed.endsWith('!') ? trimmed : `${trimmed}.`
  },
}

/** Web Speech API speaker for step prompts. */
export class VoicePrompter {
  private lastSpoken: string | null = null

  speak(text: string): void {
    if (typeof window === 'undefined' || !window.speechSynthesis) return
    if (this.lastSpoken === text) return
    this.lastSpoken = text
    try {
      window.speechSynthesis.cancel()
      const utterance = new SpeechSynthesisUtterance(text)
      utterance.rate = 1.0
      utterance.pitch = 1.0
      window.speechSynthesis.speak(utterance)
    } catch {
      // ignore
    }
  }

  stop(): void {
    if (typeof window !== 'undefined' && window.speechSynthesis) {
      window.speechSynthesis.cancel()
    }
    this.lastSpoken = null
  }
}
