import SwiftUI

struct InkPanelView: View {
    @ObservedObject var viewModel: PrinterViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(viewModel.printer?.name ?? "Epson L3270")
                    .font(.headline)
                Spacer()
                if let updated = viewModel.lastUpdated {
                    Text(updated, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let status = viewModel.status {
                Text(status.state)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                InkBar(label: "Black", color: .black, level: status.ink.black)
                InkBar(label: "Cyan", color: .cyan, level: status.ink.cyan)
                InkBar(label: "Magenta", color: .pink, level: status.ink.magenta)
                InkBar(label: "Yellow", color: .yellow, level: status.ink.yellow)

                if let waste = status.ink.waste {
                    InkBar(label: "Waste", color: .gray, level: waste)
                }

                if !status.ink.hasAnyLevel {
                    Text("Ink levels unavailable — check tanks visually.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Loading printer status…")
                    .foregroundStyle(.secondary)
            }

            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            switch viewModel.printCoordinator.state {
            case .idle:
                EmptyView()
            case .rendering:
                Text("Rendering…").font(.caption)
            case .sending:
                Text("Sending to printer…").font(.caption)
            case .success(let jobID):
                Text("Job \(jobID) accepted").font(.caption).foregroundStyle(.green)
            case .failed(let message):
                Text(message).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button("Refresh") {
                    Task { await viewModel.refresh() }
                }
                Spacer()
                Button("Print File…") {
                    PrintActions.openAndPrint(viewModel: viewModel)
                }
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}

struct InkBar: View {
    let label: String
    let color: Color
    let level: Int?

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 64, alignment: .leading)
                .font(.caption)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.gray.opacity(0.2))
                    if let level {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(color)
                            .frame(width: geo.size.width * CGFloat(level) / 100.0)
                    }
                }
            }
            .frame(height: 10)
            Text(level.map { "\($0)%" } ?? "—")
                .font(.caption2)
                .frame(width: 36, alignment: .trailing)
        }
    }
}
