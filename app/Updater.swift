// アップデートの確認と入れ替え。
// GitHub の最新のリリースを調べ、新しいバージョンがあればメニューとアイコンの印で知らせる。
// 押すと zip をダウンロードしてアプリを入れ替え、起動し直す。
// 開発用の証明書で署名したアプリ（build.sh で作ったもの）は入れ替えず、リリースのページを開くだけにする
// （配る zip は ad-hoc の署名なので、入れ替えるとシステム設定で許可した内容が外れるため）。
// EdgeShelf・DisplayToggle・SMBToggle・ClipHistory で同じファイルを使う。リポジトリは Info.plist の UpdateRepo。
import AppKit
import Security

final class Updater {
    static let shared = Updater()

    struct Release {
        let version: String
        let page: URL
        let zips: [String: URL]   // zip の名前 → ダウンロード先
    }

    enum State { case idle, checking, downloading }

    private(set) var latest: Release?
    private(set) var state = State.idle
    var onChange: (() -> Void)?   // 新しいバージョンが見つかったとき（アイコンに印を付ける）

    private let repo = Bundle.main.object(forInfoDictionaryKey: "UpdateRepo") as? String ?? ""
    private let appName = Bundle.main.bundleURL.deletingPathExtension().lastPathComponent
    let current = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    private var timer: Timer?

    /// 新しいバージョンがあるか
    var available: Bool { latest.map { Self.isNewer($0.version, than: current) } ?? false }

    /// 自動で確認するか（メニューで切り替える）
    var autoCheck: Bool {
        get { UserDefaults.standard.object(forKey: "autoCheckUpdates") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "autoCheckUpdates")
            if newValue { checkIfDue() }
        }
    }

    private var lastCheck: Date {
        get { UserDefaults.standard.object(forKey: "lastUpdateCheck") as? Date ?? .distantPast }
        set { UserDefaults.standard.set(newValue, forKey: "lastUpdateCheck") }
    }

    /// 起動したら呼ぶ。少し待ってから確認し、そのあとは 1 時間ごとに、前の確認から 1 日たっていれば確認する
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) { [weak self] in self?.check(manual: false) }
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in self?.checkIfDue() }
    }

    private func checkIfDue() {
        if Date().timeIntervalSince(lastCheck) > 24 * 3600 { check(manual: false) }
    }

    // MARK: 確認

    /// manual：メニューから選んだとき。結果（最新です・失敗しました）を知らせる
    func check(manual: Bool) {
        guard state == .idle, manual || autoCheck, !repo.isEmpty,
              let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else { return }
        state = .checking
        var req = URLRequest(url: url, timeoutInterval: 30)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("\(appName)/\(current)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            let release = data.flatMap(Self.parse)
            DispatchQueue.main.async {
                guard let self else { return }
                self.state = .idle
                guard let release else {
                    if manual { self.alert(L("アップデートを確認できませんでした"), error?.localizedDescription ?? "") }
                    return
                }
                self.lastCheck = Date()
                self.latest = release
                self.onChange?()
                if manual && !self.available {
                    self.alert(L("最新のバージョンです"), String(format: L("バージョン %@ は最新のバージョンです。"), self.current))
                } else if manual {
                    self.update()
                }
            }
        }.resume()
    }

    private static func parse(_ data: Data) -> Release? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)) else { return nil }
        var zips: [String: URL] = [:]
        for a in json["assets"] as? [[String: Any]] ?? [] {
            if let name = a["name"] as? String, name.hasSuffix(".zip"),
               let u = (a["browser_download_url"] as? String).flatMap(URL.init(string:)) { zips[name] = u }
        }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version, page: page, zips: zips)
    }

    /// "0.10" は "0.9" より新しい、のように数字で比べる
    static func isNewer(_ a: String, than b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }, y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
            if p != q { return p > q }
        }
        return false
    }

    // MARK: メニュー

    /// メニューの一番上に出す項目（新しいバージョンがあるときだけ）
    func topMenuItems() -> [NSMenuItem] {
        guard available, let v = latest?.version else { return [] }
        let title = state == .downloading ? L("アップデートをダウンロード中…") : String(format: L("バージョン %@ にアップデート…"), v)
        let item = UpdaterMenuItem(title) { [weak self] in self?.update() }
        item.isEnabled = state != .downloading
        item.image = NSImage(systemSymbolName: "arrow.down.circle", accessibilityDescription: nil)
        return [item, .separator()]
    }

    /// 設定の並びに出す項目
    func settingsMenuItems() -> [NSMenuItem] {
        let check = UpdaterMenuItem(L("アップデートを確認…")) { [weak self] in self?.check(manual: true) }
        check.isEnabled = state == .idle
        let auto = UpdaterMenuItem(L("アップデートを自動で確認")) { [weak self] in
            guard let self else { return }
            self.autoCheck.toggle()
        }
        auto.state = autoCheck ? .on : .off
        return [check, auto]
    }

    /// メニューバーのアイコンの右上に、小さな丸の印を付ける（新しいバージョンがあるときだけ）
    func badge(_ image: NSImage?) -> NSImage? {
        guard available, let image else { return image }
        let size = image.size
        let out = NSImage(size: size, flipped: false) { rect in
            image.draw(in: rect)
            let d = max(5, size.width * 0.34)
            let dot = NSRect(x: size.width - d, y: size.height - d, width: d, height: d)
            NSGraphicsContext.current?.compositingOperation = .clear   // 印の周りを少し空けて、アイコンと重ならないようにする
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        out.isTemplate = true
        out.accessibilityDescription = image.accessibilityDescription
        return out
    }

    // MARK: 入れ替え

    /// 開発用の証明書で署名したアプリか（ad-hoc の署名には Team ID がない）
    private var isDeveloperBuild: Bool {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dict = info as? [String: Any] else { return false }
        return dict[kSecCodeInfoTeamIdentifier as String] != nil
    }

    func update() {
        guard let release = latest, available, state == .idle else { return }
        if isDeveloperBuild { NSWorkspace.shared.open(release.page); return }
        let lang = Bundle.main.preferredLocalizations.first == "ja" ? "ja" : "en"
        guard let zip = release.zips["\(appName)-\(release.version)-\(lang).zip"] ?? release.zips.values.first else {
            NSWorkspace.shared.open(release.page)
            return
        }
        let a = NSAlert()
        a.messageText = String(format: L("バージョン %@ にアップデートしますか？"), release.version)
        a.informativeText = L("新しいバージョンをダウンロードして入れ替え、起動し直します。")
        // アプリごとの一言（ClipHistory は、入れ替えたあとに許可を入れ直す必要がある）。Info.plist の UpdateNote
        if let note = Bundle.main.object(forInfoDictionaryKey: "UpdateNote") as? String {
            a.informativeText += "\n\n" + L(note)
        }
        a.addButton(withTitle: L("アップデート"))
        a.addButton(withTitle: L("キャンセル"))
        a.addButton(withTitle: L("変更点を見る"))
        NSApp.activate(ignoringOtherApps: true)
        switch a.runModal() {
        case .alertFirstButtonReturn: break
        case .alertThirdButtonReturn: NSWorkspace.shared.open(release.page); return
        default: return
        }
        state = .downloading
        URLSession.shared.downloadTask(with: zip) { [weak self] file, _, error in
            guard let self else { return }
            var failure = error?.localizedDescription
            var newApp: URL?
            if let file {
                do { newApp = try self.unpack(file, version: release.version) } catch { failure = error.localizedDescription }
            }
            DispatchQueue.main.async {
                self.state = .idle
                if let newApp { self.install(newApp) } else { self.failed(failure ?? "", page: release.page) }
            }
        }.resume()
    }

    private struct UpdateError: LocalizedError {
        let errorDescription: String?
    }

    /// zip を開き、中のアプリが同じアプリの新しいバージョンで、署名が壊れていないかを確かめる
    private func unpack(_ zip: URL, version: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("\(appName)-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, dir.path]) else { throw UpdateError(errorDescription: "zip") }
        let found = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }.first { $0.lastPathComponent == "\(appName).app" }
        guard let app = found, let info = Bundle(url: app)?.infoDictionary,
              info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == version else {
            throw UpdateError(errorDescription: L("ダウンロードしたファイルの中身が違います。"))
        }
        guard run("/usr/bin/codesign", ["--verify", "--deep", app.path]) else {
            throw UpdateError(errorDescription: L("ダウンロードしたアプリの署名が壊れています。"))
        }
        return app
    }

    private func install(_ newApp: URL) {
        let target = Bundle.main.bundleURL
        do {
            _ = try FileManager.default.replaceItemAt(target, withItemAt: newApp)
        } catch {
            failed(error.localizedDescription, page: latest?.page)
            return
        }
        // 終わったあとで新しいアプリを開く
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", target.path]
        try? p.run()
        NSApp.terminate(nil)
    }

    private func failed(_ reason: String, page: URL?) {
        alert(L("アップデートできませんでした"), reason + "\n" + L("リリースのページを開きます。手動で入れ替えてください。"))
        if let page { NSWorkspace.shared.open(page) }
    }

    @discardableResult
    private func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }

    private func alert(_ title: String, _ text: String) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        NSApp.activate(ignoringOtherApps: true)
        a.runModal()
    }
}

/// 選ばれたら handler を呼ぶメニューの項目（アプリごとの MenuAction と名前がぶつからないように別に持つ）
final class UpdaterMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(_ title: String, _ handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func run() { handler() }
}
