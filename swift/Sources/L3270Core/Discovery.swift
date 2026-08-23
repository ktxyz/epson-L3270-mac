import Foundation
import Network

/// Discovers IPP printers via Bonjour (_ipp._tcp.local.).
public enum Discovery {
    public struct Printer: Equatable {
        public let name: String
        public let host: String
        public let port: Int
        public let resource: String
    }

    public static func findPrinters(
        matching pattern: String = "",
        timeout: TimeInterval = 3.0
    ) -> [Printer] {
        let sem = DispatchSemaphore(value: 0)
        var results: [Printer] = []

        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: "_ipp._tcp", domain: nil),
            using: NWParameters()
        )
        browser.browseResultsChangedHandler = { browsed, _ in
            for result in browsed {
                guard case let .service(name, _, _, _) = result.endpoint else { continue }
                guard pattern.isEmpty || name.lowercased().contains(pattern.lowercased()) else {
                    continue
                }
                results.append(Printer(name: name, host: "", port: 631, resource: "/ipp/print"))
            }
            if !results.isEmpty { sem.signal() }
        }
        browser.stateUpdateHandler = { state in
            if case .failed = state { sem.signal() }
        }
        browser.start(queue: .global())
        _ = sem.wait(timeout: .now() + timeout)
        browser.cancel()

        var resolved: [Printer] = []
        let group = DispatchGroup()
        let lock = NSLock()
        for printer in results {
            if resolved.contains(where: { $0.name == printer.name }) { continue }
            group.enter()
            resolveEndpoint(name: printer.name) { host, port in
                if let host, let port {
                    lock.lock()
                    resolved.append(
                        Printer(name: printer.name, host: host, port: port, resource: "/ipp/print")
                    )
                    lock.unlock()
                }
                group.leave()
            }
        }
        _ = group.wait(timeout: .now() + 3)
        return resolved.sorted { $0.name < $1.name }
    }

    private static func resolveEndpoint(
        name: String,
        completion: @escaping (String?, Int?) -> Void
    ) {
        let connection = NWConnection(
            to: NWEndpoint.service(
                name: name, type: "_ipp._tcp", domain: "local", interface: nil
            ),
            using: NWParameters.tcp
        )
        let once = Once()
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                once.run {
                    if let endpoint = connection.currentPath?.remoteEndpoint,
                       case let .hostPort(host, port) = endpoint {
                        completion("\(host)", Int(port.rawValue))
                    } else {
                        completion(nil, nil)
                    }
                    connection.cancel()
                }
            case .failed:
                once.run {
                    completion(nil, nil)
                    connection.cancel()
                }
            default:
                break
            }
        }
        connection.start(queue: .global())
        DispatchQueue.global().asyncAfter(deadline: .now() + 3) {
            once.run { connection.cancel() }
        }
    }
}

final class Once {
    private let lock = NSLock()
    private var done = false
    func run(_ block: () -> Void) {
        lock.lock()
        let shouldRun = !done
        done = true
        lock.unlock()
        if shouldRun { block() }
    }
}
