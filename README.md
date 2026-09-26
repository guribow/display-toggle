# DisplayToggle

外付けモニター（セカンドモニター）を、メニューバーから macOS から切り離したり戻したりするアプリ。コマンドライン版の `displayctl` も付いている。

モニター本体の電源を切るだけでは、macOS は数分間そのモニターを接続中として扱う。そのあいだ、カーソルやウインドウが見えない画面に移ってしまう。このアプリで切り離すと、macOS からもすぐに消える。

- 作成：2026-09-23
- 動作確認：Mac mini（Apple Silicon）、macOS 27.2、Philips 230S8Q（セカンド）＋ HP 27f 4k（メイン）
- 動く環境：macOS 13 以降（Apple シリコン・Intel のユニバーサル）。Intel は Mac mini 2018（macOS 15.8.1、モニターなしのサーバー）で、アプリの起動・一覧・英語表示を確認した。Intel での切り離し・戻す・ケーブル未接続の判定は、モニターのある環境で未確認
- 言語：日本語・英語。Mac の言語設定が日本語なら日本語、それ以外なら英語で表示する（メニューバーのアプリもコマンドも）。アプリだけ言語を変えたいときは、システム設定 →「一般」→「言語と地域」→「アプリケーション」で指定する

## 使い方

### メニューバー

アイコン：接続中は画面2枚 `display.2`、切り離し中は画面1枚 `display`

```
✓ PHL 230S8Q          ← クリックで切り離す／戻す（✓ は接続中）
  HP 27f 4k（メイン）   ← メインは切り離せない
  PHL 230S8Q (2)（ケーブル未接続）    ← 同じ型番の 2 台目を、切り離し中にケーブルを抜いたもの。クリックで一覧から消す
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
displayctl forget PHL    # ケーブル未接続の記録を一覧から消す
```

モニターの名前は macOS から自動で取る（モニター本体が名乗る製品名）。同じ名前のモニターが複数あるときは、番号の小さい順に「PHL 230S8Q (1)」「PHL 230S8Q (2)」のように区別する。コマンドでは、一覧の左端の番号、「 (2)」付きの名前、名前の一部のどれでも指定できる。名前の一部が複数に当てはまるときは、どれか指定するよう案内する。

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
| `icon/make-icon.swift` | アプリアイコンを作るスクリプト |
| `icon/AppIcon.icns` | アプリアイコン（紫の角丸四角に白い画面2枚の記号） |
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

1. `displayctl` と `DisplayToggle.app` を、macOS 13 以降・Apple シリコンと Intel の両対応（ユニバーサル）でビルドする
2. アドホック署名（`codesign --sign -`）をする
3. 起動中のアプリを終了し、`~/Applications` のアプリを入れ替え、`displayctl` のリンクを張り直す

ビルドしたら、アプリを起動し直す。

```bash
open ~/Applications/DisplayToggle.app
```

アイコンを変えるときは `icon/make-icon.swift` の色や記号を書き換えて、次を実行してからビルドし直す。

```bash
swift icon/make-icon.swift   # icon/AppIcon.icns を作り直す
```

Finder に古いアイコンが残るときは `touch ~/Applications/DisplayToggle.app` を実行する。

## 仕組み

macOS の非公開API `CGSConfigureDisplayEnabled`（CoreGraphics / SkyLight）を `@_silgen_name` で宣言して呼んでいる。この関数は Apple の公開ドキュメントにはないが、Mac のモニター関係のオープンソースツールや、有志がまとめた非公開ヘッダー（CGSInternal など）で知られている。動くかどうかは、実機で切り離しと再接続を試して確認した（上記の動作確認環境）。

```swift
CGBeginDisplayConfiguration(&cfg)
CGSConfigureDisplayEnabled(cfg, displayID, false)   // true で再接続
CGCompleteDisplayConfiguration(cfg, .forSession)
```

切り離したモニターは `NSScreen.screens` から消える。そのため、切り離すときに displayID と、モニターが名乗るメーカー・製品・シリアル番号を状態ファイルに記録しておき、戻すときはその ID を使う。

切り離し中のモニターも、ケーブルがつながっていれば IORegistry の `IOMobileFramebufferShim`（Apple シリコンの Mac）に情報が残る。Intel の Mac では `IODisplayConnect` の情報を使う（Intel で切り離し中のモニターが残るかは未確認）。どちらも取れないときは、ケーブルの有無は判定しない。調べるときは `displayctl debug` で、macOS から見えるモニター・ケーブルでつながっているモニター・記録を並べて表示できる。記録した番号がここに見つからなければ「ケーブル未接続」とし、戻す操作はできないようにする。つなぎ直すと macOS が改めて認識するので、使い始めたモニターの記録は自動で消す。

## トラブルシューティング

| 症状 | 対処 |
|---|---|
| macOS をアップデートしたら切り離せなくなった | 非公開APIなので、仕様が変わった可能性がある。`displayctl off PHL` のエラーを確認する |
| 切り離したモニターが戻らない | `displayctl on` を実行する。それでも戻らなければ、アプリを終了するか、ケーブルを抜き差しするか、ログアウトする |
| 切り離し中にケーブルを抜いた | 「（ケーブル未接続）」と表示される。つなぎ直せば自動で元に戻る。もう使わないなら、メニューでクリックするか `displayctl forget <名前>` で一覧から消す |
| 状態の表示がおかしい（切り離し中のまま残っている） | `~/Library/Application Support/displayctl/disabled.json` を削除する |
| 「ログイン時に起動」でエラーが出る | アドホック署名のアプリは、`SMAppService` に登録できないことがある。その場合はシステム設定 › 一般 › ログイン項目 に手動で追加する |
| displayID が変わった（ケーブルの差し替えなど） | 一度 `displayctl on` で戻し、改めて切り離す |
| 同じ型番のモニターで (1) (2) が入れ替わった | 番号は displayID の小さい順。つなぐポートを変えると入れ替わることがある。一覧の左端の番号で指定すると確実 |

## 経緯

- 無料の代替アプリを検討したが、どれも画面を黒くするだけで、macOS からは切り離さなかった。Lunar の BlackOut は Pro 版のみ、MonitorControl と Blackout – Display Manager は画面を覆うだけ。
- BetterDisplay の Disconnect は Pro（有料）機能だったため、上記の非公開APIを使う小さなアプリを自作した。BetterDisplay の実装は参照していない（非公開のため不明）。BetterDisplay はアンインストール済み。

## ライセンス

MIT ライセンス（[LICENSE](LICENSE)）。自由に使う・改変する・配ることができる。配るときは著作権表示（© 2026 guribow）とライセンスの文章を残すこと。無保証で、使って起きたことについて作者は責任を負わない。
