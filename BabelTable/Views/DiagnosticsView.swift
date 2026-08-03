import SwiftUI
import UIKit

/// Settings → Diagnostics. Shows the in-app log buffer captured by
/// `DiagnosticsLogger`, with copy / share / clear actions for shipping
/// logs out when reproducing an issue.
struct DiagnosticsView: View {
    @State private var logger = DiagnosticsLogger.shared
    @State private var filter: FilterOption = .all
    @State private var copied = false
    @State private var showingShare = false
    @State private var confirmClear = false

    private enum FilterOption: String, CaseIterable, Identifiable {
        case all, error, warn, info
        var id: String { rawValue }
        var label: String {
            switch self {
            case .all: return "All"
            case .error: return "Errors"
            case .warn: return "Warnings"
            case .info: return "Info"
            }
        }
    }

    private var filteredEntries: [DiagnosticsLogger.Entry] {
        let source = logger.entries
        switch filter {
        case .all: return source.reversed()
        case .error: return source.filter { $0.level == .error }.reversed()
        case .warn: return source.filter { $0.level == .warn }.reversed()
        case .info: return source.filter { $0.level == .info }.reversed()
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Filter", selection: $filter) {
                ForEach(FilterOption.allCases) { opt in
                    Text(opt.label).tag(opt)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.vertical, 8)

            if filteredEntries.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(filteredEntries) { entry in
                        LogRow(entry: entry)
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Diagnostics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        UIPasteboard.general.string = logger.exportText()
                        copied = true
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(1.5))
                            copied = false
                        }
                    } label: {
                        Label(copied ? "Copied" : "Copy all", systemImage: "doc.on.doc")
                    }
                    .disabled(logger.entries.isEmpty)

                    Button {
                        showingShare = true
                    } label: {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                    .disabled(logger.entries.isEmpty)

                    Divider()

                    Button(role: .destructive) {
                        confirmClear = true
                    } label: {
                        Label("Clear logs", systemImage: "trash")
                    }
                    .disabled(logger.entries.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showingShare) {
            ShareSheet(items: [logger.exportText()])
        }
        .confirmationDialog("Clear all logs?",
                            isPresented: $confirmClear,
                            titleVisibility: .visible) {
            Button("Clear", role: .destructive) { logger.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes \(logger.entries.count) entries from memory and disk.")
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            Text("No logs to show")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("Logs appear here as the app runs — connection events, translator messages, and errors.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct LogRow: View {
    let entry: DiagnosticsLogger.Entry

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss.SSS"
        return f
    }()

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(entry.level.label)
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(levelColor.opacity(0.18), in: .capsule)
                    .foregroundStyle(levelColor)

                Text(entry.tag)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)

                Spacer()

                Text(Self.timeFormatter.string(from: entry.timestamp))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            Text(entry.message)
                .font(.callout)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
    }

    private var levelColor: Color {
        switch entry.level {
        case .info: return .blue
        case .warn: return .orange
        case .error: return .red
        }
    }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
