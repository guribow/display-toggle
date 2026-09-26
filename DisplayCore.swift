// 外付けモニターを macOS から切り離す / 再接続する共通処理。
// macOS の非公開API (CGSConfigureDisplayEnabled) を使う。
// CLI (cli/main.swift) とメニューバーアプリ (app/main.swift) の両方から使う。
import AppKit
import CoreGraphics
import IOKit

@_silgen_name("CGSConfigureDisplayEnabled")
func CGSConfigureDisplayEnabled(_ config: CGDisplayConfigRef, _ display: CGDirectDisplayID, _ enabled: Bool) -> CGError

struct Display {
    let id: CGDirectDisplayID
    let baseName: String        // モニターが名乗る名前
    var name: String            // 表示名。同じ名前のモニターが複数あるときは「 (1)」「 (2)」を付ける
    let isMain: Bool
    let connected: Bool         // 使っている（切り離していない）
    var cableAttached = true    // ケーブルがつながっている（切り離し中に抜かれると false）
    let vendor: UInt32, model: UInt32, serial: UInt32   // モニターが名乗るメーカー・製品・シリアル番号

    /// ケーブルが抜けていて戻せない、切り離し中の記録
    var unplugged: Bool { !connected && !cableAttached }
}

/// 切り離し中のモニターの記録（切り離すと macOS の一覧から消えるので、自分で覚えておく）
struct OffRecord: Codable {
    let id: UInt32
    let name: String
    var vendor: UInt32 = 0, model: UInt32 = 0, serial: UInt32 = 0
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
    "使い方: displayctl list | off <名前> | on [名前] | toggle <名前> | forget <名前>":
        "Usage: displayctl list | off <name> | on [name] | toggle <name> | forget <name>",
    "ケーブルが抜けているため戻せない: %@": "Can't reconnect %@: the cable is unplugged.",
    "複数あります。番号か (1) (2) を付けて指定してください: %@": "More than one match. Use the number or (1), (2): %@",
    "%@（ケーブル未接続）": "%@ (unplugged)",
    "(ケーブル未接続)": "(unplugged)",
    "ケーブルが抜けています。クリックで一覧から消す（つなぎ直すと自動で元に戻る）":
        "The cable is unplugged. Click to remove from the list. (It comes back when you plug it in.)",
    "一覧から消した: %@": "Removed from the list: %@",
    "ケーブル未接続の記録に見つからない: %@": "Not found among unplugged displays: %@",
]

enum DisplayError: LocalizedError {
    case notFound(String), mainDisplay(String), lastDisplay, failed(String), unplugged(String), ambiguous([String])
    var errorDescription: String? {
        switch self {
        case .notFound(let q): return L("見つからない: %@", q)
        case .mainDisplay(let n): return L("メインモニター（%@）は切り離せない", n)
        case .lastDisplay: return L("モニターが1台しかないため切り離さない")
        case .failed(let n): return L("操作に失敗: %@", n)
        case .unplugged(let n): return L("ケーブルが抜けているため戻せない: %@", n)
        case .ambiguous(let ns): return L("複数あります。番号か (1) (2) を付けて指定してください: %@", ns.joined(separator: ", "))
        }
    }
}

enum DisplayCore {
    static let stateDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/displayctl")
    static let stateFile = stateDir.appendingPathComponent("disabled.json")  // [OffRecord]

    /// 切り離し中の記録。古い形式（{名前: 番号}）なら読み替える
    static func loadState() -> [OffRecord] {
        guard let d = try? Data(contentsOf: stateFile) else { return [] }
        if let list = try? JSONDecoder().decode([OffRecord].self, from: d) { return list }
        if let old = try? JSONDecoder().decode([String: UInt32].self, from: d) {
            return old.map { OffRecord(id: $0.value, name: $0.key) }
        }
        return []
    }

    static func saveState(_ list: [OffRecord]) {
        try? FileManager.default.createDirectory(at: stateDir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(list).write(to: stateFile)
    }

    typealias Monitor = (vendor: UInt32, model: UInt32, serial: UInt32, name: String)

    /// ケーブルでつながっているモニター（切り離し中も含む）と、どこから取ったか。
    /// - Apple シリコン：IORegistry の IOMobileFramebufferShim の DisplayAttributes
    /// - Intel：IORegistry の IODisplayConnect の DisplayVendorID など
    /// どちらも取れないときは nil（ケーブルの有無は分からないものとして扱う）
    static func attachedMonitorsWithSource() -> (monitors: [Monitor], source: String)? {
        let shim = services("IOMobileFramebufferShim").compactMap { entry -> Monitor? in
            guard let attrs = property(entry, "DisplayAttributes") as? [String: Any],
                  let p = attrs["ProductAttributes"] as? [String: Any] else { return nil }
            return (vendor: (p["LegacyManufacturerID"] as? NSNumber)?.uint32Value ?? 0,
                    model: (p["ProductID"] as? NSNumber)?.uint32Value ?? 0,
                    serial: (p["SerialNumber"] as? NSNumber)?.uint32Value ?? 0,
                    name: p["ProductName"] as? String ?? "")
        }
        if !shim.isEmpty { return (shim, "IOMobileFramebufferShim") }

        let connect = services("IODisplayConnect").compactMap { entry -> Monitor? in
            guard let vendor = property(entry, "DisplayVendorID") as? NSNumber,
                  let model = property(entry, "DisplayProductID") as? NSNumber else { return nil }
            let names = property(entry, "DisplayProductName") as? [String: String]
            return (vendor: vendor.uint32Value, model: model.uint32Value,
                    serial: (property(entry, "DisplaySerialNumber") as? NSNumber)?.uint32Value ?? 0,
                    name: names?["en_US"] ?? names?.values.first ?? "")
        }
        if !connect.isEmpty { return (connect, "IODisplayConnect") }
        return nil
    }

    static func attachedMonitors() -> [Monitor]? { attachedMonitorsWithSource()?.monitors }

    private static func services(_ className: String) -> [io_object_t] {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iter) == KERN_SUCCESS
        else { return [] }
        defer { IOObjectRelease(iter) }
        var result: [io_object_t] = []
        while case let entry = IOIteratorNext(iter), entry != 0 { result.append(entry) }
        return result
    }

    private static func property(_ entry: io_object_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// 調査用（displayctl debug）：macOS から見えるモニター、ケーブルでつながっているモニター、記録を並べる
    static func debugReport() -> String {
        var lines: [String] = []
        let arch: String = {
            #if arch(arm64)
            return "arm64"
            #else
            return "x86_64"
            #endif
        }()
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        lines.append("DisplayToggle debug  (\(arch), macOS \(os))")
        lines.append("")
        lines.append("[active displays: NSScreen / CGDisplay]")
        for s in NSScreen.screens {
            guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let id = CGDirectDisplayID(n.uint32Value)
            lines.append("  id=\(id) name=\(s.localizedName) vendor=\(CGDisplayVendorNumber(id)) model=\(CGDisplayModelNumber(id)) serial=\(CGDisplaySerialNumber(id)) main=\(id == CGMainDisplayID())")
        }
        lines.append("")
        if let r = attachedMonitorsWithSource() {
            lines.append("[attached monitors: \(r.source)]")
            for m in r.monitors { lines.append("  name=\(m.name) vendor=\(m.vendor) model=\(m.model) serial=\(m.serial)") }
        } else {
            lines.append("[attached monitors: not available]")
        }
        lines.append("")
        lines.append("[records: \(stateFile.path)]")
        for r in loadState() { lines.append("  id=\(r.id) name=\(r.name) vendor=\(r.vendor) model=\(r.model) serial=\(r.serial)") }
        lines.append("")
        lines.append("[list]")
        for d in all() {
            lines.append("  id=\(d.id) name=\(d.name) connected=\(d.connected) cableAttached=\(d.cableAttached) main=\(d.isMain)")
        }
        return lines.joined(separator: "\n")
    }

    /// 使っているモニターと、切り離し中として記録しているモニター
    static func all() -> [Display] {
        let main = CGMainDisplayID()
        let active: [Display] = NSScreen.screens.compactMap { s in
            guard let n = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return nil }
            let id = CGDirectDisplayID(n.uint32Value)
            return Display(id: id, baseName: s.localizedName, name: s.localizedName, isMain: id == main, connected: true,
                           vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id))
        }
        let activeIDs = Set(active.map(\.id))

        // 使い始めたモニターの記録は消す（macOS 側で戻った、つなぎ直して戻ったなど）
        var state = loadState()
        if state.contains(where: { activeIDs.contains($0.id) }) {
            state.removeAll { activeIDs.contains($0.id) }
            saveState(state)
        }

        // ケーブルでつながっているモニターから、使っているものを除くと、切り離し中のものが残る
        var pool = attachedMonitors()
        for d in active {
            if let i = pool?.firstIndex(where: { $0.vendor == d.vendor && $0.model == d.model && $0.serial == d.serial }) {
                pool?.remove(at: i)
            }
        }
        let off: [Display] = state.map { r in
            var attached = true
            if pool != nil {
                // 番号が分かれば番号で、古い記録で分からなければ名前で探す
                let i = r.vendor != 0
                    ? pool!.firstIndex { $0.vendor == r.vendor && $0.model == r.model && $0.serial == r.serial }
                    : pool!.firstIndex { $0.name == r.name }
                if let i { pool!.remove(at: i) } else { attached = false }
            }
            return Display(id: r.id, baseName: r.name, name: r.name, isMain: false, connected: false,
                           cableAttached: attached, vendor: r.vendor, model: r.model, serial: r.serial)
        }

        // 同じ名前が複数あれば、番号の小さい順に「 (1)」「 (2)」を付ける
        var list = active + off
        let counts = Dictionary(grouping: list, by: \.baseName).mapValues(\.count)
        for (base, n) in counts where n > 1 {
            let ids = list.filter { $0.baseName == base }.map(\.id).sorted()
            for i in list.indices where list[i].baseName == base {
                list[i].name = "\(base) (\(ids.firstIndex(of: list[i].id)! + 1))"
            }
        }
        return list.filter(\.connected) + list.filter { !$0.connected }.sorted { $0.name < $1.name }
    }

    /// 名前で探す。一覧の番号、表示名（「 (2)」付きも可）、名前の一部の順に試す。
    /// 名前の一部が複数に当てはまるときは、どれか分からないのでエラーにする
    static func find(_ query: String, in list: [Display] = all()) throws -> Display? {
        if let n = UInt32(query), let d = list.first(where: { $0.id == n }) { return d }
        if let d = list.first(where: { $0.name.caseInsensitiveCompare(query) == .orderedSame }) { return d }
        let hits = list.filter { $0.name.localizedCaseInsensitiveContains(query) }
        if hits.count > 1 { throw DisplayError.ambiguous(hits.map(\.name)) }
        return hits.first
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
        var st = loadState()
        st.removeAll { $0.id == d.id }
        st.append(OffRecord(id: d.id, name: d.baseName, vendor: d.vendor, model: d.model, serial: d.serial))
        saveState(st)
        guard setEnabled(d.id, false) else {
            st.removeAll { $0.id == d.id }; saveState(st)
            throw DisplayError.failed(d.name)
        }
    }

    static func reconnect(_ d: Display) throws {
        if d.unplugged { throw DisplayError.unplugged(d.name) }
        guard setEnabled(d.id, true) else { throw DisplayError.failed(d.name) }
        var st = loadState(); st.removeAll { $0.id == d.id }; saveState(st)
    }

    static func toggle(_ d: Display) throws {
        d.connected ? try disconnect(d) : try reconnect(d)
    }

    /// ケーブルが抜けたモニターの記録を一覧から消す（つなぎ直せば、macOS が改めて認識する）
    static func forget(_ d: Display) {
        var st = loadState(); st.removeAll { $0.id == d.id }; saveState(st)
    }

    /// 切り離し中をすべて戻す（ケーブルが抜けたものは除く）。戻せたモニター名を返す
    @discardableResult
    static func reconnectAll() -> [String] {
        all().filter { !$0.connected && !$0.unplugged }.compactMap { d in
            (try? reconnect(d)) != nil ? d.name : nil
        }
    }
}
