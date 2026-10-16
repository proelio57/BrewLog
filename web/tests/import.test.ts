import { describe, expect, it } from 'vitest'
import { mergeFeed } from '../src/data/recipeFeed'
import { blankRecipe } from '../src/domain/library'
import { emptyAppData } from '../src/domain/models'
import { parseAppData } from '../src/domain/validation'
import { grindValueFrom, methodFrom, parseBeanconqueror, processFrom, roastLevelFrom, stars } from '../src/import/beanconqueror'
import { importBeanconqueror, mergeAppData, parseImport, summaryMessage } from '../src/import/importer'
import { decodeRecipes, encodeRecipes, recipeFileName } from '../src/import/recipeFile'
import { ZipArchive } from '../src/import/zip'

// Same scenarios as ImportTests.swift / DataImporterTests.swift and the Android importer tests.

const bytes = (text: string) => new TextEncoder().encode(text)

export const BACKUP_JSON = `{
  "SETTINGS": [ { "brew_rating": 10 } ],
  "BEANS": [
    { "name": "Gesha Village", "roaster": "Kawa", "roastingDate": "2026-09-01T00:00:00.000Z", "weight": 250,
      "roast": "Moderate-Light Roast", "aromatics": "jasmine", "note": "", "finished": false,
      "bean_information": [ { "country": "Ethiopia", "region": "Bench Maji", "variety": "Gesha", "processing": "Natural" } ],
      "config": { "uuid": "bean-1", "unix_timestamp": 1788220800 } },
    { "name": "No id" }
  ],
  "MILL": [ { "name": "Comandante C40 MK4", "note": "", "config": { "uuid": "mill-1", "unix_timestamp": 1 } } ],
  "PREPARATION": [
    { "name": "My V60", "type": "V60", "finished": false, "config": { "uuid": "prep-1", "unix_timestamp": 1 } },
    { "name": "Old press", "type": "FRENCH_PRESS", "finished": true, "config": { "uuid": "prep-2", "unix_timestamp": 1 } }
  ],
  "BREWS": [
    { "grind_size": "24", "grind_weight": 15, "method_of_preparation": "prep-1", "mill": "mill-1", "bean": "bean-1",
      "brew_temperature": 94, "brew_time": 165, "brew_time_milliseconds": 500, "brew_quantity": 250,
      "brew_beverage_quantity": 215, "rating": 8, "note": "juicy",
      "config": { "uuid": "brew-1", "unix_timestamp": 1760000000 } },
    { "grind_size": "medium", "grind_weight": "16,5", "method_of_preparation": "", "mill": "", "bean": "",
      "brew_temperature": null, "brew_time": 0, "brew_quantity": 0, "brew_beverage_quantity": 230, "rating": 0,
      "config": { "uuid": "brew-2", "unix_timestamp": 1760100000 } }
  ]
}`

/** ZIP with uncompressed entries (CRC left at 0; the reader doesn't check it). */
function storedZip(files: [string, string][]): Uint8Array {
  const out: number[] = []
  const central: number[] = []
  const u16 = (v: number) => [v & 0xff, (v >> 8) & 0xff]
  const u32 = (v: number) => [...u16(v & 0xffff), ...u16((v >>> 16) & 0xffff)]
  for (const [name, text] of files) {
    const nameBytes = [...bytes(name)]
    const data = [...bytes(text)]
    const offset = out.length
    out.push(...u32(0x04034b50), ...u16(20), ...u16(0), ...u16(0), ...u16(0), ...u16(0), ...u32(0),
      ...u32(data.length), ...u32(data.length), ...u16(nameBytes.length), ...u16(0), ...nameBytes, ...data)
    central.push(...u32(0x02014b50), ...u16(20), ...u16(20), ...u16(0), ...u16(0), ...u16(0), ...u16(0), ...u32(0),
      ...u32(data.length), ...u32(data.length), ...u16(nameBytes.length), ...u16(0), ...u16(0), ...u16(0), ...u16(0), ...u32(0),
      ...u32(offset), ...nameBytes)
  }
  const directoryOffset = out.length
  out.push(...central, ...u32(0x06054b50), ...u16(0), ...u16(0), ...u16(files.length), ...u16(files.length),
    ...u32(central.length), ...u32(directoryOffset), ...u16(0))
  return new Uint8Array(out)
}

describe('recipe files', () => {
  it('fills defaults for a minimal recipe', () => {
    const [recipe] = decodeRecipes(JSON.parse('{ "name": "Morning V60", "method": "v60", "steps": [ { "kind": "bloom", "time": 0, "target": 40 }, { "kind": "pour", "time": 40, "target": 240 } ] }'))
    expect(recipe.name).toBe('Morning V60')
    expect(recipe.water).toBe(240)
    expect(recipe.dose).toBe(15)
    expect(recipe.targetTime).toBeGreaterThanOrEqual(40)
    expect(recipe.id.startsWith('custom-')).toBe(true)
  })

  it('reads one recipe, a list or a wrapper and round-trips', () => {
    const recipe = blankRecipe()
    expect(decodeRecipes(JSON.parse(encodeRecipes([recipe])))[0].id).toBe(recipe.id)
    expect(decodeRecipes([recipe, recipe])).toHaveLength(2)
    expect(decodeRecipes({ recipes: [recipe, recipe] })).toHaveLength(2)
  })

  it('rejects other JSON and skips unknown step kinds', () => {
    expect(() => decodeRecipes({ BREWS: [] })).toThrow()
    expect(() => decodeRecipes([])).toThrow()
    const list = [{ name: 'Known', steps: [{ kind: 'pour', time: 0, target: 200 }] }, { name: 'From the future', steps: [{ kind: 'teleport', time: 0 }] }]
    expect(decodeRecipes(list).map((r) => r.name)).toEqual(['Known'])
  })

  it('makes safe file names', () => {
    const recipe = { ...blankRecipe(), name: '4:6 / Kasuya?' }
    expect(recipeFileName([recipe])).toBe('46  Kasuya.json')
    expect(recipeFileName([recipe, recipe])).toBe('BrewLog recipes.json')
  })

  it('merges the online list like iOS and Android', () => {
    const a = { ...blankRecipe(), id: 'a', name: 'A' }
    const b = { ...blankRecipe(), id: 'b', name: 'B' }
    const c = { ...blankRecipe(), id: 'c', name: 'C' }
    const merged = mergeFeed([a, b], [c, { ...a, name: 'A v2' }, c])
    expect(merged.map((r) => r.id)).toEqual(['a', 'b', 'c'])
    expect(merged[0].name).toBe('A v2')
    expect(merged[2].isCustom).toBeNull()
  })
})

describe('Beanconqueror', () => {
  it('parses the JSON export', async () => {
    const backup = await parseBeanconqueror(bytes(BACKUP_JSON))
    expect(backup.ratingScale).toBe(10)
    expect(backup.beans).toHaveLength(1)
    expect(backup.mills.map((m) => m.name)).toEqual(['Comandante C40 MK4'])
    expect(backup.brews).toHaveLength(2)
    expect(backup.beans[0].roastingDate).toBe(1_788_220_800_000)
    expect(backup.brews[0].date).toBe(1_760_000_000_000)
    expect(backup.brews[0].time).toBeCloseTo(165.5)
    expect(stars(backup, backup.brews[0].rating)).toBe(4)
    expect(backup.brews[1].dose).toBe(16.5)
    expect(stars(backup, 0)).toBe(0)
  })

  it('maps like the other platforms', () => {
    expect(grindValueFrom('24')).toBe(24)
    expect(grindValueFrom(' 7,5 ')).toBe(7.5)
    expect(grindValueFrom('medium-fine')).toBeNull()
    expect(roastLevelFrom('Cinnamon Roast')).toBe('light')
    expect(roastLevelFrom('Full City + Roast')).toBe('mediumDark')
    expect(roastLevelFrom('Unknown')).toBeNull()
    expect(processFrom('Anaerobic Natural')).toBe('anaerobic')
    expect(processFrom('Wet hulled')).toBe('other')
    expect(methodFrom('HARIO_SWITCH')).toBe('switch')
    expect(methodFrom('PORTAFILTER')).toBe('espresso')
    expect(methodFrom('AEROPRESS')).toBeNull()
  })

  it('reads chunked ZIP exports', async () => {
    const zip = storedZip([
      ['Beanconqueror.json', '{ "BREWS": [ { "config": { "uuid": "b1", "unix_timestamp": 1 } } ], "BEANS": [ { "name": "One", "config": { "uuid": "bean-1" } } ] }'],
      ['Beanconqueror_Brews_1.json', '[ { "config": { "uuid": "b2", "unix_timestamp": 2 } } ]'],
      ['Beanconqueror_Brews_2.json', '[ { "config": { "uuid": "b3", "unix_timestamp": 3 } } ]'],
    ])
    const backup = await parseBeanconqueror(zip)
    expect(backup.brews.map((b) => b.uuid)).toEqual(['b1', 'b2', 'b3'])
    await expect(parseBeanconqueror(storedZip([['other.json', '{}']]))).rejects.toThrow(/Beanconqueror.json/)
    expect(() => new ZipArchive(zip.slice(0, zip.length - 10))).toThrow()
  })

  it('reads deflated ZIP exports (same fixture as iOS)', async () => {
    const base64 = 'UEsDBBQAAAAIAFJrTl3q55lxKAEAABUCAAASAAAAQmVhbmNvbnF1ZXJvci5qc29udZBfa8IwFMW/SslzHamoY77pVqTMOakFwSHlTmN7H5q4JF3nit99+WPdxljIQzj33nPPLy2ZxpPFioyDl5ZwqJh5kRlTJZAwIFKA0kxa7REaJ+0EP2BhlJbUNe5t6ZUB70W2WHP8yDVWTGmojqYW3dLLOXd2yIsH0G5Pn/ZHPXrXo1FG6djdG9O6sVYNw6LUpqs/pN2onblHbmIKHqROCf36HPlByAo0Cu5ZdqLmWp7syBLMhAt/lGLHlDIRrL4GVbK91d9BItOnb/bz9rw1+jSN16vO7y+3ZM2/3KMf3IVEvs+vRNEw9MP5Ww1co1vsMX2nwk//P4OO7/c3S9AeYdAZ2d3OmbrcT8l8bmPb9zKNl5N0kiXPi05axVmWLGYXMmdwtRwa9C9QSwECFAMUAAAACABSa05d6ueZcSgBAAAVAgAAEgAAAAAAAAAAAAAAgAEAAAAAQmVhbmNvbnF1ZXJvci5qc29uUEsFBgAAAAABAAEAQAAAAFgBAAAAAA=='
    const backup = await parseBeanconqueror(new Uint8Array(Buffer.from(base64, 'base64')))
    expect(backup.beans[0].name).toBe('Gesha')
    expect(backup.brews[0].grindSize).toBe('24')
  })

  it('imports once and maps brews, beans and gear', async () => {
    const backup = await parseBeanconqueror(bytes(BACKUP_JSON))
    const first = importBeanconqueror(emptyAppData(), backup)
    expect(first.summary).toMatchObject({ brews: 2, beans: 1, grinders: 1, brewers: 1 })
    const data = parseAppData(first.data)
    const brew = [...data.brews].sort((a, b) => a.date - b.date)[0]
    expect(brew.recipeName).toBe('My V60')
    expect(brew.grindValue).toBe(24)
    expect(brew.rating).toBe(4)
    expect(brew.finalWeight).toBe(250)
    const bean = data.beans[0]
    expect(bean.roastLevel).toBe('mediumLight')
    expect(bean.process).toBe('natural')
    expect(bean.origin).toBe('Ethiopia, Bench Maji')
    expect(bean.remaining).toBe(235)
    const second = importBeanconqueror(data, backup)
    expect(second.summary).toMatchObject({ brews: 0, beans: 0, grinders: 0, skippedBrews: 2 })
    expect(summaryMessage(second.summary)).toBe('Nothing new to import. 2 brews were already in your journal.')
  })
})

describe('import detection and BrewLog backups', () => {
  it('detects the file type', async () => {
    expect((await parseImport(bytes(BACKUP_JSON))).kind).toBe('beanconqueror')
    expect((await parseImport(bytes(JSON.stringify(blankRecipe())))).kind).toBe('recipes')
    expect((await parseImport(bytes('{"app":"BrewLog","format":1,"data":{}}'))).kind).toBe('brewlog')
    expect((await parseImport(bytes('{"beans":[],"brews":[]}'))).kind).toBe('brewlog')
    await expect(parseImport(bytes('hello'))).rejects.toThrow()
  })

  it('merges backups without replacing', async () => {
    const backup = await parseBeanconqueror(bytes(BACKUP_JSON))
    const mine = parseAppData(importBeanconqueror(emptyAppData(), backup).data)
    const result = mergeAppData(emptyAppData(), mine, new Set())
    expect(result.summary.brews).toBe(2)
    expect(result.newBrewIds.size).toBe(2)
    const again = mergeAppData(result.data, mine, new Set())
    expect(again.summary.brews).toBe(0)
    expect(again.summary.skippedBrews).toBe(2)
    expect(again.data.brews).toHaveLength(2)
  })
})
