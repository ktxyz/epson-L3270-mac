import AppKit
import UniformTypeIdentifiers

enum PrintActions {
    @MainActor
    static func openAndPrint(viewModel: PrinterViewModel) {
        guard let printer = viewModel.printer else {
            viewModel.discoverPrinter()
            return
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pdf, .jpeg, .png, .heic, .tiff]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task {
                await viewModel.printCoordinator.printFile(
                    url: url,
                    printer: printer,
                    media: viewModel.defaultMedia,
                    mono: viewModel.defaultMono
                )
            }
        }
    }

    @MainActor
    static func printDroppedURLs(_ urls: [URL], viewModel: PrinterViewModel) {
        guard let printer = viewModel.printer, let url = urls.first else { return }
        Task {
            await viewModel.printCoordinator.printFile(
                url: url,
                printer: printer,
                media: viewModel.defaultMedia,
                mono: viewModel.defaultMono
            )
        }
    }
}
