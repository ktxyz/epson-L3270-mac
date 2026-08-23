import Foundation

public enum PWGRaster {
    public static let headerSize = 1796
    public static let colorSpaceSRGB = 19
    public static let colorSpaceSGray = 18
}

public struct PageGeometry {
    public let media: String
    public let sizeHW: (width: Int, height: Int)
    public let widthPx: Int
    public let heightPx: Int
    public let printableWidthPx: Int
    public let printableHeightPx: Int
}

private let mediaTable: [String: (name: String, w: Int, h: Int)] = [
    "a4": ("iso_a4_210x297mm", 595, 841),
    "letter": ("na_letter_8.5x11in", 612, 792),
    "legal": ("na_legal_8.5x14in", 612, 1008),
    "a5": ("iso_a5_148x210mm", 420, 595),
    "a6": ("iso_a6_105x148mm", 298, 420),
    "b5": ("iso_b5_176x250mm", 499, 709),
    "4x6": ("na_index-4x6_4x6in", 288, 432),
    "5x7": ("na_5x7_5x7in", 360, 504),
    "8x10": ("na_8x10_8x10in", 576, 720),
]

public func geometry(for media: String) throws -> PageGeometry {
    guard let entry = mediaTable[media.lowercased()] else {
        throw NSError(domain: "L3270", code: 100,
                      userInfo: [NSLocalizedDescriptionKey: "unknown media '\(media)'"])
    }
    let widthPx = Int(round(Double(entry.w) / 72.0 * 360.0))
    let heightPx = Int(round(Double(entry.h) / 72.0 * 360.0))
    return PageGeometry(
        media: entry.name,
        sizeHW: (entry.w, entry.h),
        widthPx: widthPx,
        heightPx: heightPx,
        printableWidthPx: widthPx,
        printableHeightPx: heightPx
    )
}

private func put32(_ buf: inout [UInt8], _ offset: Int, _ value: Int) {
    buf[offset] = UInt8((value >> 24) & 0xFF)
    buf[offset + 1] = UInt8((value >> 16) & 0xFF)
    buf[offset + 2] = UInt8((value >> 8) & 0xFF)
    buf[offset + 3] = UInt8(value & 0xFF)
}

public func pageHeader(
    width: Int,
    height: Int,
    colorSpace: Int,
    mediaName: String = "iso_a4_210x297mm",
    mediaWidth: Int = 595,
    mediaHeight: Int = 841
) throws -> [UInt8] {
    guard colorSpace == PWGRaster.colorSpaceSRGB || colorSpace == PWGRaster.colorSpaceSGray else {
        throw NSError(domain: "L3270", code: 101,
                      userInfo: [NSLocalizedDescriptionKey: "invalid color space"])
    }
    let bpp = colorSpace == PWGRaster.colorSpaceSRGB ? 24 : 8
    let numColors = colorSpace == PWGRaster.colorSpaceSRGB ? 3 : 1
    let bpl = width * (bpp / 8)

    var buf = [UInt8](repeating: 0, count: PWGRaster.headerSize)
    Array("PwgRaster".utf8).enumerated().forEach { buf[$0.offset] = $0.element }
    put32(&buf, 276, 360)
    put32(&buf, 280, 360)
    put32(&buf, 284, 0)
    put32(&buf, 288, 0)
    put32(&buf, 292, mediaWidth)
    put32(&buf, 296, mediaHeight)
    put32(&buf, 324, 1)
    put32(&buf, 352, mediaWidth)
    put32(&buf, 356, mediaHeight)
    put32(&buf, 372, width)
    put32(&buf, 376, height)
    put32(&buf, 384, 8)
    put32(&buf, 388, bpp)
    put32(&buf, 392, bpl)
    put32(&buf, 396, 0)
    put32(&buf, 400, colorSpace)
    put32(&buf, 420, numColors)
    let base = 452
    put32(&buf, base + 0, 1)
    put32(&buf, base + 4, 1)
    put32(&buf, base + 8, 1)
    put32(&buf, base + 28, 0x00FFFFFF)
    let nameBytes = Array(mediaName.utf8.prefix(64))
    for (i, b) in nameBytes.enumerated() { buf[1732 + i] = b }
    return buf
}

func packbitsRow(_ row: [UInt8], bpp: Int) -> [UInt8] {
    var out = [UInt8]()
    let n = row.count
    var pos = 0
    while pos < n {
        let pixelEnd = min(pos + bpp, n)
        if pixelEnd == n {
            out.append(0)
            out.append(contentsOf: row[pos..<pixelEnd])
            break
        }
        let repeatSlice = row[pixelEnd..<min(pixelEnd + bpp, n)]
        if row[pos..<pixelEnd].elementsEqual(repeatSlice) {
            var count = 1
            var p = pos + bpp
            while p + bpp <= n,
                  row[pos..<pixelEnd].elementsEqual(row[p..<p + bpp]),
                  count < 128 {
                count += 1
                p += bpp
            }
            out.append(UInt8(count - 1))
            out.append(contentsOf: row[pos..<pixelEnd])
            pos = p
        } else {
            var count = 1
            var p = pos + bpp
            while count < 128, p < n - bpp,
                  !row[p..<p + bpp].elementsEqual(row[p + bpp..<p + 2 * bpp]) {
                count += 1
                p += bpp
            }
            if p >= n - bpp, count < 128 {
                count += 1
                p += bpp
            }
            out.append(UInt8((257 - count) & 0xFF))
            out.append(contentsOf: row[pos..<pos + count * bpp])
            pos = p
        }
    }
    return out
}

func compressRows(raw: [UInt8], width: Int, height: Int, bpp: Int) -> [UInt8] {
    let stride = width * bpp
    var out = [UInt8]()
    var y = 0
    while y < height {
        let row = Array(raw[(y * stride)..<((y + 1) * stride)])
        let encoded = packbitsRow(row, bpp: bpp)
        var repeat = 1
        var z = y + 1
        while z < height {
            let nextRow = Array(raw[(z * stride)..<((z + 1) * stride)])
            if packbitsRow(nextRow, bpp: bpp) != encoded { break }
            repeat += 1
            z += 1
        }
        out.append(UInt8(repeat - 1))
        out.append(contentsOf: encoded)
        y = z
    }
    return out
}

public func writePWGRaster(
    pages: [(raw: [UInt8], width: Int, height: Int)],
    colorSpace: Int,
    mediaName: String,
    mediaWidth: Int,
    mediaHeight: Int
) throws -> [UInt8] {
    let bpp = colorSpace == PWGRaster.colorSpaceSRGB ? 3 : 1
    var out = Array("RaS2".utf8)
    for page in pages {
        let header = try pageHeader(
            width: page.width,
            height: page.height,
            colorSpace: colorSpace,
            mediaName: mediaName,
            mediaWidth: mediaWidth,
            mediaHeight: mediaHeight
        )
        out.append(contentsOf: header)
        out.append(contentsOf: compressRows(
            raw: page.raw, width: page.width, height: page.height, bpp: bpp
        ))
    }
    return out
}
