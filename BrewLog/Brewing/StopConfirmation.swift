import Foundation

/// The two-tap stop: the first tap arms the button ("Really stop?"), the second one stops. Taps right after
/// arming are ignored (debounce, so a double tap doesn't stop by accident), and the armed state runs out again.
struct StopConfirmation {
    enum Result: Equatable { case arm, ignore, stop }

    /// Taps this soon after arming don't count.
    static let debounce: TimeInterval = 0.7
    /// An armed button goes back to normal after this long.
    static let timeout: TimeInterval = 4

    private(set) var armedAt: Date?

    func isArmed(now: Date) -> Bool {
        guard let armedAt else { return false }
        return now.timeIntervalSince(armedAt) <= Self.timeout
    }

    mutating func tap(now: Date) -> Result {
        guard isArmed(now: now), let armedAt else {
            self.armedAt = now
            return .arm
        }
        if now.timeIntervalSince(armedAt) < Self.debounce { return .ignore }
        self.armedAt = nil
        return .stop
    }

    mutating func reset() { armedAt = nil }
}
