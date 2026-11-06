import { describe, expect, it } from 'vitest'
import {
  MACHINE_CAPABILITIES,
  defaultGrinderSpec,
  defaultStartingValue,
  machineCanControl,
  machineReadsPressure,
  suggestMachineKind,
  type Equipment,
  type GrinderSpec,
} from '../src/domain/models'
import { BrewSetup } from '../src/data/setup'
import { blankRecipe } from '../src/domain/library'
import type { Recipe } from '../src/domain/recipe'

describe('Machine capabilities and suggestions', () => {
  it('suggests machine kind from brewer name', () => {
    expect(suggestMachineKind('Gaggia Classic (GaggiMate)')).toBe('gaggimate')
    expect(suggestMachineKind('Decent DE1')).toBe('decent')
    expect(suggestMachineKind('La Marzocco Linea Micra')).toBe('laMarzocco')
    expect(suggestMachineKind('la marzocco linea mini')).toBe('laMarzocco')
    expect(suggestMachineKind('Gaggia Classic')).toBeNull()
    expect(suggestMachineKind('Rancilio Silvia')).toBeNull()
    expect(suggestMachineKind('Hario V60 02')).toBeNull()
  })

  it('provides machine capabilities and control status', () => {
    expect(Array.from(MACHINE_CAPABILITIES.gaggimate).sort()).toEqual(
      ['machineScale', 'profiles', 'startStop', 'temperatureNudge'].sort(),
    )
    expect(Array.from(MACHINE_CAPABILITIES.demo).sort()).toEqual(
      ['machineScale', 'profiles', 'startStop', 'temperatureNudge'].sort(),
    )
    expect(Array.from(MACHINE_CAPABILITIES.decent)).toEqual(['startStop'])
    expect(Array.from(MACHINE_CAPABILITIES.laMarzocco).sort()).toEqual(['power', 'temperatureNudge'].sort())
    expect(Array.from(MACHINE_CAPABILITIES.none)).toEqual([])

    expect(machineCanControl('gaggimate', true)).toBe(true)
    expect(machineCanControl('gaggimate', false)).toBe(false)
    expect(machineReadsPressure('gaggimate', { hasPressure: true })).toBe(true)
    expect(machineReadsPressure('gaggimate', { hasPressure: false })).toBe(false)

    expect(machineCanControl('laMarzocco', true)).toBe(false)
    expect(machineReadsPressure('laMarzocco', { hasPressure: true })).toBe(false)

    expect(machineCanControl('none', false)).toBe(false)
    expect(machineReadsPressure('none', { hasPressure: false })).toBe(false)
  })
})

describe('Grinder defaults and memory in BrewSetup', () => {
  it('computes default starting values', () => {
    const comandante: GrinderSpec = {
      unit: 'clicks',
      step: 1.0,
      adjustStep: 2.0,
      finerIsLower: true,
      rangeNote: '20–30 clicks',
    }
    expect(defaultStartingValue(comandante)).toBe(25.0)

    const ode: GrinderSpec = {
      unit: 'numbers',
      step: 0.1,
      adjustStep: 0.2,
      finerIsLower: true,
      rangeNote: '5.0–7.0',
    }
    expect(defaultStartingValue(ode)).toBe(6.0)

    const fallbackClicks = defaultGrinderSpec()
    expect(defaultStartingValue(fallbackClicks)).toBe(20.0)
  })

  it('remembers grind setting per grinder and restores upon switching', () => {
    const memory = new Map<string, string>()
    const storage: Storage = {
      get length() { return memory.size },
      clear: () => memory.clear(),
      getItem: (k) => memory.get(k) ?? null,
      key: (i) => [...memory.keys()][i] ?? null,
      removeItem: (k) => { memory.delete(k) },
      setItem: (k, v) => { memory.set(k, String(v)) },
    }
    const origStorage = globalThis.localStorage
    globalThis.localStorage = storage

    try {
      const recipes: Recipe[] = [
        { ...blankRecipe(), id: 'v60-1', name: 'V60 Daily', method: 'v60' },
        { ...blankRecipe(), id: 'espresso-1', name: 'Espresso Classic', method: 'espresso' },
      ]

      const filterSetup = new BrewSetup(() => recipes, 'filter')
      const espressoSetup = new BrewSetup(() => recipes, 'espresso')

      expect(filterSetup.value.recipe.id).toBe('v60-1')
      expect(espressoSetup.value.recipe.id).toBe('espresso-1')

      const g1: Equipment = {
        id: 'c40',
        name: 'Comandante C40',
        type: 'grinder',
        notes: '',
        method: null,
        filterFlow: null,
        idealRoast: null,
        grinder: { unit: 'clicks', step: 1, adjustStep: 2, finerIsLower: true, rangeNote: '20–30 clicks', defaultGrind: 24 },
        createdAt: 0,
      }
      const g2: Equipment = {
        id: 'k-ultra',
        name: '1Zpresso K-Ultra',
        type: 'grinder',
        notes: '',
        method: null,
        filterFlow: null,
        idealRoast: null,
        grinder: { unit: 'numbers', step: 0.1, adjustStep: 0.2, finerIsLower: true, rangeNote: '7.0–8.5', defaultGrind: 7.5 },
        createdAt: 0,
      }

      // Select g1 and set grind to 23
      filterSetup.selectGrinder('c40', g1, [])
      expect(filterSetup.value.grindValue).toBe(24) // fallback to defaultGrind
      filterSetup.pinGrind(23)
      expect(filterSetup.value.grindValue).toBe(23)

      // Switch to g2
      filterSetup.selectGrinder('k-ultra', g2, [])
      expect(filterSetup.value.grindValue).toBe(7.5)
      filterSetup.pinGrind(7.2)
      expect(filterSetup.value.grindValue).toBe(7.2)

      // Switch back to g1: restores 23!
      filterSetup.selectGrinder('c40', g1, [])
      expect(filterSetup.value.grindValue).toBe(23)

      // And switch back to g2: restores 7.2!
      filterSetup.selectGrinder('k-ultra', g2, [])
      expect(filterSetup.value.grindValue).toBe(7.2)
    } finally {
      globalThis.localStorage = origStorage
    }
  })
})
