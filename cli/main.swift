// displayctl: DisplayCore のコマンドライン版
//   displayctl list | off <名前の一部> | on [名前の一部] | toggle <名前の一部>
import Foundation

func fail(_ msg: String) -> Never {
    FileHandle.standardError.write((msg + "\n").data(using: .utf8)!)
    exit(1)
}

func run(_ body: () throws -> Void) {
    do { try body() } catch { fail(error.localizedDescription) }
}

let args = Array(CommandLine.arguments.dropFirst())
switch (args.first, args.dropFirst().first) {
case ("list", _):
    for d in DisplayCore.all() {
        print("\(d.id)\t\(d.name)\(d.isMain ? "\t(メイン)" : "")\(d.connected ? "" : "\t(切り離し中)")")
    }
case ("off", let q?):
    guard let d = DisplayCore.find(q), d.connected else { fail("接続中のモニターに見つからない: \(q)") }
    run { try DisplayCore.disconnect(d); print("切り離した: \(d.name)") }
case ("on", nil):
    let names = DisplayCore.reconnectAll()
    if names.isEmpty { fail("切り離し中のモニターがない") }
    names.forEach { print("再接続した: \($0)") }
case ("on", let q?):
    guard let d = DisplayCore.find(q), !d.connected else { fail("切り離し中のモニターに見つからない: \(q)") }
    run { try DisplayCore.reconnect(d); print("再接続した: \(d.name)") }
case ("toggle", let q?):
    guard let d = DisplayCore.find(q) else { fail("見つからない: \(q)") }
    run { try DisplayCore.toggle(d); print("\(d.connected ? "切り離した" : "再接続した"): \(d.name)") }
default:
    print("使い方: displayctl list | off <名前> | on [名前] | toggle <名前>")
    exit(2)
}
