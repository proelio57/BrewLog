import { useSyncExternalStore } from 'react'

/** Minimal observable value, used for all app state (no state library needed). */
export class Store<T> {
  private listeners = new Set<() => void>()

  constructor(private value: T) {}

  get = (): T => this.value

  set = (next: T): void => {
    if (Object.is(next, this.value)) return
    this.value = next
    this.listeners.forEach((listener) => listener())
  }

  update = (transform: (value: T) => T): void => this.set(transform(this.value))

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener)
    return () => {
      this.listeners.delete(listener)
    }
  }
}

export function useStore<T>(store: Store<T>): T {
  return useSyncExternalStore(store.subscribe, store.get, store.get)
}
