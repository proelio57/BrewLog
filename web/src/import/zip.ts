// Port of ZipArchive.swift: minimal read-only ZIP reader for backups such as Beanconqueror.zip.
// Stored and deflated entries (inflated with the browser's DecompressionStream). No ZIP64, encryption or multi-part.

export interface ZipEntry {
  name: string
  method: number
  compressedSize: number
  uncompressedSize: number
  localHeaderOffset: number
}

export const MAX_ENTRY_SIZE = 100 * 1024 * 1024
const MAX_ENTRIES = 10_000

export const isZip = (bytes: Uint8Array): boolean =>
  bytes.length >= 4 && bytes[0] === 0x50 && bytes[1] === 0x4b && bytes[2] === 0x03 && bytes[3] === 0x04

export class ZipArchive {
  readonly entries: ZipEntry[]
  private readonly view: DataView

  constructor(private readonly bytes: Uint8Array) {
    if (!isZip(bytes) || bytes.length < 22) throw new Error("This file isn't a ZIP archive.")
    this.view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength)
    // The end-of-central-directory record sits at the very end, followed by an optional comment (≤ 64 KB).
    let eocd = -1
    for (let p = bytes.length - 22; p >= Math.max(0, bytes.length - 22 - 0xffff); p--) {
      if (this.u32(p) === 0x06054b50) { eocd = p; break }
    }
    if (eocd < 0) throw new Error('The ZIP file is damaged or incomplete.')
    const count = this.u16(eocd + 10)
    if (count > MAX_ENTRIES) throw new Error('The ZIP file is too large.')
    let offset = this.u32(eocd + 16)
    const entries: ZipEntry[] = []
    for (let i = 0; i < count; i++) {
      if (this.u32(offset) !== 0x02014b50) throw new Error('The ZIP file is damaged or incomplete.')
      const nameLength = this.u16(offset + 28)
      const nameEnd = offset + 46 + nameLength
      if (nameEnd > bytes.length) throw new Error('The ZIP file is damaged or incomplete.')
      entries.push({
        name: new TextDecoder().decode(bytes.subarray(offset + 46, nameEnd)),
        method: this.u16(offset + 10),
        compressedSize: this.u32(offset + 20),
        uncompressedSize: this.u32(offset + 24),
        localHeaderOffset: this.u32(offset + 42),
      })
      offset = nameEnd + this.u16(offset + 30) + this.u16(offset + 32)
    }
    this.entries = entries
  }

  entry(name: string): ZipEntry | undefined {
    return this.entries.find((e) => e.name === name)
  }

  async data(entry: ZipEntry): Promise<Uint8Array> {
    if (entry.uncompressedSize > MAX_ENTRY_SIZE || entry.compressedSize > MAX_ENTRY_SIZE) throw new Error('The ZIP file is too large.')
    const header = entry.localHeaderOffset
    if (this.u32(header) !== 0x04034b50) throw new Error('The ZIP file is damaged or incomplete.')
    // Sizes in the local header may be 0 (data descriptor), so only the name/extra lengths are taken from it.
    const start = header + 30 + this.u16(header + 26) + this.u16(header + 28)
    const end = start + entry.compressedSize
    if (end > this.bytes.length) throw new Error('The ZIP file is damaged or incomplete.')
    const raw = this.bytes.slice(start, end)
    if (entry.method === 0) return raw
    if (entry.method !== 8) throw new Error("The ZIP file uses a compression method BrewLog can't read.")
    const stream = new Blob([raw]).stream().pipeThrough(new DecompressionStream('deflate-raw'))
    const out = new Uint8Array(await new Response(stream).arrayBuffer())
    if (out.length !== entry.uncompressedSize) throw new Error('The ZIP file is damaged or incomplete.')
    return out
  }

  async text(entry: ZipEntry): Promise<string> {
    return new TextDecoder().decode(await this.data(entry))
  }

  private u16(offset: number): number {
    if (offset < 0 || offset + 2 > this.bytes.length) throw new Error('The ZIP file is damaged or incomplete.')
    return this.view.getUint16(offset, true)
  }

  private u32(offset: number): number {
    if (offset < 0 || offset + 4 > this.bytes.length) throw new Error('The ZIP file is damaged or incomplete.')
    return this.view.getUint32(offset, true)
  }
}
