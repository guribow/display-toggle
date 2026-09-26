// DisplayToggle: メニューバーから外付けモニターを切り離す / 戻すアプリ
import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private let menu = NSMenu()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu.delegate = self
        statusItem.menu = menu
        updateIcon()
        // ケーブルの抜き差しなどでモニター構成が変わったらアイコンを更新
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // 見えないモニターを残さないよう、終了時は全部戻す
        DisplayCore.reconnectAll()
    }

    @objc private func screensChanged() { updateIcon() }

    private func updateIcon() {
        let anyOff = DisplayCore.all().contains { !$0.connected && !$0.unplugged }
        let symbol = anyOff ? "display" : "display.2"
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "DisplayToggle")
        image?.isTemplate = true
        statusItem.button?.image = image
    }

    // メニューを開くたびに作り直す
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let about = NSMenuItem(title: L("DisplayToggle について"), action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())
        let externals = DisplayCore.all().filter { !$0.isMain }
        if externals.isEmpty {
            menu.addItem(disabledItem(L("外付けモニターなし")))
        }
        for d in externals {
            let item: NSMenuItem
            if d.unplugged {
                // 切り離し中にケーブルが抜けた：戻せないので、クリックで一覧から消せるようにする
                item = NSMenuItem(title: L("%@（ケーブル未接続）", d.name), action: #selector(forgetDisplay(_:)), keyEquivalent: "")
                item.toolTip = L("ケーブルが抜けています。クリックで一覧から消す（つなぎ直すと自動で元に戻る）")
            } else {
                item = NSMenuItem(title: d.name, action: #selector(toggleDisplay(_:)), keyEquivalent: "")
                item.state = d.connected ? .on : .off
                item.toolTip = d.connected ? L("クリックで切り離す") : L("クリックで戻す")
            }
            item.target = self
            item.representedObject = d.id
            menu.addItem(item)
        }
        if let main = DisplayCore.all().first(where: \.isMain) {
            menu.addItem(disabledItem(L("%@（メイン）", main.name)))
        }

        menu.addItem(.separator())
        let login = NSMenuItem(title: L("ログイン時に起動"), action: #selector(toggleLoginItem), keyEquivalent: "")
        login.target = self
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(login)
        let quit = NSMenuItem(title: L("終了（モニターを全部戻す）"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    @objc private func toggleDisplay(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CGDirectDisplayID,
              let d = DisplayCore.all().first(where: { $0.id == id }) else { return }
        do { try DisplayCore.toggle(d) } catch { showError(error) }
        updateIcon()
    }

    @objc private func forgetDisplay(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? CGDirectDisplayID,
              let d = DisplayCore.all().first(where: { $0.id == id }) else { return }
        DisplayCore.forget(d)
        updateIcon()
    }

    /// macOS 標準の「このアプリについて」（アイコン・名前・バージョン・著作権は Info.plist から）
    @objc private func showAbout() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.version: ""])   // ビルド番号の「(…)」は出さない
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled { try service.unregister() } else { try service.register() }
        } catch { showError(error) }
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "DisplayToggle"
        alert.informativeText = error.localizedDescription
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
