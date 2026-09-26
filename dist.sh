#!/bin/bash
# 配布用の zip を作る（GitHub Releases に置くもの）。
#   ./dist.sh → dist/DisplayToggle-<版>-ja.zip（説明書：はじめにお読みください.txt）
#               dist/DisplayToggle-<版>-en.zip（説明書：ReadMe.txt）
# 中身は DisplayToggle.app（日本語・英語入り）、コマンドの displayctl、説明書、LICENSE。
# 署名は仮のもの（ad-hoc）なので、受け取った人は初回だけ macOS の警告を許可する必要がある（説明書に手順あり）。
set -euo pipefail
cd "$(dirname "$0")"

./build.sh   # 最新の状態でビルドする（~/Applications にも入る）

VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" app/Info.plist)

make_zip() {   # $1 = ja / en、$2 = 説明書のファイル名
    local STAGE=build/dist/$1/DisplayToggle
    local ZIP=dist/DisplayToggle-$VERSION-$1.zip
    mkdir -p "$STAGE"
    ditto build/DisplayToggle.app "$STAGE/DisplayToggle.app"
    ditto build/displayctl "$STAGE/displayctl"
    cp "dist/$2" "$STAGE/"
    cp LICENSE "$STAGE/"   # MIT ライセンスは、配るときにライセンスの文章を添えることを求めている
    # zip コマンドは署名を壊すことがあるので ditto で固める
    rm -f "$ZIP"
    ditto -c -k --keepParent "$STAGE" "$ZIP"
    echo "作成: $ZIP"
}
rm -rf build/dist
make_zip ja "はじめにお読みください.txt"
make_zip en "ReadMe.txt"

open ~/Applications/DisplayToggle.app   # build.sh で止めたアプリを起動し直す
