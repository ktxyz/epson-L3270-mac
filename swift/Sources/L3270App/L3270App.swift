import SwiftUI

@main
struct L3270App: App {
    @StateObject private var viewModel = PrinterViewModel()

    var body: some Scene {
        MenuBarExtra("L3270", systemImage: "printer.fill") {
            VStack(spacing: 0) {
                InkPanelView(viewModel: viewModel)
                    .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                        handleDrop(providers)
                    }
                    .onAppear {
                        if viewModel.printer == nil { viewModel.discoverPrinter() }
                        viewModel.start()
                        Task { await viewModel.refresh() }
                    }
            }
            .sheet(isPresented: $viewModel.showSetup) {
                SetupView(viewModel: viewModel)
            }

            Divider()

            Button("Print File…") {
                PrintActions.openAndPrint(viewModel: viewModel)
            }

            Button("Settings…") {
                openSettings()
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: viewModel)
        }
    }

    init() {
        NotificationManager.requestAuthorization()
    }

    private func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    PrintActions.printDroppedURLs([url], viewModel: viewModel)
                }
            }
        }
        return true
    }
}
