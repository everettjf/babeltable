import Foundation

/// Single WebSocket connection to gpt-realtime-translate, configured for one
/// target output language. Auto-detects the source language from the audio
/// stream and emits transcript deltas (input = source-lang, output = target-lang).
nonisolated final class RealtimeTranslator: @unchecked Sendable {

    enum State: Sendable {
        case idle
        case connecting
        case ready
        case closed
        case failed(String)
    }

    enum Event: Sendable {
        /// Connection state changes.
        case state(State)
        /// Source-language transcript fragment of what the user just said.
        case inputDelta(String)
        /// Target-language translated transcript fragment.
        case outputDelta(String)
        /// An error occurred. `code` carries the server's structured error
        /// code/type when available (e.g. `insufficient_quota`); it is nil for
        /// client-side failures like a dropped socket.
        case error(message: String, code: String?)
    }

    /// Server-side noise reduction profile.
    enum NoiseReduction: String, Sendable {
        case nearField = "near_field"
        case farField = "far_field"
    }

    private let apiKey: String
    private let targetLanguageCode: String
    private let noiseReduction: NoiseReduction
    private let onEvent: @Sendable (Event) -> Void
    private let logTag: String

    private let session: URLSession
    private var task: URLSessionWebSocketTask?
    private var receiveLoop: Task<Void, Never>?
    private var pingTimer: DispatchSourceTimer?
    private var sendQueue = DispatchQueue(label: "BabelTable.WSSend")

    /// Heartbeat interval. A silently dead connection (NAT timeout, network
    /// switch) is otherwise only noticed on the next failed send — which may
    /// be minutes away when the user is just listening.
    private static let pingInterval: TimeInterval = 25

    init(apiKey: String,
         targetLanguageCode: String,
         noiseReduction: NoiseReduction = .farField,
         onEvent: @escaping @Sendable (Event) -> Void) {
        self.apiKey = apiKey
        self.targetLanguageCode = targetLanguageCode
        self.noiseReduction = noiseReduction
        self.onEvent = onEvent
        self.logTag = "WS-\(targetLanguageCode)"
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 60
        cfg.timeoutIntervalForResource = 60 * 60
        self.session = URLSession(configuration: cfg)
    }

    nonisolated func connect() {
        onEvent(.state(.connecting))
        diagLog(.info, tag: logTag, "Connecting → target=\(targetLanguageCode), noiseReduction=\(noiseReduction.rawValue)")

        guard let url = URL(string: "wss://api.openai.com/v1/realtime/translations?model=gpt-realtime-translate") else {
            diagLog(.error, tag: logTag, "Invalid URL")
            onEvent(.state(.failed("Invalid URL")))
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        let task = session.webSocketTask(with: request)
        self.task = task
        task.resume()

        // The /v1/realtime/translations endpoint does not accept a
        // `turn_detection` field (neither nested nor at the session root —
        // both produce "Unknown parameter"). The server picks VAD internally.
        let sessionUpdate: [String: Any] = [
            "type": "session.update",
            "session": [
                "audio": [
                    "input": [
                        "transcription": ["model": "gpt-realtime-whisper"],
                        "noise_reduction": ["type": noiseReduction.rawValue],
                    ],
                    "output": [
                        "language": targetLanguageCode
                    ],
                ],
            ],
        ]
        send(json: sessionUpdate)

        startReceiveLoop()
        startPingTimer()
    }

    nonisolated func close() {
        diagLog(.info, tag: logTag, "Closing")
        stopPingTimer()
        receiveLoop?.cancel()
        receiveLoop = nil
        // Best-effort: send session.close, then close the socket.
        send(json: ["type": "session.close"])
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
        onEvent(.state(.closed))
    }

    /// Send a PCM16 24kHz mono audio chunk. Hops off the real-time audio
    /// thread before base64-encoding (~10 chunks/sec per socket) so encoding
    /// cost never causes capture dropouts.
    nonisolated func appendAudio(_ pcm16Data: Data) {
        sendQueue.async { [weak self] in
            guard let self else { return }
            let b64 = pcm16Data.base64EncodedString()
            self.sendOnQueue(json: [
                "type": "session.input_audio_buffer.append",
                "audio": b64,
            ])
        }
    }

    // MARK: - Internals

    nonisolated private func send(json: [String: Any]) {
        sendQueue.async { [weak self] in
            self?.sendOnQueue(json: json)
        }
    }

    /// Must already be running on `sendQueue`.
    nonisolated private func sendOnQueue(json: [String: Any]) {
        guard let task else { return }
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return }
        guard let str = String(data: data, encoding: .utf8) else { return }
        task.send(.string(str)) { [weak self] error in
            guard let self, let error else { return }
            // Suppress URL-cancelled errors from intentional close().
            if Self.isCancellationError(error) { return }
            let ns = error as NSError
            diagLog(.error, tag: self.logTag, "Send failed: \(error.localizedDescription) (domain=\(ns.domain), code=\(ns.code))")
            self.onEvent(.error(message: "Send failed: \(error.localizedDescription)", code: nil))
        }
    }

    nonisolated private func startPingTimer() {
        stopPingTimer()
        let timer = DispatchSource.makeTimerSource(queue: sendQueue)
        timer.schedule(deadline: .now() + Self.pingInterval, repeating: Self.pingInterval)
        timer.setEventHandler { [weak self] in
            guard let self, let task = self.task else { return }
            task.sendPing { [weak self] error in
                guard let self, let error else { return }
                // A ping we can't even send means the socket is silently dead
                // (NAT timeout etc.) — surface it so the coordinator reconnects
                // instead of sitting "Live" on a dead connection.
                diagLog(.error, tag: self.logTag, "Ping failed: \(error.localizedDescription)")
                self.onEvent(.state(.failed("Ping failed: \(error.localizedDescription)")))
            }
        }
        pingTimer = timer
        timer.resume()
    }

    nonisolated private func stopPingTimer() {
        pingTimer?.cancel()
        pingTimer = nil
    }

    nonisolated private static func isCancellationError(_ error: Error) -> Bool {
        if let urlErr = error as? URLError, urlErr.code == .cancelled { return true }
        let ns = error as NSError
        return ns.domain == NSURLErrorDomain && ns.code == NSURLErrorCancelled
    }

    nonisolated private func startReceiveLoop() {
        receiveLoop?.cancel()
        receiveLoop = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                guard let task = self.task else { break }
                do {
                    let msg = try await task.receive()
                    self.handle(message: msg)
                } catch {
                    if !Task.isCancelled, !Self.isCancellationError(error) {
                        let ns = error as NSError
                        diagLog(.error, tag: self.logTag, "Receive failed: \(error.localizedDescription) (domain=\(ns.domain), code=\(ns.code))")
                        self.onEvent(.state(.failed(error.localizedDescription)))
                    } else {
                        diagLog(.info, tag: self.logTag, "Receive loop ended (cancelled)")
                    }
                    break
                }
            }
        }
    }

    nonisolated private func handle(message: URLSessionWebSocketTask.Message) {
        let text: String
        switch message {
        case .string(let s): text = s
        case .data(let d): text = String(data: d, encoding: .utf8) ?? ""
        @unknown default: return
        }
        guard let data = text.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String else { return }

        switch type {
        case "session.created", "session.updated":
            diagLog(.info, tag: logTag, type)
            onEvent(.state(.ready))
        case "session.closed":
            diagLog(.info, tag: logTag, "session.closed")
            onEvent(.state(.closed))
        case "session.input_transcript.delta":
            if let delta = obj["delta"] as? String, !delta.isEmpty {
                onEvent(.inputDelta(delta))
            }
        case "session.output_transcript.delta":
            if let delta = obj["delta"] as? String, !delta.isEmpty {
                onEvent(.outputDelta(delta))
            }
        case "session.output_audio.delta":
            // Ignored for MVP — text only.
            break
        case "error":
            let err = obj["error"] as? [String: Any]
            let msg = err?["message"] as? String ?? "Unknown error"
            let code = err?["code"] as? String ?? err?["type"] as? String
            // Capture the full server payload so rate-limit / quota / model
            // errors land in the log with their code + type, not just message.
            let detail = Self.compactJSON(obj) ?? text
            diagLog(.error, tag: logTag, "server error: \(detail)")
            onEvent(.error(message: msg, code: code))
        default:
            // Unknown / unhandled event types are rare but useful when
            // debugging API changes.
            diagLog(.info, tag: logTag, "event \(type)")
        }
    }

    nonisolated private static func compactJSON(_ obj: [String: Any]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: obj, options: []) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
