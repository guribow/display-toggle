# DisplayToggle

外付けモニター（セカンドモニター）を、メニューバーから macOS から切り離したり戻したりするアプリ。コマンドライン版の `displayctl` も付いている。

モニター本体の電源を切るだけでは、macOS は数分間そのモニターを接続中として扱う。そのあいだ、カーソルやウインドウが見えない画面に移ってしまう。このアプリで切り離すと、macOS からもすぐに消える。

- 作成：2026-09-23
- 動作確認：Mac mini（Apple Silicon）、macOS 27.2、Philips 230S8Q（セカンド）＋ HP 27f 4k（メイン）

## 使い方

### メニューバー

アイコン：接続中は画面2枚 `display.2`、切り離し中は画面1枚 `display`

```
✓ PHL 230S8Q          ← クリックで切り離す／戻す（✓ は接続中）
  HP 27f 4k（メイン）   ← メインは切り離せない
──────────
  ログイン時に起動
  終了（モニターを全部戻す）   ⌘Q
```

### コマンドライン

```bash
displayctl list          # モニター一覧（メイン・切り離し中の表示付き）
displayctl toggle PHL    # 切り離す ⇄ 戻す
displayctl off PHL       # 切り離す（名前の一部で指定）
displayctl on            # 切り離し中をすべて戻す
displayctl on PHL        # 指定したモニターだけ戻す
```

メニューバーアプリとコマンドは同じ状態ファイルを使う。どちらで切り離しても、もう一方から戻せる。

## 安全のための仕様

- **メインモニターは切り離せない**。モニターが1台しかないときも切り離さない。画面が真っ暗になるのを防ぐため。
- 切り離しは `.forSession` で行う。**ログアウトや再起動をすると元に戻る**。
- アプリを**終了すると、切り離し中のモニターをすべて戻す**。

## ファイル構成

| ファイル | 内容 |
|---|---|
| `DisplayCore.swift` | 切り離し・再接続の共通処理（アプリとコマンドの両方から使う） |
| `app/main.swift` | メニューバーアプリ（`NSStatusItem`、Dock には出ない） |
| `app/Info.plist` | アプリの設定（`LSUIElement`、Bundle ID `com.guribow.displaytoggle`） |
| `cli/main.swift` | `displayctl` コマンド |
| `build.sh` | ビルドとインストール |
| `build/` | ビルド結果（生成物） |

インストール先：

- アプリ：`~/Applications/DisplayToggle.app`
- コマンド：`/opt/homebrew/bin/displayctl`（`build/displayctl` へのシンボリックリンク）
- 状態ファイル：`~/Library/Application Support/displayctl/disabled.json`（切り離し中のモニター名と displayID）

## ビルド

Xcode（`swiftc`）が必要。

```bash
cd ~/ClaudWork/display-toggle && ./build.sh
```

`build.sh` は次の処理を行う。

1. `displayctl` と `DisplayToggle.app` をビルドする
2. アドホック署名（`codesign --sign -`）をする
3. 起動中のアプリを終了し、`~/Applications` のアプリを入れ替え、`displayctl` のリンクを張り直す

ビルドしたら、アプリを起動し直す。

```bash
open ~/Applications/DisplayToggle.app
```

## 仕組み

macOS の非公開API `CGSConfigureDisplayEnabled`（CoreGraphics / SkyLight）を `@_silgen_name` で宣言して呼んでいる。BetterDisplay の Disconnect も同じAPIを使っている。

```swift
CGBeginDisplayConfiguration(&cfg)
CGSConfigureDisplayEnabled(cfg, displayID, false)   // true で再接続
CGCompleteDisplayConfiguration(cfg, .forSession)
```

切り離したモニターは `NSScreen.screens` から消える。そのため、切り離すときに displayID を状態ファイルに記録しておき、戻すときはその ID を使う。

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| macOS をアップデートしたら切り離せなくなった | 非公開APIなので、仕様が変わった可能性がある。`displayctl off PHL` のエラーを確認する |
| 切り離したモニターが戻らない | `displayctl on` を実行する。それでも戻らなければ、アプリを終了するか、ケーブルを抜き差しするか、ログアウトする |
| 状態の表示がおかしい（切り離し中のまま残っている） | `~/Library/Application Support/displayctl/disabled.json` を削除する |
| 「ログイン時に起動」でエラーが出る | アドホック署名のアプリは、`SMAppService` に登録できないことがある。その場合はシステム設定 › 一般 › ログイン項目 に手動で追加する |
| displayID が変わった（ケーブルの差し替えなど） | 一度 `displayctl on` で戻し、改めて切り離す |

## 経緯

- 無料の代替アプリを検討したが、どれも画面を黒くするだけで、macOS からは切り離さなかった。Lunar の BlackOut は Pro 版のみ、MonitorControl と Blackout – Display Manager は画面を覆うだけ。
- BetterDisplay の Disconnect は Pro（有料）機能だった。そこで同じAPIを使う小さなアプリを自作した。BetterDisplay はアンインストール済み。
