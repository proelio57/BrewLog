import SwiftUI
import PhotosUI
import UIKit

/// A bean's photo, or a drawn bean tinted by the roast level when there is none.
struct BeanThumbnail: View {
    let photo: Data?
    let roast: RoastLevel
    var size: CGFloat = 44

    var body: some View {
        Group {
            if let photo, let image = BeanPhotoCache.image(for: photo) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                BeanPlaceholder(roast: roast)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .accessibilityHidden(true)
    }
}

/// A coffee bean on a background from light honey to roasted umber.
struct BeanPlaceholder: View {
    let roast: RoastLevel

    static func tint(_ roast: RoastLevel) -> Color {
        switch roast {
        case .light: return Color(red: 0.86, green: 0.67, blue: 0.40)
        case .mediumLight: return Color(red: 0.76, green: 0.53, blue: 0.29)
        case .medium: return Color(red: 0.64, green: 0.42, blue: 0.22)
        case .mediumDark: return Color(red: 0.47, green: 0.30, blue: 0.17)
        case .dark: return Color(red: 0.31, green: 0.20, blue: 0.13)
        }
    }

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            ZStack {
                Self.tint(roast).opacity(0.25)
                ZStack {
                    Ellipse().fill(Self.tint(roast).gradient)
                    // The bean's crease.
                    Path { path in
                        let w = side * 0.34, h = side * 0.5
                        path.move(to: CGPoint(x: w / 2, y: 0))
                        path.addCurve(to: CGPoint(x: w / 2, y: h),
                                      control1: CGPoint(x: w * 0.15, y: h * 0.35),
                                      control2: CGPoint(x: w * 0.85, y: h * 0.65))
                    }
                    .stroke(Color.black.opacity(0.35), style: StrokeStyle(lineWidth: max(side * 0.035, 1), lineCap: .round))
                    .frame(width: side * 0.34, height: side * 0.5)
                }
                .frame(width: side * 0.42, height: side * 0.6)
                .rotationEffect(.degrees(28))
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

/// Decoded photos by data, so lists don't decode the same JPEG on every redraw.
enum BeanPhotoCache {
    private static let cache: NSCache<NSData, UIImage> = {
        let cache = NSCache<NSData, UIImage>()
        cache.countLimit = 60
        return cache
    }()

    static func image(for data: Data) -> UIImage? {
        let key = data as NSData
        if let image = cache.object(forKey: key) { return image }
        guard let image = BeanPhoto.image(from: data) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// The system camera, for a photo of the bag.
struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}

/// Photo and label scan section of the bean editor.
struct BeanPhotoSection: View {
    @Binding var photo: Data?
    let roast: RoastLevel
    /// Called with what the label scan found.
    let onScan: (LabelParser.Result) -> Void

    private enum Purpose { case photo, scan }

    @State private var pickerItem: PhotosPickerItem?
    @State private var showPicker = false
    @State private var showCamera = false
    @State private var purpose: Purpose = .photo
    @State private var scanning = false
    @State private var message: String?

    var body: some View {
        Section {
            HStack(spacing: 14) {
                BeanThumbnail(photo: photo, roast: roast, size: 76)
                VStack(alignment: .leading, spacing: 8) {
                    Menu {
                        if CameraPicker.isAvailable {
                            Button { choose(.photo, camera: true) } label: { Label("Take photo", systemImage: "camera") }
                        }
                        Button { choose(.photo, camera: false) } label: { Label("Choose photo", systemImage: "photo") }
                        if photo != nil {
                            Button(role: .destructive) { photo = nil } label: { Label("Remove photo", systemImage: "trash") }
                        }
                    } label: {
                        Label(photo == nil ? "Add photo" : "Change photo", systemImage: "photo.badge.plus")
                    }
                    Menu {
                        if CameraPicker.isAvailable {
                            Button { choose(.scan, camera: true) } label: { Label("Photograph the label", systemImage: "camera") }
                        }
                        Button { choose(.scan, camera: false) } label: { Label("Choose a photo", systemImage: "photo") }
                    } label: {
                        if scanning {
                            HStack { ProgressView(); Text("Reading label…") }
                        } else {
                            Label("Scan label", systemImage: "text.viewfinder")
                        }
                    }
                    .disabled(scanning)
                    .accessibilityIdentifier("bean.scanLabel")
                }
                .font(.subheadline.weight(.semibold))
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.secondary)
            }
        } header: {
            Text("Photo")
        } footer: {
            Text("Scan label reads name, origin, process, varietal, roast date and weight from the bag. The text is recognized on this iPhone, nothing is uploaded. Check the fields afterwards.")
        }
        .photosPicker(isPresented: $showPicker, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) {
            guard let item = pickerItem else { return }
            pickerItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self), let image = BeanPhoto.image(from: data) {
                    await handle(image)
                }
            }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraPicker { image in Task { await handle(image) } }
                .ignoresSafeArea()
        }
    }

    private func choose(_ purpose: Purpose, camera: Bool) {
        self.purpose = purpose
        if camera { showCamera = true } else { showPicker = true }
    }

    @MainActor
    private func handle(_ image: UIImage) async {
        switch purpose {
        case .photo:
            photo = BeanPhoto.jpeg(from: image)
        case .scan:
            scanning = true
            message = nil
            let result = await LabelScanner.scan(image)
            scanning = false
            // The bag photo doubles as the bean's photo when there is none yet.
            if photo == nil { photo = BeanPhoto.jpeg(from: image) }
            if result.isEmpty {
                message = "No details found. Try a sharper photo, straight on and in good light."
            } else {
                message = "Found " + result.foundFields.joined(separator: ", ") + "."
                onScan(result)
            }
        }
    }
}
