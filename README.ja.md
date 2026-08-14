<img src="docs/icon.png" width="128" align="right" alt="MemoryBar のアイコン">

# MemoryBar

[English](README.md) | **日本語**

macOSのメニューバーに常駐し、メモリの残容量・使用量をアクティビティモニタと同じ計算式でリアルタイム表示するアプリ。

[![ダウンロード](https://img.shields.io/github/v/release/sugasaki/memorybar?label=download&style=flat-square)](https://github.com/sugasaki/memorybar/releases/latest/download/MemoryBar.zip)
[![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?style=flat-square)](#ビルド)
[![Swift 6](https://img.shields.io/badge/Swift-6-orange?style=flat-square)](Package.swift)
[![MIT](https://img.shields.io/badge/license-MIT-blue?style=flat-square)](LICENSE)

- メニューバーに常時表示(約1秒間隔で更新)。表示する値は **残容量GB / 使用量GB / 使用率%** から選べ、パネルの大きな数値も同じ値になる
- 既定はコンパクト表示。「詳細」を開くと内訳と使用量の多いアプリが出る
- **フローティングウィンドウ**で常時表示できる(リサイズ可能・全スペースに追従・×で閉じる)
- 使用量の多いアプリを表示(何を終了すれば楽になるかが分かる)
- 更新を自動で確認して適用する
- Swift + SwiftUI製、外部依存なし。実測でCPU約1%、常駐時のメモリ約70MB

メニューパネルとフローティングウィンドウは同じ見た目で、開閉状態だけ別々に持つ。

## スクリーンショット

<img src="docs/screenshots/menubar.png" width="420" alt="macOS のメニューバー。メモリチップのアイコンの隣に MemoryBar が 2.5G と表示している">

*メニューバーでの表示 — メモリチップのアイコンと `2.5G`。数値は選んだモードに従う。*

| コンパクト表示 | 詳細を開いた状態 |
| --- | --- |
| <img src="docs/screenshots/floating.png" width="300" alt="利用可能なメモリ 2.56 GB、内訳の帯、搭載/使用済み/利用可能の行を表示した MemoryBar"> | <img src="docs/screenshots/floating-details.png" width="300" alt="詳細を開き、内訳・使用済みスワップ・使用率・使用量の多いアプリを表示した MemoryBar"> |
| 選んだ値・内訳の帯・搭載/使用済み/利用可能。右上の点はメモリプレッシャー。 | 帯の内訳、スワップ、使用率、使用量の多いアプリ。 |

ここではフローティングウィンドウを載せているため閉じるボタンが付いている。メニューバーのパネルも同じ表示で、下に設定と終了が加わる。

## インストール

**[MemoryBar.zip](https://github.com/sugasaki/memorybar/releases/latest/download/MemoryBar.zip)** をダウンロードし、展開して `MemoryBar.app` を `/Applications` に置く。

- Apple SiliconとIntelの両方で動くUniversalビルド。`main`への変更ごとにGitHub Actionsが自動で更新する

**初回起動時に自分でログイン項目へ登録する**ため、設定は要らない。パネルの「ログイン時に開く」で解除でき、一度自分で切り替えたあとは勝手に登録し直さない。macOS側の許可が必要な状態ならパネルにその旨が出て、「ログイン項目の設定を開く」から移動できる。

### 初回起動時の許可(1回だけ)

ad-hoc署名のため、**ブラウザでダウンロードした場合のみ**macOSが初回起動をブロックする。次のいずれかで許可する。

- `MemoryBar.app` を右クリック →「開く」→ ダイアログで「開く」
- 「システム設定 > プライバシーとセキュリティ」の「このまま開く」
- `xattr -dr com.apple.quarantine /Applications/MemoryBar.app`

2回目以降は不要。アプリ内の更新では差し替え時に検疫属性を取り除くため、警告は出ない。

## 自動アップデート

起動時と、以降6時間おきに最新リリースを確認する。既定では**更新が見つかると自動でインストールして再起動**する。差し替えに失敗した場合は元のバージョンへ戻して再起動する。

- 「更新を自動でインストール」をオフにすると、更新があってもパネルに表示するだけになり、「インストールして再起動」を押したときにだけ適用する
- 「定期的に自動で確認」をオフにすると自動確認そのものを止められる
- パネルの「更新を確認」でいつでも手動確認できる
- ログは `~/Library/Logs/MemoryBar-update.log`

**認証は不要**で、アプリはトークンを一切持たない。公開リポジトリのリリースを素のHTTPSで取得する。追加のインストールも設定もいらない。

## 表示している値

```
未使用   = free_count − speculative
残容量   = 未使用 + キャッシュされたファイル(external + purgeable)
使用済み = 物理メモリ(hw.memsize) − 残容量

アプリメモリ = internal − purgeable   確保済み = wired   圧縮 = compressor
その他       = 使用済み − (アプリメモリ + 確保済み + 圧縮)
```

解放できる領域を残容量として先に定め、使用済みをそこから導出する。こうすると両者の合計が必ず物理メモリに一致する。データソースはアクティビティモニタと同じ Mach API `host_statistics64`。

読むうえで押さえておく点が3つある。

**「その他」があるのは、アクティビティモニタの「使用済みメモリ」が3内訳(アプリ+確保済み+圧縮)の合計ではないため。** 実測で約0.73GB大きく、その差はメモリ状態が動く間もほぼ一定。VMがどの内訳にも計上していないページ(カーネル/ファームウェア予約領域など)にあたる。これを表示することで、画面上で内訳の合計と使用済みが一致する。

**残容量はファイルキャッシュを含むため「いますぐ確実に使える量」の上限にあたる。** キャッシュは必要に応じて解放されるが、書き戻し前のページは即座には解放できない。実際の逼迫度はメモリプレッシャーとスワップ使用量を併せて見る。

**アクティビティモニタとの差は0.15GB程度残る。** 使用済みメモリは1秒で最大0.16GB動くため、採取時刻の差がそのまま出る。アクティビティモニタ側も「使用済み+キャッシュ>物理メモリ」となる瞬間があり、その表示が単一時点のものではないため、これ以上の一致は原理的に難しい。内訳(アプリ/確保済み/圧縮/キャッシュ/スワップ)は完全に一致する。

計算式の検証記録は [Issue #24](https://github.com/sugasaki/memorybar/issues/24) を参照。

### 使用量の多いアプリ

各アプリの値は、そのアプリに属するプロセスの `phys_footprint` の合計。これは**アクティビティモニタの「メモリ」列と同じ指標**で、同時刻の比較で一致することを確認している。

ヘルパープロセスは親アプリにまとめるため、Chromeのように多数の子プロセスを持つアプリも1行で見られる。所有者の違うプロセス(端末が挟む `login` など)を経由していても辿れるようにしてあり、メニューバー常駐アプリ配下のプロセスも名前で表示される。

**合計が物理メモリを超えることがある。** `phys_footprint` は圧縮済み・スワップ済みの分を含むためで、二重計上ではない。

他ユーザー所有のプロセスは権限の都合で取得できないため含まれない。取得できた分のうち上位に入らなかったものは「その他のプロセス」としてまとめ、黙って落とさないようにしている。

## ビルド

要件: macOS 14以降、Xcode(またはSwift 6 toolchain)

```sh
swift build
swift test
swift run              # そのまま実行(メニューバーに常駐)
```

`.app` として使う場合:

```sh
scripts/make-app.sh                                   # 自アーキテクチャのみ(高速)
UNIVERSAL=1 scripts/make-app.sh                       # arm64 + x86_64(配布用)
APP_VERSION=0.9.9 APP_BUILD=42 scripts/make-app.sh    # バージョンを明示指定
cp -R dist/MemoryBar.app /Applications/
```

生成物はad-hoc署名。第三者へ配布する場合はDeveloper ID Application証明書での署名とnotarizationが別途必要。

### バージョン

**Git タグ(`vX.Y.Z`)が唯一の出所**。`main` へマージするたびにCIがパッチ番号を進めてタグを打つため、手で管理する必要はない。メジャー・マイナーを上げたいときは、Releaseワークフローを手動実行してバージョンを指定する。

手元ビルドでは「いま出ている最新のタグ」を表示する(次の番号を騙らない)。未コミットの変更を含むビルドは `MBSourceCommit` に `-dirty` が付き、更新判定から外れる。

### アイコン

`scripts/icon/make-icon.swift` が全サイズを生成する。**生成物ではなく生成コードを置いている**ので、色や形はコードを直して作り直せる。`scripts/make-app.sh` がビルドのたびに呼び出すため、手作業は要らない。

16pxでは要素が潰れるため、ピンを省き帯を3色に絞った専用の描き分けをしている。

## 検証用コマンド

`.app` 内の実行ファイルを直接起動する(`swift run` では `.app` でないため更新判定まで確認できない)。

```sh
dist/MemoryBar.app/Contents/MacOS/memorybar --print           # 1回分のサンプルを出力
dist/MemoryBar.app/Contents/MacOS/memorybar --apps            # 使用量の多いアプリを出力
dist/MemoryBar.app/Contents/MacOS/memorybar --check-update    # 更新確認のみ
/Applications/MemoryBar.app/Contents/MacOS/memorybar --install-update   # 実際に適用
```

`--install-update` は常駐中に実行すると動作中のバンドルを置き換えてしまうため、**MemoryBarが起動中は拒否される**。先に終了しておく。

## 名前について

旧称は TrueMem。「正確な値を出す」という開発上の主張が名前になっており、使う人の視点ではなかったため MemoryBar に改めた(2026-08、[Issue #61](https://github.com/sugasaki/memorybar/issues/61))。

Spotlight は前方一致が強いため、先頭が `Memory` だと「Memory」と打った時点で候補に出る。表記は空白なしに統一している(パスやURLに空白が入るのを避けるため)。

## 開発

- 開発規約と実装上の注意: [AGENTS.md](AGENTS.md)([agent-project-template](https://github.com/sugasaki/agent-project-template)ベース)
- 設計判断の記録: [Wiki](https://github.com/sugasaki/memorybar/wiki) — コードを読んでも分からない「なぜそうしたか / なぜそうしなかったか」
  - [パネルの高さ問題](https://github.com/sugasaki/memorybar/wiki/%E3%83%91%E3%83%8D%E3%83%AB%E3%81%AE%E9%AB%98%E3%81%95%E5%95%8F%E9%A1%8C) — メニューパネルの高さを触る前に必ず読む(5回壊した)
  - [配布と自動アップデートの変遷](https://github.com/sugasaki/memorybar/wiki/%E9%85%8D%E5%B8%83%E3%81%A8%E8%87%AA%E5%8B%95%E3%82%A2%E3%83%83%E3%83%97%E3%83%87%E3%83%BC%E3%83%88%E3%81%AE%E5%A4%89%E9%81%B7) — private + `gh` から public + 未認証 HTTPS へ切り替えた判断
  - [メモリ解放機能を実装しない判断](https://github.com/sugasaki/memorybar/wiki/%E3%83%A1%E3%83%A2%E3%83%AA%E8%A7%A3%E6%94%BE%E6%A9%9F%E8%83%BD%E3%82%92%E5%AE%9F%E8%A3%85%E3%81%97%E3%81%AA%E3%81%84%E5%88%A4%E6%96%AD) / [UI実装でつまずいた点](https://github.com/sugasaki/memorybar/wiki/UI%E5%AE%9F%E8%A3%85%E3%81%A7%E3%81%A4%E3%81%BE%E3%81%9A%E3%81%84%E3%81%9F%E7%82%B9)

## ライセンス

[MIT](LICENSE)
