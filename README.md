# TrueMem

macOSのメニューバーに常駐し、メモリの**残容量・使用量をアクティビティモニタと同じ計算式で正確に**リアルタイム表示するアプリ。

名前の由来: 既存の類似アプリのような乖離のない「真の(true)メモリ値」を表示すること。

## なぜ作ったか

既存のメニューバー系メモリ監視アプリの多くは`vm_stat`のfree pagesなどを表示するため、アクティビティモニタの値と大きく乖離する。macOSは空きメモリを積極的にファイルキャッシュへ回すので、「free pages」は実際に使える残容量を表さない。

TrueMemはアクティビティモニタと**同じデータソース(Mach API `host_statistics64`)・同じ計算式**を使う:

```
使用済みメモリ = アプリメモリ(internal − purgeable) + 確保済み(wired) + 圧縮(compressor)
残容量        = 物理メモリ(hw.memsize) − 使用済みメモリ
```

## 機能

- メニューバーに常時表示(約2秒間隔で更新)
- 表示モードを切替可能: **残容量GB / 使用量GB / 使用率%**
- クリックで詳細パネル: アプリメモリ / 確保済み / 圧縮 / キャッシュされたファイル / 使用済みスワップ / メモリプレッシャー
- ネイティブSwift + SwiftUI製。アプリ自体のメモリ消費は最小限、外部依存なし

## ビルドと実行

要件: macOS 14以降、Xcode(またはSwift 6 toolchain)

```sh
swift build            # ビルド
swift test             # テスト
swift run              # そのまま実行(メニューバーに常駐)
```

### .appとしてローカルで使う(推奨)

```sh
scripts/make-app.sh
cp -R dist/TrueMem.app /Applications/
```

バージョンとビルド番号はスクリプトを編集せず指定できる:

```sh
APP_VERSION=0.2.0 APP_BUILD=42 scripts/make-app.sh
```

生成物はad-hoc署名で、同じMacでのローカル利用を想定している。第三者へ外部配布する場合は、Developer ID Application証明書での署名とAppleのnotarizationを別途行うこと。

ログイン時に自動起動するには「システム設定 > 一般 > ログイン項目」に追加する。

### 値の検証

1回分のサンプルを標準出力に出して終了する:

```sh
swift run truemem --print
```

アクティビティモニタの「メモリ」タブと突き合わせて確認できる。

### メモリプレッシャーの検証

常駐中のプレッシャー変化は、公開APIの`DispatchSource.makeMemoryPressureSource`から取得する。DispatchSourceが最初のイベントを通知するまでの起動直後だけ、同期表示のため`kern.memorystatus_vm_pressure_level`を互換レイヤーで参照する。取得失敗や未知値は「通常」へ置換せず「取得不能」と表示する。

対応OSでの手動確認:

1. macOS 14または15以降でTrueMemとアクティビティモニタの「メモリ」タブを開く
2. 起動直後の表示と、メモリ負荷が変化した後の通常・注意・危険の遷移を比較する
3. スリープ・復帰後も約2秒間隔の数値更新とプレッシャー通知が続くことを確認する
4. InstrumentsのEnergy LogまたはActivity MonitorでIdle Wake Upsが過剰に増えないことを確認する

## 開発

開発規約は[AGENTS.md](AGENTS.md)を参照([agent-project-template](https://github.com/sugasaki/agent-project-template)ベース)。
