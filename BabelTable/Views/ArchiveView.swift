import SwiftUI

struct ArchiveView: View {
    @Environment(SessionStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var deleteFailed = false
    @State private var selection: ChatSession?
    @State private var searchText = ""
    @State private var deleteCandidate: ChatSession?

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .alert("Could not delete conversation", isPresented: $deleteFailed) {
            Button("OK", role: .cancel) {}
        } message: { Text("The conversation is still saved. Please try again.") }
        .confirmationDialog("Delete this conversation?", isPresented: deleteBinding, titleVisibility: .visible) {
            Button("Delete conversation", role: .destructive) {
                guard let deleteCandidate else { return }
                if store.delete(deleteCandidate) {
                    if selection?.id == deleteCandidate.id { selection = nil }
                } else { deleteFailed = true }
                self.deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        } message: {
            if let deleteCandidate {
                Text("The conversation from \(deleteCandidate.displayTitle) will be permanently removed from this device.")
            }
        }
    }

    @ViewBuilder
    private var sidebar: some View {
        Group {
            if store.sessions.isEmpty {
                ContentUnavailableView(
                    "No conversations yet",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Finished conversations are saved privately on this device.")
                )
            } else if groupedSessions.isEmpty {
                ContentUnavailableView.search(text: searchText)
            } else {
                List(selection: $selection) {
                    ForEach(groupedSessions) { group in
                        Section(group.date.formatted(.dateTime.weekday(.wide).month(.wide).day())) {
                            ForEach(group.sessions) { session in
                                NavigationLink(value: session) {
                                    ConversationRow(session: session)
                                }
                                .swipeActions(edge: .trailing) {
                                    Button("Delete", systemImage: "trash", role: .destructive) {
                                        deleteCandidate = session
                                    }
                                }
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("History")
        .searchable(text: $searchText, prompt: "Search conversations")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close", systemImage: "xmark") { dismiss() }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh", systemImage: "arrow.clockwise") { store.reload() }
                    .labelStyle(.iconOnly)
            }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let selection {
            SessionDetailView(session: store.sessions.first(where: { $0.id == selection.id }) ?? selection)
        } else {
            ContentUnavailableView(
                "Select a conversation",
                systemImage: "text.bubble",
                description: Text("Choose a saved conversation to read or share its transcript.")
            )
        }
    }

    private var filteredSessions: [ChatSession] {
        guard !searchText.isEmpty else { return store.sessions }
        let query = searchText.localizedLowercase
        return store.sessions.filter { session in
            session.displayTitle.localizedLowercase.contains(query)
                || session.previewText.localizedLowercase.contains(query)
                || SupportedLanguages.label(forCode: session.primaryLanguageCode).localizedLowercase.contains(query)
                || SupportedLanguages.label(forCode: session.secondaryLanguageCode).localizedLowercase.contains(query)
        }
    }

    private var groupedSessions: [SessionGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: filteredSessions) { calendar.startOfDay(for: $0.startedAt) }
        return grouped.map { SessionGroup(date: $0.key, sessions: $0.value.sorted { $0.startedAt > $1.startedAt }) }
            .sorted { $0.date > $1.date }
    }

    private var deleteBinding: Binding<Bool> {
        Binding(get: { deleteCandidate != nil }, set: { if !$0 { deleteCandidate = nil } })
    }
}

private struct SessionGroup: Identifiable {
    let date: Date
    let sessions: [ChatSession]
    var id: Date { date }
}

private struct ConversationRow: View {
    let session: ChatSession

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Text(session.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(.headline)
                Spacer()
                Label(session.durationDescription, systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            HStack(spacing: 6) {
                LanguagePill(languageCode: session.primaryLanguageCode,
                             title: SupportedLanguages.byCode(session.primaryLanguageCode)?.nativeName ?? session.primaryLanguageCode,
                             tint: BabelTheme.local)
                Image(systemName: "arrow.left.arrow.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                LanguagePill(languageCode: session.secondaryLanguageCode,
                             title: SupportedLanguages.byCode(session.secondaryLanguageCode)?.nativeName ?? session.secondaryLanguageCode,
                             tint: BabelTheme.remote)
            }
            Text(session.previewText.isEmpty ? "No transcript recorded" : session.previewText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

private extension ChatSession {
    var previewText: String {
        if let turn = chatTurns?.first {
            return turn.sourceText.isEmpty ? turn.bestTranslation : turn.sourceText
        }
        return primaryLines.first(where: { !$0.text.isEmpty })?.text
            ?? secondaryLines.first(where: { !$0.text.isEmpty })?.text
            ?? ""
    }
}
