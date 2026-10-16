import { Upload } from 'lucide-react'
import { useRef, useState } from 'react'
import { presetRecipes, repository, setup } from '../app'
import { parseImport, summaryMessage } from '../import/importer'

/** Saves a text file: the share sheet where available (phones), otherwise a download. */
export async function shareOrDownload(fileName: string, text: string, mime = 'application/json'): Promise<void> {
  const file = new File([text], fileName, { type: mime })
  const nav = navigator as Navigator & { canShare?: (data: ShareData) => boolean }
  if (nav.canShare?.({ files: [file] }) && nav.share) {
    try {
      await nav.share({ files: [file], title: fileName })
      return
    } catch (error) {
      if (error instanceof DOMException && error.name === 'AbortError') return
    }
  }
  const url = URL.createObjectURL(file)
  const link = document.createElement('a')
  link.href = url
  link.download = fileName
  link.click()
  setTimeout(() => URL.revokeObjectURL(url), 1_000)
}

/** Import button: recipe files, Beanconqueror backups (.zip/.json) and BrewLog backups. */
export function ImportButton({ label = 'Import from file…', className = 'link', icon = true }: { label?: string; className?: string; icon?: boolean }) {
  const input = useRef<HTMLInputElement>(null)
  const [busy, setBusy] = useState(false)
  const run = async (file: File) => {
    setBusy(true)
    try {
      const parsed = await parseImport(new Uint8Array(await file.arrayBuffer()))
      const summary = await repository.applyImport(parsed, new Set(presetRecipes().map((r) => r.id)))
      setup.adopt(repository.data.get())
      window.alert(summaryMessage(summary))
    } catch (error) {
      window.alert(`Import failed: ${error instanceof Error ? error.message : String(error)}`)
    } finally {
      setBusy(false)
    }
  }
  return (
    <>
      <button className={className} disabled={busy} onClick={() => input.current?.click()} aria-label={label}>
        {icon && <Upload size={20} />}{className !== 'icon-btn' && <span>{busy ? 'Importing…' : label}</span>}
      </button>
      <input ref={input} type="file" accept=".json,.zip,.txt,application/json,application/zip,text/plain" hidden
        onChange={(e) => { const file = e.target.files?.[0]; if (file) void run(file); e.target.value = '' }} />
    </>
  )
}
