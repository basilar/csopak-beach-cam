import Foundation
import Compression

enum MiniZipError: Error {
    case notAZip
    case noEntries
    case unsupportedMethod(UInt16)
    case truncated
    case decompressFailed
}

enum MiniZip {
    private static let eocdSig: UInt32 = 0x0605_4b50
    private static let cdHeaderSig: UInt32 = 0x0201_4b50
    private static let lfhSig: UInt32 = 0x0403_4b50

    static func extractFirstEntry(from data: Data) throws -> Data {
        guard data.count >= 22 else { throw MiniZipError.notAZip }

        let eocdOffset = try findEOCD(in: data)
        let cdSize = readUInt32(data, eocdOffset + 12)
        let cdOffset = readUInt32(data, eocdOffset + 16)
        let numEntries = readUInt16(data, eocdOffset + 10)
        guard numEntries > 0 else { throw MiniZipError.noEntries }
        guard Int(cdOffset) + Int(cdSize) <= data.count else { throw MiniZipError.truncated }

        let cdStart = Int(cdOffset)
        guard readUInt32(data, cdStart) == cdHeaderSig else { throw MiniZipError.notAZip }

        let method = readUInt16(data, cdStart + 10)
        let compressedSize = Int(readUInt32(data, cdStart + 20))
        let uncompressedSize = Int(readUInt32(data, cdStart + 24))
        let nameLen = Int(readUInt16(data, cdStart + 28))
        let extraLen = Int(readUInt16(data, cdStart + 30))
        let commentLen = Int(readUInt16(data, cdStart + 32))
        let localOffset = Int(readUInt32(data, cdStart + 42))

        _ = nameLen + extraLen + commentLen

        guard localOffset + 30 <= data.count,
              readUInt32(data, localOffset) == lfhSig else {
            throw MiniZipError.notAZip
        }

        let lfhNameLen = Int(readUInt16(data, localOffset + 26))
        let lfhExtraLen = Int(readUInt16(data, localOffset + 28))
        let dataStart = localOffset + 30 + lfhNameLen + lfhExtraLen
        guard dataStart + compressedSize <= data.count else { throw MiniZipError.truncated }

        let payload = data.subdata(in: dataStart..<(dataStart + compressedSize))

        switch method {
        case 0:
            return payload
        case 8:
            return try inflateRaw(payload, expectedSize: uncompressedSize)
        default:
            throw MiniZipError.unsupportedMethod(method)
        }
    }

    private static func findEOCD(in data: Data) throws -> Int {
        let maxScan = min(data.count, 22 + 0xFFFF)
        let start = data.count - maxScan
        var i = data.count - 22
        while i >= start {
            if readUInt32(data, i) == eocdSig {
                return i
            }
            i -= 1
        }
        throw MiniZipError.notAZip
    }

    private static func inflateRaw(_ deflated: Data, expectedSize: Int) throws -> Data {
        let capacity = max(expectedSize, deflated.count * 8 + 1024)
        let dst = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { dst.deallocate() }
        let written = deflated.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
            guard let src = raw.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return 0 }
            return compression_decode_buffer(dst, capacity, src, deflated.count, nil, COMPRESSION_ZLIB)
        }
        guard written > 0 else { throw MiniZipError.decompressFailed }
        return Data(bytes: dst, count: written)
    }

    private static func readUInt16(_ data: Data, _ offset: Int) -> UInt16 {
        let b0 = UInt16(data[data.startIndex + offset])
        let b1 = UInt16(data[data.startIndex + offset + 1])
        return b0 | (b1 << 8)
    }

    private static func readUInt32(_ data: Data, _ offset: Int) -> UInt32 {
        let b0 = UInt32(data[data.startIndex + offset])
        let b1 = UInt32(data[data.startIndex + offset + 1])
        let b2 = UInt32(data[data.startIndex + offset + 2])
        let b3 = UInt32(data[data.startIndex + offset + 3])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }
}
