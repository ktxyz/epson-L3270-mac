import Foundation
import CoreGraphics
import ImageIO
import PDFKit
import UniformTypeIdentifiers

/// Renders PDFs and images into raw pixel pages sized for the printer.
public enum Renderer {
    public static func renderPDFPage(
        page: CGPDFPage,
        geometry: PageGeometry,
        mono: Bool
    ) -> (raw: [UInt8], width: Int, height: Int) {
        let mediaBox = page.getBoxRect(.mediaBox)
        let scale = min(
            CGFloat(geometry.printableWidthPx) / mediaBox.width,
            CGFloat(geometry.printableHeightPx) / mediaBox.height
        )
        let drawWidth = max(1, mediaBox.width * scale)
        let drawHeight = max(1, mediaBox.height * scale)

        let width = geometry.widthPx
        let height = geometry.heightPx
        let scratch = renderScratch(width: width, height: height) { context in
            context.translateBy(
                x: (CGFloat(width) - drawWidth) / 2,
                y: (CGFloat(height) - drawHeight) / 2
            )
            context.scaleBy(x: drawWidth / mediaBox.width, y: drawHeight / mediaBox.height)
            context.translateBy(x: -mediaBox.origin.x, y: -mediaBox.origin.y)
            context.drawPDFPage(page)
        }
        if mono {
            return (rgbToGray(raw: scratch, width: width, height: height), width, height)
        }
        return (rgbaToRGB(raw: scratch, width: width, height: height), width, height)
    }

    public static func renderPDF(
        url: URL,
        geometry: PageGeometry,
        mono: Bool
    ) throws -> [(raw: [UInt8], width: Int, height: Int)] {
        guard let document = CGPDFDocument(url as CFURL) else {
            throw NSError(domain: "L3270", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "cannot open PDF \(url.path)"])
        }
        var pages: [(raw: [UInt8], width: Int, height: Int)] = []
        for index in 1...document.numberOfPages {
            guard let page = document.page(at: index) else { continue }
            pages.append(renderPDFPage(page: page, geometry: geometry, mono: mono))
        }
        return pages
    }

    public static func renderImage(
        url: URL,
        geometry: PageGeometry,
        mono: Bool
    ) throws -> [(raw: [UInt8], width: Int, height: Int)] {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw NSError(domain: "L3270", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "cannot open image \(url.path)"])
        }

        let width = geometry.widthPx
        let height = geometry.heightPx
        let scale = min(
            CGFloat(geometry.printableWidthPx) / CGFloat(image.width),
            CGFloat(geometry.printableHeightPx) / CGFloat(image.height)
        )
        let drawWidth = max(1, CGFloat(image.width) * scale)
        let drawHeight = max(1, CGFloat(image.height) * scale)

        let scratch = renderScratch(width: width, height: height) { context in
            context.translateBy(x: (CGFloat(width) - drawWidth) / 2, y: (CGFloat(height) - drawHeight) / 2)
            context.draw(image, in: CGRect(x: 0, y: 0, width: drawWidth, height: drawHeight))
        }
        if mono {
            return [(rgbToGray(raw: scratch, width: width, height: height), width, height)]
        }
        return [(rgbaToRGB(raw: scratch, width: width, height: height), width, height)]
    }

    public static func renderFile(
        url: URL,
        geometry: PageGeometry,
        mono: Bool
    ) throws -> [(raw: [UInt8], width: Int, height: Int)] {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            return try renderPDF(url: url, geometry: geometry, mono: mono)
        }
        return try renderImage(url: url, geometry: geometry, mono: mono)
    }

    private static func renderScratch(
        width: Int,
        height: Int,
        draw: (CGContext) -> Void
    ) -> [UInt8] {
        let bytesPerRow = width * 4
        var raw = [UInt8](repeating: 0xFF, count: bytesPerRow * height)
        raw.withUnsafeMutableBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard let context = CGContext(
                data: base,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
            ) else { return }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            draw(context)
        }
        return raw
    }

    /// CoreGraphics noneSkipFirst layout: [skip, R, G, B].
    static func rgbaToRGB(raw: [UInt8], width: Int, height: Int) -> [UInt8] {
        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        for y in 0..<height {
            for x in 0..<width {
                let src = (y * width + x) * 4
                let dst = (y * width + x) * 3
                rgb[dst] = raw[src + 1]
                rgb[dst + 1] = raw[src + 2]
                rgb[dst + 2] = raw[src + 3]
            }
        }
        return rgb
    }

    static func rgbToGray(raw: [UInt8], width: Int, height: Int) -> [UInt8] {
        var gray = [UInt8](repeating: 0, count: width * height)
        for y in 0..<height {
            for x in 0..<width {
                let src = (y * width + x) * 4
                let r = Int(raw[src + 1])
                let g = Int(raw[src + 2])
                let b = Int(raw[src + 3])
                gray[y * width + x] = UInt8(min(255, (r * 299 + g * 587 + b * 114) / 1000))
            }
        }
        return gray
    }
}
