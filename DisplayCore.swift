// 外付けモニターを macOS から切り離す / 再接続する共通処理。
// macOS の非公開API (CGSConfigureDisplayEnabled) を使う。
// CLI (cli/main.swift) とメニューバーアプリ (app/main.swift) の両方から使う。
import AppKit
import CoreGraphics

@_silgen_name("CGSConfigureDisplayEnabled")
func CGSConfigureDisplayEnabled(_ config: CGDisplayConfigRef, _ display: CGDirectDisplayID, _ enabled: Bool) -> CGError

struct Display {
    let id: CGDirectDisplayID
    let name: String
    let isMain: Bool
    let connected: Bool
}

enum DisplayError: LocalizedError {
    case notFound(String), mainDisplay(String), lastDisplay, failed(String)
    var errorDescription: String? {
        switch self {
        case .notFound(let q): return "見つからない: \(q)"
        case .mainDisplay(let n): return "メインモニター（\(n)）は切り離せない"
        case .lastDisplay: return "モニターが1台しかないため切り離さない"
        case .failed(let n): return "操作に失敗: \(n)"
        }
    }
}

enum DisplayCore {
    static let stateDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/displayctl")
    static let stateFile = stateDir.appendingPathComponent("disabled.json")  // [名前: displayID]

    static func loadState() -> [String: UInt32] {
        guard let d = try? Data(contentsOf: stateFile),
              let m = try? JSONDecoder().decode([String: UInt32].self, from: d) else { return [:] }
        return m
    }

    static func saveState(_ m: [String: UInt32]) {
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(m).write(to: stateFile)
    }

    /// 接続中のモニターと、切り離し中として記録しているモニター
    static func all() -> [Display] {
        let main = CGMainDisplayID()
        let active: [Display] = NSScreen.screens.compactMap { s in
            guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(n.uint32Value)
            return Display(id: id, name: s.localizedName, isMain: id == main, connected: true)
        }
        let activeIDs = Set(active.map(\.id))
        let off = loadState()
            .filter { !activeIDs.contains($0.value) }
            .map { Display(id: $0.value, name: $0.key, isMain: false, connected: false) }
        return active + off.sorted { $0.name < $1.name }
    }

    static func find(_ query: String) -> Display? {
        all().first { $0.name.localizedCaseInsensitiveContains(query) }
    }

    private static func setEnabled(_ id: CGDirectDisplayID, _ on: Bool) -> Bool {
        var cfg: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&cfg) == .success, let cfg else { return false }
        guard CGSConfigureDisplayEnabled(cfg, id, on) == .success else {
            CGCancelDisplayConfiguration(cfg); return false
        }
        // forSession: ログアウト・再起動で元に戻る（切りっぱなしで起動しない）
        return CGCompleteDisplayConfiguration(cfg, .forSession) == .success
    }

    static func disconnect(_ d: Display) throws {
        if d.isMain { throw DisplayError.mainDisplay(d.name) }
        if all().filter(\.connected).count < 2 { throw DisplayError.lastDisplay }
        var st = loadState(); st[d.name] = d.id; saveState(st)
        guard setEnabled(d.id, false) else {
            st[d.name] = nil; saveState(st)
            throw DisplayError.failed(d.name)
        }
    }

    static func reconnect(_ d: Display) throws {
        guard setEnabled(d.id, true) else { throw DisplayError.failed(d.name) }
        var st = loadState(); st[d.name] = nil; saveState(st)
    }

    static func toggle(_ d: Display) throws {
        d.connected ? try disconnect(d) : try reconnect(d)
    }

    /// 切り離し中をすべて戻す。戻せたモニター名を返す
    @discardableResult
    static func reconnectAll() -> [String] {
        all().filter { !$0.connected }.compactMap { d in
            (try? reconnect(d)) != nil ? d.name : nil
        }
    }
}
