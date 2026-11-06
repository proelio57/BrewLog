import UIKit

/// BrewLog is a portrait app; only the full-screen brew chart turns to landscape (`LandscapeChartView`).
/// Info.plist allows all three orientations, this decides which ones apply right now.
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .portrait

    /// Allows `mask` and turns the screen to `preferred`.
    @MainActor
    static func set(_ mask: UIInterfaceOrientationMask, rotateTo preferred: UIInterfaceOrientationMask) {
        self.mask = mask
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: preferred)) { _ in }
        scene.keyWindow?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
}
