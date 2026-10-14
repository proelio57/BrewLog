import { describe, it, expect } from 'vitest'
import * as fs from 'fs'
import * as path from 'path'

describe('deployment configuration', () => {
  const webDir = path.resolve(__dirname, '..')
  const rootDir = path.resolve(webDir, '..')

  it('web package.json defines build and test scripts', () => {
    const webPkgPath = path.join(webDir, 'package.json')
    expect(fs.existsSync(webPkgPath)).toBe(true)
    const pkg = JSON.parse(fs.readFileSync(webPkgPath, 'utf8'))
    expect(pkg.scripts?.build).toBeDefined()
    expect(pkg.scripts?.test).toBeDefined()
  })

  it('root package.json defines build delegation for monorepo CI/CD', () => {
    const rootPkgPath = path.join(rootDir, 'package.json')
    expect(fs.existsSync(rootPkgPath)).toBe(true)
    const pkg = JSON.parse(fs.readFileSync(rootPkgPath, 'utf8'))
    expect(pkg.scripts?.build).toContain('npm --prefix web ci')
    expect(pkg.scripts?.build).toContain('npm --prefix web run build')
  })

  it('web wrangler.json defines static assets output directory', () => {
    const webWranglerPath = path.join(webDir, 'wrangler.json')
    expect(fs.existsSync(webWranglerPath)).toBe(true)
    const wrangler = JSON.parse(fs.readFileSync(webWranglerPath, 'utf8'))
    expect(wrangler.assets?.directory).toBe('./dist')
  })

  it('root wrangler.json defines static assets pointing to web/dist', () => {
    const rootWranglerPath = path.join(rootDir, 'wrangler.json')
    expect(fs.existsSync(rootWranglerPath)).toBe(true)
    const wrangler = JSON.parse(fs.readFileSync(rootWranglerPath, 'utf8'))
    expect(wrangler.assets?.directory).toBe('./web/dist')
  })
})
