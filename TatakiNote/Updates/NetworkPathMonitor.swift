import Foundation
import Network

/// ネットワークにつながっているかの見張り。
protocol NetworkReachability: AnyObject {
    func start(onChange: @escaping @MainActor (Bool) -> Void)
}

/// `NWPathMonitor` で、経路が使える間をつながっているとみなす。知らせはメインスレッドで呼ぶ。
final class NetworkPathMonitor: NetworkReachability {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkPathMonitor")
    private let relay = MainActorRelay()
    private var isStarted = false

    deinit {
        monitor.cancel()
    }

    func start(onChange: @escaping @MainActor (Bool) -> Void) {
        guard !isStarted else { return }
        isStarted = true
        let relay = relay
        monitor.pathUpdateHandler = { path in
            let isOnline = path.status == .satisfied
            relay.send { onChange(isOnline) }
        }
        monitor.start(queue: queue)
    }
}
