import Compression
import Foundation

enum ZipArchive {
    struct Entry {
        let path: String
        let data: Data
    }

    /// собирает zip-архив из набора файлов в памяти: deflate там, где он выигрывает, иначе store
    static func archive(entries: [Entry]) -> Data {
        var result: Data = Data()
        var central: Data = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let nameBytes: [UInt8] = Array(entry.path.utf8)
            let crc: UInt32 = crc32(entry.data)
            let originalSize: UInt32 = UInt32(entry.data.count)
            let compressed: Data? = deflate(entry.data)
            let payload: Data = compressed ?? entry.data
            let method: UInt16 = compressed == nil ? 0 : 8
            let storedSize: UInt32 = UInt32(payload.count)

            var local: Data = Data()
            local.append(contentsOf: le32(0x0403_4b50))
            local.append(contentsOf: le16(20))
            local.append(contentsOf: le16(0))
            local.append(contentsOf: le16(method))
            local.append(contentsOf: le16(0))
            local.append(contentsOf: le16(0))
            local.append(contentsOf: le32(crc))
            local.append(contentsOf: le32(storedSize))
            local.append(contentsOf: le32(originalSize))
            local.append(contentsOf: le16(UInt16(nameBytes.count)))
            local.append(contentsOf: le16(0))
            local.append(contentsOf: nameBytes)
            local.append(payload)
            result.append(local)

            central.append(contentsOf: le32(0x0201_4b50))
            central.append(contentsOf: le16(20))
            central.append(contentsOf: le16(20))
            central.append(contentsOf: le16(0))
            central.append(contentsOf: le16(method))
            central.append(contentsOf: le16(0))
            central.append(contentsOf: le16(0))
            central.append(contentsOf: le32(crc))
            central.append(contentsOf: le32(storedSize))
            central.append(contentsOf: le32(originalSize))
            central.append(contentsOf: le16(UInt16(nameBytes.count)))
            central.append(contentsOf: le16(0))
            central.append(contentsOf: le16(0))
            central.append(contentsOf: le16(0))
            central.append(contentsOf: le16(0))
            central.append(contentsOf: le32(0))
            central.append(contentsOf: le32(offset))
            central.append(contentsOf: nameBytes)

            offset += UInt32(local.count)
        }

        let centralOffset: UInt32 = offset
        let centralSize: UInt32 = UInt32(central.count)
        result.append(central)

        var end: Data = Data()
        end.append(contentsOf: le32(0x0605_4b50))
        end.append(contentsOf: le16(0))
        end.append(contentsOf: le16(0))
        end.append(contentsOf: le16(UInt16(entries.count)))
        end.append(contentsOf: le16(UInt16(entries.count)))
        end.append(contentsOf: le32(centralSize))
        end.append(contentsOf: le32(centralOffset))
        end.append(contentsOf: le16(0))
        result.append(end)

        return result
    }

    /// сжимает данные в raw deflate; nil означает, что выигрыша нет и файл надо класть как есть
    private static func deflate(_ data: Data) -> Data? {
        if data.isEmpty {
            return nil
        }
        let capacity: Int = data.count
        var output: Data = Data(count: capacity)
        let written: Int = output.withUnsafeMutableBytes { destination in
            data.withUnsafeBytes { source in
                guard let destinationBase: UnsafeMutablePointer<UInt8> = destination.baseAddress?.assumingMemoryBound(to: UInt8.self),
                    let sourceBase: UnsafePointer<UInt8> = source.baseAddress?.assumingMemoryBound(to: UInt8.self)
                else {
                    return 0
                }
                return compression_encode_buffer(destinationBase, capacity, sourceBase, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        if written == 0 {
            return nil
        }
        return output.prefix(written)
    }

    private static func le16(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xff), UInt8((value >> 8) & 0xff)]
    }

    private static func le32(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xff),
            UInt8((value >> 8) & 0xff),
            UInt8((value >> 16) & 0xff),
            UInt8((value >> 24) & 0xff),
        ]
    }

    private static let crcTable: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value: UInt32 = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = crcTable[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}
