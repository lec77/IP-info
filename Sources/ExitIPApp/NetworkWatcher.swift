import Foundation
import Network
import ExitIPCore

final class NetworkWatcher {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.lec77.ipinfo.network")
    private(set) var isOnline = true
    private(set) var supportsIPv6 = true
    /// The interface carrying the default route (first in NWPath's preference order).
    private(set) var interface: ActiveInterface?
    /// The first non-tunnel interface — where a request goes when it must
    /// bypass any VPN/proxy tunnel.
    private(set) var physicalInterface: NWInterface?
    var onPathChange: ((Bool) -> Void)?

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = (path.status == .satisfied)
            let supportsIPv6 = path.supportsIPv6
            let interface = path.availableInterfaces.first.map {
                ActiveInterface(name: $0.name, kind: interfaceKind(name: $0.name, type: $0.type))
            }
            let physical = path.availableInterfaces.first { interfaceKind(name: $0.name, type: $0.type).isPhysical }
            DispatchQueue.main.async {
                self?.isOnline = online
                self?.supportsIPv6 = supportsIPv6
                self?.interface = online ? interface : nil
                self?.physicalInterface = physical
                self?.onPathChange?(online)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }
}
