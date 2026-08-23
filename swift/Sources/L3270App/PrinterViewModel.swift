import Foundation
import L3270Core
import UserNotifications

@MainActor
public final class PrinterViewModel: ObservableObject {
    @Published public var printer: Discovery.Printer?
    @Published public var status: PrinterStatus?
    @Published public var lastUpdated: Date?
    @Published public var errorMessage: String?
    @Published public var showSetup = false
    @Published public var showSettings = false
    @Published public var passwordInput = ""

    public let printCoordinator = PrintCoordinator()

    @Published public var pollIntervalSeconds: Int {
        didSet { UserDefaults.standard.set(pollIntervalSeconds, forKey: "pollInterval") }
    }
    @Published public var defaultMedia: String {
        didSet { UserDefaults.standard.set(defaultMedia, forKey: "defaultMedia") }
    }
    @Published public var defaultMono: Bool {
        didSet { UserDefaults.standard.set(defaultMono, forKey: "defaultMono") }
    }

    private var pollTask: Task<Void, Never>?
    private var lowInkNotified: Set<String> = []

    public init() {
        pollIntervalSeconds = UserDefaults.standard.object(forKey: "pollInterval") as? Int ?? 60
        defaultMedia = UserDefaults.standard.string(forKey: "defaultMedia") ?? "a4"
        defaultMono = UserDefaults.standard.bool(forKey: "defaultMono")
        if let savedHost = UserDefaults.standard.string(forKey: "savedPrinterHost") {
            printer = Discovery.Printer(
                name: UserDefaults.standard.string(forKey: "savedPrinterName") ?? "L3270",
                host: savedHost,
                port: 631,
                resource: "/ipp/print"
            )
        }
    }

    public func start() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                let interval = self?.pollIntervalSeconds ?? 60
                try? await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
            }
        }
    }

    public func discoverPrinter() {
        let found = Discovery.findPrinters(matching: "L3270")
        guard let first = found.first else {
            errorMessage = "No L3270 printer found on the network."
            return
        }
        printer = first
        UserDefaults.standard.set(first.host, forKey: "savedPrinterHost")
        UserDefaults.standard.set(first.name, forKey: "savedPrinterName")
        if KeychainStore.loadPassword(forPrinter: first.host) == nil {
            showSetup = true
        }
    }

    public func savePassword() {
        guard let printer else { return }
        do {
            try KeychainStore.savePassword(passwordInput, forPrinter: printer.host)
            passwordInput = ""
            showSetup = false
            Task { await refresh() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func refresh() async {
        guard let printer else {
            discoverPrinter()
            return
        }
        guard let password = KeychainStore.loadPassword(forPrinter: printer.host) else {
            showSetup = true
            return
        }
        do {
            let client = RemoteUIClient(host: webHost(for: printer))
            client.setPassword(password)
            let fetched = try client.fetchStatus()
            status = fetched
            lastUpdated = Date()
            errorMessage = nil
            checkLowInk(fetched.ink)
        } catch let error as RemoteUIError {
            errorMessage = error.description
            if case .authFailed = error { showSetup = true }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func webHost(for printer: Discovery.Printer) -> String {
        if printer.host.contains(".") && !printer.host.contains(":") {
            return printer.host
        }
        return printer.name.replacingOccurrences(of: " ", with: "") + ".local"
    }

    private func checkLowInk(_ ink: InkLevels) {
        let tanks: [(String, Int?)] = [
            ("Black", ink.black), ("Cyan", ink.cyan),
            ("Magenta", ink.magenta), ("Yellow", ink.yellow),
        ]
        for (name, level) in tanks {
            guard let level, level < 15 else { continue }
            let key = "\(name)-low"
            guard !lowInkNotified.contains(key) else { continue }
            lowInkNotified.insert(key)
            NotificationManager.notifyLowInk(tank: name, level: level)
        }
        for (name, level) in tanks {
            if let level, level >= 20 {
                lowInkNotified.remove("\(name)-low")
            }
        }
    }
}

enum NotificationManager {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    static func notifyLowInk(tank: String, level: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Low ink: \(tank)"
        content.body = "\(tank) is at \(level)%. Refill soon."
        let request = UNNotificationRequest(
            identifier: "low-ink-\(tank)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }
}
