import Foundation

/// Context-aware second pass over a finished turn's translation.
///
/// `gpt-realtime-translate` is a closed translation model — it accepts no
/// prompt, glossary, or formality controls and translates each utterance in
/// isolation. To make the *wording* smarter (consistent terminology, a chosen
/// register, a user glossary, and pronoun/term continuity across turns) we run
/// a cheap text model over the finished translation. The live stream is never
/// blocked; this only swaps in a better version once a turn has closed.
nonisolated struct TranslationRefiner: Sendable {

    /// One prior turn, used so the model can keep pronouns and terminology
    /// consistent with what was already said.
    struct ContextTurn: Sendable {
        let sourceText: String
        let translatedText: String
    }

    struct Request: Sendable {
        let apiKey: String
        let sourceText: String
        let draftTranslation: String
        let sourceLanguageEnglishName: String
        let targetLanguageEnglishName: String
        let formalityClause: String
        let glossary: [(source: String, target: String)]
        let recentContext: [ContextTurn]
    }

    /// Model used for refinement — small, fast, cheap text model.
    static let model = "gpt-4o-mini"

    private let endpoint = URL(string: "https://api.openai.com/v1/chat/completions")!

    /// Returns the improved translation, or nil on any failure (the caller then
    /// keeps the original machine translation). Never throws — refinement is
    /// strictly best-effort.
    func refine(_ req: Request) async -> String? {
        guard !req.apiKey.isEmpty,
              !req.sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !req.draftTranslation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }

        let body: [String: Any] = [
            "model": Self.model,
            "temperature": 0.3,
            "messages": [
                ["role": "system", "content": systemPrompt(req)],
                ["role": "user", "content": userPrompt(req)],
            ],
        ]

        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return nil }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("Bearer \(req.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                diagLog(.info, tag: "Refine", "skip: HTTP \(code)")
                return nil
            }
            guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = obj["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else { return nil }

            let cleaned = sanitize(content)
            return cleaned.isEmpty ? nil : cleaned
        } catch {
            diagLog(.info, tag: "Refine", "skip: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Prompt building

    private func systemPrompt(_ req: Request) -> String {
        var rules: [String] = [
            "You are a professional interpreter refining a real-time machine translation into \(req.targetLanguageEnglishName).",
            "You are given the original utterance and a rough draft translation. Produce the most natural, accurate, fluent version a human interpreter would say.",
            "Preserve meaning exactly. Do not add, omit, explain, or comment.",
            "Keep proper nouns, names, numbers, and units correct.",
        ]
        if !req.formalityClause.isEmpty { rules.append(req.formalityClause) }
        if !req.glossary.isEmpty {
            let entries = req.glossary.map { "- \"\($0.source)\" → \"\($0.target)\"" }.joined(separator: "\n")
            rules.append("Apply this glossary strictly when the source term appears:\n\(entries)")
        }
        if !req.recentContext.isEmpty {
            rules.append("Use the conversation history only to keep pronouns and terminology consistent — do not translate it again.")
        }
        rules.append("Respond with ONLY the refined \(req.targetLanguageEnglishName) translation as plain text — no quotes, labels, or notes.")
        return rules.joined(separator: "\n")
    }

    private func userPrompt(_ req: Request) -> String {
        var blocks: [String] = []
        if !req.recentContext.isEmpty {
            let history = req.recentContext.map {
                "• \($0.sourceText) → \($0.translatedText)"
            }.joined(separator: "\n")
            blocks.append("Conversation so far (for context only):\n\(history)")
        }
        blocks.append("Source (\(req.sourceLanguageEnglishName)):\n\(req.sourceText)")
        blocks.append("Draft translation (\(req.targetLanguageEnglishName)):\n\(req.draftTranslation)")
        blocks.append("Refined translation:")
        return blocks.joined(separator: "\n\n")
    }

    /// Strip wrapping quotes / stray labels the model occasionally adds.
    private func sanitize(_ text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Drop a leading "Refined translation:" style echo if present.
        if let range = s.range(of: "Refined translation:", options: .caseInsensitive),
           range.lowerBound == s.startIndex {
            s = String(s[range.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Unwrap a single pair of surrounding quotes.
        let quotePairs: [(Character, Character)] = [("\"", "\""), ("“", "”"), ("「", "」"), ("『", "』")]
        for (open, close) in quotePairs where s.count >= 2 && s.first == open && s.last == close {
            s = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines)
            break
        }
        return s
    }
}
