import UIKit
import Vision

/// Recognizes the text on a photo of a coffee bag on the device (Apple Vision, nothing is uploaded)
/// and reads the bean details from it with `LabelParser`.
enum LabelScanner {
    static func scan(_ image: UIImage) async -> LabelParser.Result {
        guard let cgImage = image.cgImage else { return LabelParser.Result() }
        let orientation = CGImagePropertyOrientation(image.imageOrientation)
        let lines = await Task.detached(priority: .userInitiated) { () -> [LabelParser.Line] in
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "de-DE", "es-ES", "fr-FR"]
            do {
                try VNImageRequestHandler(cgImage: cgImage, orientation: orientation).perform([request])
            } catch {
                return []
            }
            return (request.results ?? []).compactMap { observation in
                guard let text = observation.topCandidates(1).first?.string else { return nil }
                // Vision's boxes are normalized with the origin at the bottom left.
                let box = observation.boundingBox
                return LabelParser.Line(text: text, height: box.height, top: 1 - box.maxY)
            }
        }.value
        return LabelParser.parse(lines)
    }
}

/// Bean photos: downsampled JPEGs so lists stay fast and backups small.
enum BeanPhoto {
    static let maxPixels: CGFloat = 1024
    static let quality: CGFloat = 0.8

    static func jpeg(from image: UIImage) -> Data? {
        let size = image.size
        let scale = min(1, maxPixels / max(size.width, size.height, 1))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    /// Only images a JPEG/PNG/HEIC decoder accepts, at most 10 MB (imported or picked files are untrusted).
    static func image(from data: Data) -> UIImage? {
        guard data.count <= 10_000_000 else { return nil }
        return UIImage(data: data)
    }
}

private extension CGImagePropertyOrientation {
    init(_ orientation: UIImage.Orientation) {
        switch orientation {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}
