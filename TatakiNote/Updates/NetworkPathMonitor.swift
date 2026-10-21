import Foundation
import Network

/// ネットワークにつながっているかの見張り。
protocol NetworkReachability: AnyObject {
    func start(onChange: @escaping (Bool) -> Void)
}

/// `NWPathMonitor` で、経路が使える間をつながっているとみなす。知らせはメインスレッドで呼ぶ。
final class NetworkPathMonitor: NetworkReachability {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkPathMonitor")
    private var isStarted = false

    deinit {
        monitor.cancel()
    }

    func start(onChange: @escaping (Bool) -> Void) {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { path in
            let isOnline = path.status == .satisfied
            DispatchQueue.main.async {
                onChange(isOnline)
            }
        }
        monitor.start(queue: queue)
    }
}
