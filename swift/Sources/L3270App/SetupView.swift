import SwiftUI

struct SetupView: View {
    @ObservedObject var viewModel: PrinterViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Printer Password")
                .font(.headline)
            Text("The initial admin password is printed on a label attached to your Epson printer (usually near the serial number).")
                .font(.caption)
                .foregroundStyle(.secondary)
            SecureField("Password from label", text: $viewModel.passwordInput)
                .textFieldStyle(.roundedBorder)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Save") {
                    viewModel.savePassword()
                    if !viewModel.showSetup { dismiss() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.passwordInput.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
    }
}
