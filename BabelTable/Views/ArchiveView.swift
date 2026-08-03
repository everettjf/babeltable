import SwiftUI

struct ArchiveView: View {
    @Environment(SessionStore.self) private var store

    @State private var selection: ChatSession?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        Group {
            if store.sessions.isEmpty {
                ContentUnavailableView(
                    "No archived sessions",
                    systemImage: "tray",
                    description: Text("Each chat you finish will appear here.")
                )
            } else {
                List(selection: $selection) {
                    ForEach(store.sessions) { session in
                        NavigationLink(value: session) {
                            row(for: session)
                        }
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Archive")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selection {
            SessionDetailView(session: selection)
        } else {
            ContentUnavailableView(
                "Select a conversation",
                systemImage: "tray",
                description: Text("Pick a session from the list to view its transcript.")
            )
        }
    }

    @ViewBuilder
    private func row(for session: ChatSession) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.displayTitle)
                .font(.headline)
            HStack(spacing: 8) {
                Text(SupportedLanguages.byCode(session.primaryLanguageCode)?.nativeName ?? session.primaryLanguageCode)
                Text("⇄")
                    .foregroundStyle(.secondary)
                Text(SupportedLanguages.byCode(session.secondaryLanguageCode)?.nativeName ?? session.secondaryLanguageCode)
                Spacer()
                Text(session.durationDescription)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.caption)
        }
        .padding(.vertical, 4)
    }

    private func delete(at offsets: IndexSet) {
        for idx in offsets {
            let session = store.sessions[idx]
            if selection?.id == session.id { selection = nil }
            store.delete(session)
        }
    }
}
