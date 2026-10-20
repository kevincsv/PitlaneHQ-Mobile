import Network
import SwiftUI

@main
struct PitlaneHQApp: App {
    @StateObject private var account = Account()
    @StateObject private var net = NetMonitor()
    @StateObject private var i18n = I18n.shared
    @StateObject private var updates = Updates()
    @StateObject private var inbox = Inbox()
    @StateObject private var live = Live()
    @Environment(\.scenePhase) private var phase

    var body: some Scene {
        WindowGroup {
            Group {
                if account.signedIn { MainView() } else { LoginView() }
            }
            .id(i18n.lang)
            .environmentObject(account)
            .environmentObject(net)
            .environmentObject(i18n)
            .environmentObject(updates)
            .environmentObject(inbox)
            .environmentObject(live)
            .task { await updates.check() }
            .task { await inbox.load() }
            // every time the app comes to the screen, the account syncs by itself
            .task { await account.syncIfDue() }
            // and the link to the account's live room stays open (presence only): the moment another device
            // uploads the account, the server says so and this phone reads it again
            .task {
                live.onSync = { v in account.nudged(v) }
                if account.signedIn { live.startPresence(token: account.token, key: account.dataKey) }
            }
            .onChange(of: account.signedIn) { on in
                if on { live.startPresence(token: account.token, key: account.dataKey) } else { live.stop() }
            }
            .onChange(of: phase) { p in
                if p == .active {
                    Task { await account.syncIfDue() }
                    if account.signedIn { live.resume(token: account.token, key: account.dataKey, demo: account.demo) }
                } else {
                    live.stop()
                }
            }
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
        }
    }
}

/// Whether the phone has a connection, to show the offline banner and reload when it comes back.
@MainActor
final class NetMonitor: ObservableObject {
    @Published var online = true
    @Published var cameBack = 0
    private let monitor = NWPathMonitor()

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let on = path.status == .satisfied
            Task { @MainActor in
                guard let self else { return }
                if on && !self.online { self.cameBack += 1 }
                self.online = on
            }
        }
        monitor.start(queue: DispatchQueue(label: "net"))
    }
}

/// A newer Pitlane HQ for this phone on the server (the same build the downloads page points to).
@MainActor
final class Updates: ObservableObject {
    @Published var version: String?
    let page = URL(string: "https://pitlanehq.app/downloads")!

    static func parts(_ v: String) -> [Int] {
        let core = v.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "v", with: "").split(separator: "-").first.map(String.init) ?? ""
        return core.split(separator: ".").map { Int($0) ?? 0 }
    }

    static func newer(_ latest: String, than current: String) -> Bool {
        let a = parts(latest), b = parts(current)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    func check() async {
        // the newest build on the server (pitlanehq.app/dl/phones.json), the same one the downloads page points to
        let r = URLRequest(url: URL(string: "https://pitlanehq.app/dl/phones.json")!, timeoutInterval: 15)
        guard let res = try? await URLSession.shared.data(for: r),
              let j = try? JSONSerialization.jsonObject(with: res.0) as? [String: Any],
              let v0 = j["version"] as? String else { return }
        let v = v0.replacingOccurrences(of: "-beta", with: "").replacingOccurrences(of: "v", with: "")
        let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        // another version on the server is the one to have (the numbering started again at 0.4.1)
        if !v.isEmpty && Updates.parts(v) != Updates.parts(current) { version = v }
    }
}

/// One piece of news of the app (web/dist/app-news.json on the server, edited by hand).
struct AppNews: Identifiable {
    let id: String, date: String, title: String, text: String, url: URL?, view: String?
}

/// The inbox: app news from the server and which items were dismissed on this phone.
@MainActor
final class Inbox: ObservableObject {
    @Published var news: [AppNews] = []
    @Published var goTab: Int?          // a tab an Info action asks the main view to open
    @Published var analysisTab: Int?    // the Analysis tab to open next (Home's "See all" opens My races)
    @Published var seen: Set<String> = Set(UserDefaults.standard.stringArray(forKey: "inboxSeen") ?? [])

    func mark(_ ids: [String]) {
        seen.formUnion(ids)
        UserDefaults.standard.set(Array(seen), forKey: "inboxSeen")
    }

    func load() async {
        guard let res = try? await URLSession.shared.data(from: server.appendingPathComponent("app/app-news.json")),
              let j = try? JSONSerialization.jsonObject(with: res.0) as? [String: Any], let items = j["items"] as? [[String: Any]] else { return }
        let lang = I18n.shared.lang
        func pick(_ o: Any?) -> String { let d = o as? [String: String] ?? [:]; return d[lang] ?? d["en"] ?? "" }
        news = items.prefix(10).map { it in
            AppNews(id: it["id"] as? String ?? "", date: it["date"] as? String ?? "", title: pick(it["title"]), text: pick(it["text"]), url: (it["url"] as? String).flatMap(URL.init), view: it["view"] as? String)
        }
    }
}

enum Theme {
    // the pit wall look: one dark theme with the amber accent, never switched
    static let ink = Color(red: 0x0D / 255, green: 0x11 / 255, blue: 0x16 / 255)
    static let surface = Color(red: 0x16 / 255, green: 0x1C / 255, blue: 0x24 / 255)
    static let surface2 = Color(red: 0x1E / 255, green: 0x26 / 255, blue: 0x31 / 255)
    static let line = Color(red: 0x26 / 255, green: 0x31 / 255, blue: 0x40 / 255)
    static let fg = Color(red: 0xE7 / 255, green: 0xEB / 255, blue: 0xF1 / 255)
    static let bg = Color(red: 0x0D / 255, green: 0x11 / 255, blue: 0x16 / 255)
    static let muted = Color(red: 0x9A / 255, green: 0xA6 / 255, blue: 0xB8 / 255)
    static let accent = Color(red: 1, green: 0xB0 / 255, blue: 0x2E / 255)
    static let good = Color(red: 0x4F / 255, green: 0xE0 / 255, blue: 0x9A / 255)
    static let bad = Color(red: 1, green: 0x7A / 255, blue: 0x7A / 255)
    static let purple = Color(red: 0xC9 / 255, green: 0xA4 / 255, blue: 1)
    static let blue = Color(red: 0x8C / 255, green: 0xC4 / 255, blue: 1)
    /// the floating tab bar and its chosen tab
    static let navBar = Color(red: 0x1E / 255, green: 0x26 / 255, blue: 0x31 / 255)
    static let navEdge = Color(red: 0x2E / 255, green: 0x3A / 255, blue: 0x4A / 255)
    static let navOn = Color(red: 0x2E / 255, green: 0x38 / 255, blue: 0x46 / 255)
}
