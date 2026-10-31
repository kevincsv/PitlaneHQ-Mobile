import Foundation
import OSLog
import UIKit

/// The file a crash signal writes to (opened when the app starts, so the handler only writes).
private var crashSigFD: Int32 = -1

/// What breaks on the phone, for the admin page's Health (the server's reports.js): a crash is written as it happens and
/// sent (POST /community/crash) the next time the app opens; and the app's own log for "Send the app's logs" in the
/// support chat (POST /community/support/logs).
enum Reports {
    private static var dir: URL { FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0] }
    private static var crashURL: URL { dir.appendingPathComponent("crash.txt") }
    private static var signalURL: URL { dir.appendingPathComponent("crash-signal.txt") }

    /// The crash of the last run, once (the files go). Read before install(), which starts the signal's file again.
    static func take() -> [String: Any]? {
        var out: [String: Any]?
        if let d = try? Data(contentsOf: crashURL), let j = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { out = j }
        if out == nil, let s = try? String(contentsOf: signalURL, encoding: .utf8), !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let lines = s.split(separator: "\n", maxSplits: 1).map(String.init)
            out = ["where": "signal", "msg": lines.first ?? "signal", "stack": String((lines.count > 1 ? lines[1] : "").prefix(8000))]
        }
        try? FileManager.default.removeItem(at: crashURL)
        try? FileManager.default.removeItem(at: signalURL)
        return out
    }

    /// Once, when the app starts: an Objective-C exception or a crash signal is written down before the app closes.
    static func install() {
        NSSetUncaughtExceptionHandler { e in
            let j: [String: Any] = ["where": "exception", "msg": String((e.name.rawValue + ": " + (e.reason ?? "")).prefix(500)),
                                    "stack": String(e.callStackSymbols.joined(separator: "\n").prefix(8000))]
            if let d = try? JSONSerialization.data(withJSONObject: j) { try? d.write(to: Reports.crashURL) }
        }
        crashSigFD = open(signalURL.path, O_WRONLY | O_CREAT | O_TRUNC, 0o600)
        let handler: @convention(c) (Int32) -> Void = { sig in
            if crashSigFD >= 0 {
                let m = "signal \(sig)\n" + Thread.callStackSymbols.joined(separator: " | ")
                m.utf8CString.withUnsafeBufferPointer { p in _ = write(crashSigFD, p.baseAddress, p.count - 1) }
                close(crashSigFD)
                crashSigFD = -1
            }
            signal(sig, SIG_DFL)
            raise(sig)
        }
        for s in [SIGABRT, SIGSEGV, SIGBUS, SIGILL, SIGTRAP, SIGFPE] { signal(s, handler) }
    }

    /// The end of this app's own log (this run's), with a line naming the app and the phone.
    static func log() -> String {
        let v = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let head = "Pitlane HQ \(v) · iOS \(UIDevice.current.systemVersion) · \(UIDevice.current.model)\n\n"
        var body = ""
        if let store = try? OSLogStore(scope: .currentProcessIdentifier),
           let entries = try? store.getEntries(at: store.position(date: Date().addingTimeInterval(-6 * 3600))) {
            let f = DateFormatter(); f.dateFormat = "HH:mm:ss.SSS"
            let lines = entries.compactMap { $0 as? OSLogEntryLog }.suffix(800).map { "\(f.string(from: $0.date)) \($0.category) \($0.composedMessage)" }
            body = String(lines.joined(separator: "\n").suffix(400 * 1024))
        }
        return head + (body.isEmpty ? "(no log)" : body)
    }
}

/// "Share my lap": the same 1200×630 picture as the web's (lapCardCanvas in index.html), the dark card with the amber
/// edge, Pitlane HQ and the game, the track, the car, the time, "P3 of 42 on the leaderboard" and pitlanehq.app.
enum ShareCard {
    static func image(track: String, car: String, time: Double, pos: Int, of: Int, game: String) -> UIImage {
        let w: CGFloat = 1200, h: CGFloat = 630
        let fmt = UIGraphicsImageRendererFormat(); fmt.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: w, height: h), format: fmt).image { ctx in
            let c = ctx.cgContext
            UIColor(red: 0x0D / 255, green: 0x11 / 255, blue: 0x16 / 255, alpha: 1).setFill(); c.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let card = UIBezierPath(roundedRect: CGRect(x: 40, y: 40, width: w - 80, height: h - 80), cornerRadius: 24)
            UIColor(red: 0x16 / 255, green: 0x1C / 255, blue: 0x24 / 255, alpha: 1).setFill(); card.fill()
            UIColor(red: 0x26 / 255, green: 0x31 / 255, blue: 0x40 / 255, alpha: 1).setStroke(); card.lineWidth = 2; card.stroke()
            let amber = UIColor(red: 1, green: 0xB0 / 255, blue: 0x2E / 255, alpha: 1)
            amber.setFill(); c.fill(CGRect(x: 40, y: 92, width: 8, height: h - 184))
            func text(_ s: String, _ x: CGFloat, _ base: CGFloat, _ size: CGFloat, _ color: UIColor, mono: Bool = false, right: Bool = false, max: CGFloat = 0) {
                var sz = size
                func attrs() -> [NSAttributedString.Key: Any] {
                    [.font: mono ? UIFont.monospacedSystemFont(ofSize: sz, weight: .bold) : UIFont.systemFont(ofSize: sz, weight: .bold), .foregroundColor: color]
                }
                var a = NSAttributedString(string: s, attributes: attrs())
                while max > 0 && a.size().width > max && sz > 20 { sz -= 2; a = NSAttributedString(string: s, attributes: attrs()) }
                let f = attrs()[.font] as! UIFont
                a.draw(at: CGPoint(x: right ? x - a.size().width : x, y: base - f.ascender))
            }
            text("PITLANE HQ", 88, 100, 30, amber)
            text(game == "lmu" ? "Le Mans Ultimate" : "iRacing", w - 88, 100, 26, UIColor(white: 0.56, alpha: 1), right: true)
            text(track.uppercased(), 88, 200, 76, UIColor(red: 0xE7 / 255, green: 0xEB / 255, blue: 0xF1 / 255, alpha: 1), max: w - 176)
            text(car, 88, 256, 40, UIColor(red: 0xAA / 255, green: 0xB4 / 255, blue: 0xC3 / 255, alpha: 1), max: w - 176)
            text(lapTime(time), 82, 440, 150, amber, mono: true)
            let pl = NSAttributedString(string: "P\(pos)", attributes: [.font: UIFont.systemFont(ofSize: 54, weight: .bold)])
            text("P\(pos)", 88, 524, 54, UIColor(red: 0xE7 / 255, green: 0xEB / 255, blue: 0xF1 / 255, alpha: 1))
            text(t("share_card_of", of), 88 + pl.size().width + 18, 522, 34, UIColor(white: 0.56, alpha: 1))
            text("pitlanehq.app", w - 88, 524, 28, UIColor(white: 0.45, alpha: 1), right: true)
        }
    }

    /// The phone's share sheet with the picture and a line of text.
    static func share(track: String, car: String, time: Double, pos: Int, of: Int, game: String) {
        let img = image(track: track, car: car, time: time, pos: pos, of: of, game: game)
        guard let root = UIApplication.shared.connectedScenes.compactMap({ ($0 as? UIWindowScene)?.keyWindow }).first?.rootViewController else { return }
        var top = root
        while let p = top.presentedViewController { top = p }
        let vc = UIActivityViewController(activityItems: [img, "\(track) · \(car) · \(lapTime(time)) · P\(pos) · pitlanehq.app"], applicationActivities: nil)
        vc.popoverPresentationController?.sourceView = top.view
        vc.popoverPresentationController?.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.midY, width: 0, height: 0)
        top.present(vc, animated: true)
    }
}
