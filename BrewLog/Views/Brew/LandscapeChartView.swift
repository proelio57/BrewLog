import SwiftUI
import UIKit

/// The live charts full screen in landscape: opened with the button on the charts or by turning the phone
/// (Settings → Landscape chart). Closes with the button or by turning the phone back.
struct LandscapeChartView: View {
    let session: BrewSession
    @Binding var isPresented: Bool
    @Environment(MachineManager.self) private var machine
    @Environment(PressureMonitor.self) private var monitor
    /// Only after the phone was held in landscape does turning it back to portrait close the view.
    @State private var sawLandscape = false

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 16) {
                numbers.frame(width: min(proxy.size.width * 0.28, 220))
                charts(height: proxy.size.height)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .overlay(alignment: .topTrailing) {
            Button(action: close) {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(Color(.tertiarySystemFill), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close full screen chart")
        }
        .onAppear {
            UIDevice.current.beginGeneratingDeviceOrientationNotifications()
            sawLandscape = UIDevice.current.orientation.isLandscape
            // Normally already turned by the opener (BrewSessionView.openLandscapeChart).
            if OrientationLock.mask != .landscape { OrientationLock.set(.landscape, rotateTo: .landscape) }
        }
        .onDisappear {
            if OrientationLock.mask != .portrait { OrientationLock.set(.portrait, rotateTo: .portrait) }
            UIDevice.current.endGeneratingDeviceOrientationNotifications()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)) { _ in
            let orientation = UIDevice.current.orientation
            if orientation.isLandscape { sawLandscape = true }
            if orientation == .portrait && sawLandscape { close() }
        }
    }

    /// Back to portrait first, then away without the slide-down, so the brew screen isn't shown sideways.
    private func close() {
        OrientationLock.set(.portrait, rotateTo: .portrait)
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { isPresented = false }
    }

    private var numbers: some View {
        let pressure = liveShotPressure(session: session, machine: machine, monitor: monitor)
        let zone = PressureFocus.zone(pressure: pressure, target: session.recipe.pressure)
        return VStack(alignment: .leading, spacing: 10) {
            number("TIME", session.elapsed.mmss, color: session.isPastTargetTime && session.phase == .brewing ? .orange : .primary)
            if session.usesScale {
                number("WEIGHT", max(session.weight, 0).scaleReadout + " g")
                number("FLOW", String(format: "%.1f g/s", max(session.flowRate, 0)), color: .teal)
            }
            if session.hasPressure {
                number("PRESSURE", pressure.map { String(format: "%.1f bar", max($0, 0)) } ?? "–",
                       color: zone.color, size: session.pressureFocus ? 56 : 40)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func charts(height: CGFloat) -> some View {
        if session.hasPressure {
            let big = height * 0.62, small = max(height * 0.38 - 40, 60)
            VStack(spacing: 8) {
                if session.pressureFocus {
                    MachineChart(samples: session.machineSamples, targetPressure: session.recipe.pressure,
                                 currentTime: session.elapsed, height: big - 30, emphasis: true)
                    BrewChart(samples: session.samples, recipe: session.recipe, currentTime: session.elapsed, height: small)
                } else {
                    BrewChart(samples: session.samples, recipe: session.recipe, currentTime: session.elapsed, height: big - 30)
                    MachineChart(samples: session.machineSamples, targetPressure: session.recipe.pressure,
                                 currentTime: session.elapsed, height: small)
                }
            }
        } else {
            BrewChart(samples: session.samples, recipe: session.recipe, currentTime: session.elapsed, height: height - 50)
        }
    }

    private func number(_ title: String, _ value: String, color: Color = .primary, size: CGFloat = 40) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: size, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
    }
}
