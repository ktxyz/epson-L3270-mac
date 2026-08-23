import ArgumentParser
import Foundation
import L3270Core

@main
struct L3270Command: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "l3270",
        abstract: "Driverless printing to an Epson L3270 over IPP + PWG raster"
    )

    @Argument(help: "PDF or image file to print")
    var file: String

    @Option(help: "Paper size: a4 (default), letter, legal, a5, a6, b5, 4x6, 5x7, 8x10")
    var media: String = "a4"

    @Flag(name: .shortAndLong, help: "Grayscale instead of color")
    var mono: Bool = false

    @Option(help: "Number of copies")
    var copies: Int = 1

    @Option(help: "Substring of printer name to match (default L3270)")
    var printer: String = "L3270"

    @Option(help: "Printer host (skip discovery), e.g. EPSONB2D366.local")
    var host: String?

    @Option(help: "Write PWG raster to FILE instead of printing")
    var dryRun: String?

    func run() throws {
        let geometry = try L3270Core.geometry(for: media)
        let url = URL(fileURLWithPath: file)
        print("rendering \(file) (\(media), \(mono ? "mono" : "color"))...")
        let pages = try Renderer.renderFile(url: url, geometry: geometry, mono: mono)
        let document = try writePWGRaster(
            pages: pages,
            colorSpace: mono ? PWGRaster.colorSpaceSGray : PWGRaster.colorSpaceSRGB,
            mediaName: geometry.media,
            mediaWidth: geometry.sizeHW.width,
            mediaHeight: geometry.sizeHW.height
        )

        if let dryRun {
            try Data(document).write(to: URL(fileURLWithPath: dryRun))
            print("wrote \(document.count) bytes to \(dryRun)")
            return
        }

        let client: IPPClient
        if let host {
            client = IPPClient(host: host)
        } else {
            let printers = Discovery.findPrinters(matching: printer)
            guard let found = printers.first else {
                throw ValidationError("no IPP printer matching '\(printer)' found")
            }
            print("found \(found.name) at \(found.host):\(found.port)")
            client = IPPClient(host: found.host, port: found.port)
        }

        let attrs = try client.printJob(
            document: document,
            copies: copies,
            media: geometry.media,
            colorMode: mono ? "monochrome" : "color"
        )
        let jobID = attrs["job-id"]?.first ?? "?"
        print("job \(jobID) accepted (\(pages.count) page(s), \(copies) copy(ies))")
    }
}
