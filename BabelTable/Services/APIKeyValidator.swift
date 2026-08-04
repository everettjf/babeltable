import Foundation

/// Validates an OpenAI API key with a lightweight authenticated request
/// before it is saved. `GET /v1/models` is the cheapest endpoint that
/// requires auth:
///   - 200 → key works
///   - 401 → key rejected
///   - 429 → key authenticated but rate-limited / out of quota — the key
///     itself is valid, so this still counts as a passed connection test
///   - anything else, or a network failure → unreachable
enum APIKeyValidator {
    enum Outcome: Sendable, Equatable {
        case valid
        case invalid
        case unreachable(String)
    }

    static func validate(_ apiKey: String) async -> Outcome {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .unreachable("Unexpected response from OpenAI.")
            }
            switch http.statusCode {
            case 200, 429:
                return .valid
            case 401:
                return .invalid
            default:
                return .unreachable("OpenAI returned HTTP \(http.statusCode).")
            }
        } catch {
            return .unreachable(error.localizedDescription)
        }
    }
}
