import Compression
import Foundation

/// Minimal self-contained ZIP reader. iOS has no public unzip API, so this
/// parses the end-of-central-directory record and central directory itself,
/// then extracts stored entries directly and inflates deflate-compressed
/// entries with the Compression framework.
enum ZipArchive {
    enum ZipError: LocalizedError {
        case unreadable
        case corrupt
        case unsupported
        case unsafePath(String)

        var errorDescription: String? {
            switch self {
            case .unreadable:
                return String(localized: "The ZIP archive could not be read.")
            case .corrupt:
                return String(localized: "The ZIP archive appears to be damaged.")
            case .unsupported:
                return String(localized: "The ZIP archive uses a compression feature this app does not support.")
            case .unsafePath(let name):
                return String(localized: "The ZIP archive contains an unsafe file path (\(name)).")
            }
        }
    }

    /// Extracts every safe entry into `destinationRoot`, creating it if needed.
    /// Metadata entries (`__MACOSX`, `.DS_Store`, AppleDouble files) are skipped
    /// and entries that would escape the destination (zip-slip) are rejected.
    static func extract(_ zipURL: URL, to destinationRoot: URL) throws {
        let data: Data
        do {
            data = try Data(contentsOf: zipURL, options: .mappedIfSafe)
        } catch {
            throw ZipError.unreadable
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let root = destinationRoot.standardizedFileURL.resolvingSymlinksInPath()
        let rootPath = root.path

        for entry in try centralDirectoryEntries(in: data) {
            guard !isMetadataEntry(entry.name) else { continue }

            let target = root.appendingPathComponent(entry.name).standardizedFileURL
            guard target.path == rootPath || target.path.hasPrefix(rootPath + "/") else {
                throw ZipError.unsafePath(entry.name)
            }

            if entry.isDirectory {
                try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
                continue
            }

            let contents = try fileContents(of: entry, in: data)
            try fileManager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: target)
        }
    }

    // MARK: - Central directory parsing

    private struct Entry {
        let name: String
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int

        var isDirectory: Bool {
            name.hasSuffix("/")
        }
    }

    private static let endOfCentralDirectorySignature: UInt32 = 0x0605_4b50
    private static let centralDirectorySignature: UInt32 = 0x0201_4b50
    private static let localHeaderSignature: UInt32 = 0x0403_4b50

    private static func centralDirectoryEntries(in data: Data) throws -> [Entry] {
        // The end-of-central-directory record is 22 bytes plus an optional
        // comment of up to 65535 bytes; scan backwards for its signature.
        let recordLength = 22
        guard data.count >= recordLength else { throw ZipError.corrupt }
        let lowestOffset = max(0, data.count - recordLength - 65535)
        var recordOffset = -1
        var searchOffset = data.count - recordLength
        while searchOffset >= lowestOffset {
            if readUInt32(data, at: searchOffset) == endOfCentralDirectorySignature {
                recordOffset = searchOffset
                break
            }
            searchOffset -= 1
        }
        guard recordOffset >= 0 else { throw ZipError.corrupt }

        let entryCount = Int(readUInt16(data, at: recordOffset + 10))
        let directoryOffset = Int(readUInt32(data, at: recordOffset + 16))
        guard entryCount != 0xFFFF, directoryOffset != 0xFFFF_FFFF else {
            // ZIP64 archives are out of scope for classroom-sized projects.
            throw ZipError.unsupported
        }
        guard directoryOffset < data.count else { throw ZipError.corrupt }

        var entries: [Entry] = []
        var offset = directoryOffset
        for _ in 0..<entryCount {
            guard offset + 46 <= data.count,
                  readUInt32(data, at: offset) == centralDirectorySignature else {
                throw ZipError.corrupt
            }

            let method = readUInt16(data, at: offset + 10)
            let compressedSize = Int(readUInt32(data, at: offset + 20))
            let uncompressedSize = Int(readUInt32(data, at: offset + 24))
            let nameLength = Int(readUInt16(data, at: offset + 28))
            let extraLength = Int(readUInt16(data, at: offset + 30))
            let commentLength = Int(readUInt16(data, at: offset + 32))
            let localHeaderOffset = Int(readUInt32(data, at: offset + 42))
            guard compressedSize != 0xFFFF_FFFF, uncompressedSize != 0xFFFF_FFFF else {
                throw ZipError.unsupported
            }
            guard offset + 46 + nameLength <= data.count else { throw ZipError.corrupt }

            let nameData = data.subdata(in: (offset + 46)..<(offset + 46 + nameLength))
            let name = String(data: nameData, encoding: .utf8)
                ?? String(data: nameData, encoding: .isoLatin1)
                ?? ""
            guard !name.isEmpty else { throw ZipError.corrupt }

            entries.append(Entry(
                name: name,
                method: method,
                compressedSize: compressedSize,
                uncompressedSize: uncompressedSize,
                localHeaderOffset: localHeaderOffset
            ))

            offset += 46 + nameLength + extraLength + commentLength
        }

        return entries
    }

    // MARK: - Entry extraction

    private static func fileContents(of entry: Entry, in data: Data) throws -> Data {
        // The local header repeats the name and can carry a different extra
        // field, so the data offset must be computed from the local record.
        let headerOffset = entry.localHeaderOffset
        guard headerOffset + 30 <= data.count,
              readUInt32(data, at: headerOffset) == localHeaderSignature else {
            throw ZipError.corrupt
        }

        let nameLength = Int(readUInt16(data, at: headerOffset + 26))
        let extraLength = Int(readUInt16(data, at: headerOffset + 28))
        let dataOffset = headerOffset + 30 + nameLength + extraLength
        guard dataOffset + entry.compressedSize <= data.count else { throw ZipError.corrupt }
        let compressed = data.subdata(in: dataOffset..<(dataOffset + entry.compressedSize))

        switch entry.method {
        case 0: // Stored (no compression)
            guard compressed.count == entry.uncompressedSize else { throw ZipError.corrupt }
            return compressed
        case 8: // Deflate
            return try inflate(compressed, uncompressedSize: entry.uncompressedSize)
        default:
            throw ZipError.unsupported
        }
    }

    private static func inflate(_ input: Data, uncompressedSize: Int) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }
        guard !input.isEmpty else { throw ZipError.corrupt }

        var output = Data(count: uncompressedSize)
        let written = output.withUnsafeMutableBytes { destination in
            input.withUnsafeBytes { source in
                // COMPRESSION_ZLIB decodes the raw deflate stream ZIP uses.
                compression_decode_buffer(
                    destination.bindMemory(to: UInt8.self).baseAddress!,
                    uncompressedSize,
                    source.bindMemory(to: UInt8.self).baseAddress!,
                    input.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard written == uncompressedSize else { throw ZipError.corrupt }
        return output
    }

    // MARK: - Helpers

    private static func isMetadataEntry(_ name: String) -> Bool {
        let components = name.split(separator: "/")
        guard let last = components.last else { return true }
        return components.contains("__MACOSX") || last == ".DS_Store" || last.hasPrefix("._")
    }

    private static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}
