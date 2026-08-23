import Foundation
import L3270Core

@MainActor
public final class PrintCoordinator: ObservableObject {
    public enum State: Equatable {
        case idle
        case rendering
        case sending
        case success(jobID: String)
        case failed(String)
    }

    @Published public private(set) var state: State = .idle

    public init() {}

    public func printFile(
        url: URL,
        printer: Discovery.Printer,
        media: String,
        mono: Bool,
        copies: Int = 1
    ) async {
        state = .rendering
        do {
            let geometry = try geometry(for: media)
            let pages = try Renderer.renderFile(url: url, geometry: geometry, mono: mono)
            let document = try writePWGRaster(
                pages: pages,
                colorSpace: mono ? PWGRaster.colorSpaceSGray : PWGRaster.colorSpaceSRGB,
                mediaName: geometry.media,
                mediaWidth: geometry.sizeHW.width,
                mediaHeight: geometry.sizeHW.height
            )
            state = .sending
            let client = IPPClient(host: printer.host, port: printer.port, resource: printer.resource)
            let attrs = try client.printJob(
                document: document,
                copies: copies,
                media: geometry.media,
                colorMode: mono ? "monochrome" : "color"
            )
            let jobID = attrs["job-id"]?.first ?? "?"
            state = .success(jobID: jobID)
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    public func reset() {
        state = .idle
    }
}
