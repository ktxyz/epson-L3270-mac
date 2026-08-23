import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: PrinterViewModel
    @Environment(\.dismiss) private var dismiss

    private let mediaOptions = ["a4", "letter", "legal", "a5", "a6", "b5", "4x6", "5x7", "8x10"]

    var body: some View {
        Form {
            Section("Printer") {
                Text(viewModel.printer?.name ?? "Not discovered")
                Text(viewModel.printer?.host ?? "—")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Rediscover") { viewModel.discoverPrinter() }
            }
            Section("Defaults") {
                Picker("Paper", selection: $viewModel.defaultMedia) {
                    ForEach(mediaOptions, id: \.self) { Text($0.uppercased()).tag($0) }
                }
                Toggle("Grayscale by default", isOn: $viewModel.defaultMono)
            }
            Section("Ink polling") {
                Stepper("Every \(viewModel.pollIntervalSeconds)s", value: $viewModel.pollIntervalSeconds, in: 30...600, step: 30)
            }
            Section("Password") {
                Button("Change admin password…") {
                    viewModel.showSetup = true
                    dismiss()
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 360, height: 380)
        .toolbar {
            Button("Done") { dismiss() }
        }
    }
}
