// displayctl: DisplayCore のコマンドライン版
//   displayctl list | off <名前> | on [名前] | toggle <名前> | forget <名前>
//   名前は、一覧の番号、「 (2)」付きの名前、名前の一部のどれでもよい
import Foundation

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func run(_ body: () throws -> Void) {
    do { try body() } catch { fail(error.localizedDescription) }
}

/// 名前（一覧の番号、「 (2)」付きの名前、名前の一部）で探す。複数に当てはまればエラーで終わる
func pick(_ q: String, from list: [Display]) -> Display? {
    do { return try DisplayCore.find(q, in: list) } catch { fail(error.localizedDescription) }
}

let args = Array(CommandLine.arguments.dropFirst())
switch (args.first, args.dropFirst().first) {
case ("list", _):
    for d in DisplayCore.all() {
        let state = d.isMain ? "\t" + L("(メイン)") : d.unplugged ? "\t" + L("(ケーブル未接続)") : d.connected ? "" : "\t" + L("(切り離し中)")
        print("\(d.id)\t\(d.name)\(state)")
    }
case ("off", let q?):
    guard let d = pick(q, from: DisplayCore.all().filter(\.connected)) else { fail(L("接続中のモニターに見つからない: %@", q)) }
    run { try DisplayCore.disconnect(d); print(L("切り離した: %@", d.name)) }
case ("on", nil):
    let names = DisplayCore.reconnectAll()
    if names.isEmpty { fail(L("切り離し中のモニターがない")) }
    names.forEach { print(L("再接続した: %@", $0)) }
case ("on", let q?):
    guard let d = pick(q, from: DisplayCore.all().filter { !$0.connected }) else { fail(L("切り離し中のモニターに見つからない: %@", q)) }
    run { try DisplayCore.reconnect(d); print(L("再接続した: %@", d.name)) }
case ("toggle", let q?):
    guard let d = pick(q, from: DisplayCore.all()) else { fail(L("見つからない: %@", q)) }
    run { try DisplayCore.toggle(d); print(L(d.connected ? "切り離した: %@" : "再接続した: %@", d.name)) }
case ("forget", let q?):
    guard let d = pick(q, from: DisplayCore.all().filter(\.unplugged)) else { fail(L("ケーブル未接続の記録に見つからない: %@", q)) }
    DisplayCore.forget(d)
    print(L("一覧から消した: %@", d.name))
case ("debug", _):   // 調査用（英語のみ）
    print(DisplayCore.debugReport())
default:
    print(L("使い方: displayctl list | off <名前> | on [名前] | toggle <名前> | forget <名前>"))
    exit(2)
}
