// Tiny key-value store on IndexedDB (falls back to memory if IndexedDB isn't available, e.g. in some private modes).

const DB_NAME = 'brewlog'
const STORE = 'kv'
const memory = new Map<string, unknown>()
let dbPromise: Promise<IDBDatabase | null> | null = null

function open(): Promise<IDBDatabase | null> {
  if (dbPromise) return dbPromise
  dbPromise = new Promise((resolve) => {
    if (typeof indexedDB === 'undefined') return resolve(null)
    try {
      const request = indexedDB.open(DB_NAME, 1)
      request.onupgradeneeded = () => request.result.createObjectStore(STORE)
      request.onsuccess = () => resolve(request.result)
      request.onerror = () => resolve(null)
    } catch {
      resolve(null)
    }
  })
  return dbPromise
}

function run<T>(mode: IDBTransactionMode, action: (store: IDBObjectStore) => IDBRequest<T>): Promise<T | undefined> {
  return open().then((db) =>
    db
      ? new Promise<T | undefined>((resolve, reject) => {
          const request = action(db.transaction(STORE, mode).objectStore(STORE))
          request.onsuccess = () => resolve(request.result)
          request.onerror = () => reject(request.error)
        })
      : undefined,
  )
}

export async function dbGet<T>(key: string): Promise<T | undefined> {
  const db = await open()
  if (!db) return memory.get(key) as T | undefined
  return run<T>('readonly', (store) => store.get(key) as IDBRequest<T>)
}

export async function dbSet(key: string, value: unknown): Promise<void> {
  const db = await open()
  if (!db) {
    memory.set(key, value)
    return
  }
  await run('readwrite', (store) => store.put(value, key))
}

export async function dbDelete(key: string): Promise<void> {
  const db = await open()
  if (!db) {
    memory.delete(key)
    return
  }
  await run('readwrite', (store) => store.delete(key))
}

export async function dbKeys(prefix: string): Promise<string[]> {
  const db = await open()
  const keys = db ? ((await run('readonly', (store) => store.getAllKeys())) ?? []) : [...memory.keys()]
  return keys.map(String).filter((key) => key.startsWith(prefix))
}

/** Asks the browser not to evict our data under storage pressure. */
export async function requestPersistentStorage(): Promise<boolean> {
  try {
    return (await navigator.storage?.persist?.()) ?? false
  } catch {
    return false
  }
}
