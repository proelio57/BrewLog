import SwiftUI

/// Shown once after an update that changed something on iOS.
struct WhatsNewView: View {
    let notes: WhatsNew
    /// nil when shown inside Settings (no button, the back button leaves).
    var onDone: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(spacing: 6) {
                        Image(systemName: "sparkles").font(.system(size: 40)).foregroundStyle(.tint)
                        Text("What's new").font(.largeTitle.bold())
                        Text("Version \(notes.version)").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 32)
                    ForEach(notes.ios, id: \.self) { line in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.tint)
                            Text(line)
                        }
                    }
                }
                .padding(.horizontal, 24)
            }
            if let onDone {
                Button(action: onDone) {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(24)
            }
        }
    }
}
