import Foundation
#if canImport(Compression)
import Compression
#endif

/// Minimal read-only ZIP reader for importing backups such as `Beanconqueror.zip`.
/// Supports stored and deflated entries, which is what zip.js and all common tools write.
/// No ZIP64, encryption or multi-part archives.
struct ZipArchive {
    struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    enum ZipError: LocalizedError, Equatable {
        case notAZip
        case corrupt
        case unsupportedMethod(UInt16)
        case tooLarge

        var errorDescription: String? {
            switch self {
            case .notAZip: return "This file isn't a ZIP archive."
            case .corrupt: return "The ZIP file is damaged or incomplete."
            case .unsupportedMethod: return "The ZIP file uses a compression method BrewLog can't read."
            case .tooLarge: return "The ZIP file is too large."
            }
        }
    }

    /// Upper bound per entry, so a hostile file can't make us allocate gigabytes.
    static let maxEntrySize = 100 * 1024 * 1024
    static let maxEntries = 10_000

    private let bytes: [UInt8]
    let entries: [Entry]

    static func isZip(_ data: Data) -> Bool {
        data.count >= 4 && Array(data.prefix(4)) == [0x50, 0x4B, 0x03, 0x04]
    }

    init(data: Data) throws {
        bytes = [UInt8](data)
        guard Self.isZip(data), bytes.count >= 22 else { throw ZipError.notAZip }

        // The end-of-central-directory record sits at the very end, followed by an optional comment (≤ 64 KB).
        var eocd: Int?
        var position = bytes.count - 22
        let lowest = max(0, bytes.count - 22 - 0xFFFF)
        while position >= lowest {
            if try Self.u32(bytes, position) == 0x0605_4B50 { eocd = position; break }
            position -= 1
        }
        guard let eocd else { throw ZipError.corrupt }

        let count = Int(try Self.u16(bytes, eocd + 10))
        let directoryOffset = Int(try Self.u32(bytes, eocd + 16))
        guard count <= Self.maxEntries else { throw ZipError.tooLarge }

        var entries: [Entry] = []
        var offset = directoryOffset
        for _ in 0..<count {
            guard try Self.u32(bytes, offset) == 0x0201_4B50 else { throw ZipError.corrupt }
            let method = try Self.u16(bytes, offset + 10)
            let compressed = Int(try Self.u32(bytes, offset + 20))
            let uncompressed = Int(try Self.u32(bytes, offset + 24))
            let nameLength = Int(try Self.u16(bytes, offset + 28))
            let extraLength = Int(try Self.u16(bytes, offset + 30))
            let commentLength = Int(try Self.u16(bytes, offset + 32))
            let localOffset = Int(try Self.u32(bytes, offset + 42))
            let nameEnd = offset + 46 + nameLength
            guard nameEnd <= bytes.count else { throw ZipError.corrupt }
            let name = String(decoding: bytes[(offset + 46)..<nameEnd], as: UTF8.self)
            entries.append(Entry(name: name, method: method, compressedSize: compressed,
                                 uncompressedSize: uncompressed, localHeaderOffset: localOffset))
            offset = nameEnd + extraLength + commentLength
        }
        self.entries = entries
    }

    func entry(named name: String) -> Entry? {
        entries.first { $0.name == name }
    }

    /// Returns the uncompressed contents of an entry.
    func data(for entry: Entry) throws -> Data {
        guard entry.uncompressedSize <= Self.maxEntrySize, entry.compressedSize <= Self.maxEntrySize else {
            throw ZipError.tooLarge
        }
        let header = entry.localHeaderOffset
        guard try Self.u32(bytes, header) == 0x0403_4B50 else { throw ZipError.corrupt }
        // Sizes in the local header may be 0 (data descriptor), so only the name/extra lengths are taken from it.
        let start = header + 30 + Int(try Self.u16(bytes, header + 26)) + Int(try Self.u16(bytes, header + 28))
        let end = start + entry.compressedSize
        guard start <= end, end <= bytes.count else { throw ZipError.corrupt }
        let raw = Array(bytes[start..<end])

        switch entry.method {
        case 0:
            return Data(raw)
        case 8:
            return try Self.inflate(raw, expectedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupportedMethod(entry.method)
        }
    }

    // MARK: Helpers

    private static func inflate(_ raw: [UInt8], expectedSize: Int) throws -> Data {
        guard expectedSize > 0 else { return Data() }
        guard !raw.isEmpty else { throw ZipError.corrupt }
        #if canImport(Compression)
        // COMPRESSION_ZLIB is raw DEFLATE (RFC 1951), exactly what ZIP stores.
        var output = [UInt8](repeating: 0, count: expectedSize)
        let written = raw.withUnsafeBufferPointer { source in
            output.withUnsafeMutableBufferPointer { destination in
                compression_decode_buffer(destination.baseAddress!, expectedSize,
                                          source.baseAddress!, raw.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written == expectedSize else { throw ZipError.corrupt }
        return Data(output)
        #else
        throw ZipError.unsupportedMethod(8)
        #endif
    }

    private static func u16(_ bytes: [UInt8], _ offset: Int) throws -> UInt16 {
        guard offset >= 0, offset + 2 <= bytes.count else { throw ZipError.corrupt }
        return UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }

    private static func u32(_ bytes: [UInt8], _ offset: Int) throws -> UInt32 {
        guard offset >= 0, offset + 4 <= bytes.count else { throw ZipError.corrupt }
        return UInt32(bytes[offset]) | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16 | UInt32(bytes[offset + 3]) << 24
    }
}
