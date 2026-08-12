import Foundation
import Network

/// Privacy-neutral connectivity signal used to pause paid realtime sessions
/// while offline and avoid optional refinement traffic on constrained links.
nonisolated final class ConnectivityMonitor: @unchecked Sendable {
    enum Condition: Sendable, Equatable {
        case offline
        case constrained
        case online
    }

    var onChange: (@Sendable (Condition) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.xnu.babeltable.connectivity")

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let condition: Condition
            if path.status != .satisfied {
                condition = .offline
            } else if path.isConstrained || path.isExpensive {
                condition = .constrained
            } else {
                condition = .online
            }
            self?.onChange?(condition)
        }
        monitor.start(queue: queue)
    }

    func cancel() {
        monitor.cancel()
    }
}
