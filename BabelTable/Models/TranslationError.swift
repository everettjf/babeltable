import Foundation

struct TranslationError: Equatable, Sendable {
    enum Recovery: Equatable, Sendable {
        case none
        case openSettings
        case openURL(URL)
    }
    let title = "Offline translation unavailable"
    let message: String
    var recovery: Recovery { .openSettings }
    var recoveryTitle: String? { "Open Settings" }
    init(raw: String) { message = raw }
}

enum OfflineError: LocalizedError {
    case unsupported
    case modelsUnavailable
    case modelsMissing
    case audioFormat
    case overloaded

    var errorDescription: String? {
        switch self {
        case .unsupported: "This device or language pair does not support offline speech translation. Choose another pair in Settings."
        case .modelsUnavailable: "The local language services could not be checked. Please try again in a moment."
        case .modelsMissing: "Download the speech and translation models in Settings before starting an offline conversation."
        case .audioFormat: "The local speech engine could not prepare its audio format. Try starting again."
        case .overloaded: "The device could not keep up with speech recognition. Translation has stopped; please try again."
        }
    }
}
