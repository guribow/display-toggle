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

/// 画面に出す文字列。日本語をキーにし、Mac の言語が日本語でなければ英語にする。
/// アプリとコマンド（displayctl）の両方で使うので、翻訳ファイルではなくここに表で持つ
func L(_ ja: String) -> String {
    guard !(Locale.preferredLanguages.first ?? "ja").hasPrefix("ja") else { return ja }
    return english[ja] ?? ja
}

func L(_ ja: String, _ args: CVarArg...) -> String { String(format: L(ja), arguments: args) }

private let english: [String: String] = [
    "見つからない: %@": "Not found: %@",
    "メインモニター（%@）は切り離せない": "Can't disconnect the main display (%@).",
    "モニターが1台しかないため切り離さない": "Only one display is connected, so it stays on.",
    "操作に失敗: %@": "Failed: %@",
    "DisplayToggle について": "About DisplayToggle",
    "外付けモニターなし": "No external displays",
    "クリックで切り離す": "Click to disconnect",
    "クリックで戻す": "Click to reconnect",
    "%@（メイン）": "%@ (Main)",
    "ログイン時に起動": "Open at Login",
    "終了（モニターを全部戻す）": "Quit (reconnect all displays)",
    "(メイン)": "(main)",
    "(切り離し中)": "(disconnected)",
    "接続中のモニターに見つからない: %@": "Not found among connected displays: %@",
    "切り離した: %@": "Disconnected: %@",
    "切り離し中のモニターがない": "No disconnected displays",
    "再接続した: %@": "Reconnected: %@",
    "切り離し中のモニターに見つからない: %@": "Not found among disconnected displays: %@",
    "使い方: displayctl list | off <名前> | on [名前] | toggle <名前>":
        "Usage: displayctl list | off <name> | on [name] | toggle <name>",
]

enum DisplayError: LocalizedError {
    case notFound(String), mainDisplay(String), lastDisplay, failed(String)
    var errorDescription: String? {
        switch self {
        case .notFound(let q): return L("見つからない: %@", q)
        case .mainDisplay(let n): return L("メインモニター（%@）は切り離せない", n)
        case .lastDisplay: return L("モニターが1台しかないため切り離さない")
        case .failed(let n): return L("操作に失敗: %@", n)
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
