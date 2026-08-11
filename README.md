# memory-info-menubar

macOS のメニューバーに常駐し、メモリの**残容量・使用量をアクティビティモニタと同じ計算式で正確に**リアルタイム表示するアプリ。

## なぜ作ったか

既存のメニューバー系メモリ監視アプリの多くは `vm_stat` の free pages などを表示するため、アクティビティモニタの値と大きく乖離する。macOS は空きメモリを積極的にファイルキャッシュへ回すので、「free pages」は実際に使える残容量を表さない。

このアプリはアクティビティモニタと**同じデータソース(Mach API `host_statistics64`)・同じ計算式**を使う:

```
使用済みメモリ = アプリメモリ(internal − purgeable) + 確保済み(wired) + 圧縮(compressor)
残容量        = 物理メモリ(hw.memsize) − 使用済みメモリ
```

## 機能

- メニューバーに常時表示(約2秒間隔で更新)
- 表示モードを切替可能: **残容量GB / 使用量GB / 使用率%**
- クリックで詳細パネル: アプリメモリ / 確保済み / 圧縮 / キャッシュされたファイル / 使用済みスワップ / メモリプレッシャー
- ネイティブ Swift + SwiftUI 製。アプリ自体のメモリ消費は最小限、外部依存なし

## ビルドと実行

要件: macOS 14 以降、Xcode(または Swift 6 toolchain)

```sh
swift build            # ビルド
swift test             # テスト
swift run              # そのまま実行(メニューバーに常駐)
```

### .app として使う(推奨)

```sh
scripts/make-app.sh
cp -R "dist/Memory Info.app" /Applications/
```

ログイン時に自動起動するには「システム設定 > 一般 > ログイン項目」に追加する。

### 値の検証

1回分のサンプルを標準出力に出して終了する:

```sh
swift run memory-info-menubar --print
```

アクティビティモニタの「メモリ」タブと突き合わせて確認できる。

## 開発

開発規約は [AGENTS.md](AGENTS.md) を参照([agent-project-template](https://github.com/sugasaki/agent-project-template) ベース)。
