# TrueMem

macOSのメニューバーに常駐し、メモリの残容量・使用量をアクティビティモニタと同じ計算式でリアルタイム表示するアプリ。

- メニューバーに常時表示(約1秒間隔で更新)。表示は **残容量GB / 使用量GB / 使用率%** から選べる
- フローティングウィンドウで常時表示できる(オン/オフ切替、リサイズ可能、内訳表示、全スペースに追従)
- クリックで詳細パネル: アプリメモリ / 確保済み / 圧縮 / その他 / キャッシュされたファイル / 未使用 / 使用済みスワップ / メモリプレッシャー
- 使用量の多いアプリを表示(何を終了すれば楽になるかが分かる)
- アプリ内から更新できる(同意なしにはインストールしない)
- Swift + SwiftUI製、外部依存なし。実測でCPU約1%、常駐時のメモリ約70MB

## インストール

**[TrueMem.zip](https://github.com/sugasaki/truemem/releases/latest/download/TrueMem.zip)** をダウンロードし、展開して `TrueMem.app` を `/Applications` に置く。

- privateリポジトリのため、GitHubにログインした状態で開くこと
- Apple SiliconとIntelの両方で動くUniversalビルド。`main`への変更ごとにGitHub Actionsが自動で更新する
- ログイン時に自動起動するには「システム設定 > 一般 > ログイン項目」に追加する

### 初回起動時の許可(1回だけ)

ad-hoc署名のため、**ブラウザでダウンロードした場合のみ**macOSが初回起動をブロックする。次のいずれかで許可する。

- `TrueMem.app` を右クリック →「開く」→ ダイアログで「開く」
- 「システム設定 > プライバシーとセキュリティ」の「このまま開く」
- `xattr -dr com.apple.quarantine /Applications/TrueMem.app`

2回目以降は不要。アプリ内の更新は `gh` 経由で取得するため検疫属性が付かず、警告は出ない。

## 自動アップデート

起動時に最新リリースを確認する。**確認するだけで、勝手にインストールはしない。** 更新があるとパネルに表示され、「インストールして再起動」を押したときにだけ適用する。差し替えに失敗した場合は元のバージョンへ戻して再起動する。

- パネルの「更新を確認」で手動確認、「起動時に自動で確認」で自動確認のオン/オフ
- ログは `~/Library/Logs/TrueMem-update.log`

privateリポジトリのため認証が要るが、**アプリはトークンを保持しない**。認証済みの [GitHub CLI](https://cli.github.com/) に委譲するので、次が前提になる。

```sh
brew install gh
gh auth login
```

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

計算式の検証記録は [Issue #24](https://github.com/sugasaki/truemem/issues/24) を参照。

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
cp -R dist/TrueMem.app /Applications/
```

バージョンはリポジトリ直下の `VERSION` を唯一の出所とし、リリースビルドと手元ビルドで食い違わないようにしている。未コミットの変更を含むビルドは `TMSourceCommit` に `-dirty` が付き、更新判定から外れる。

生成物はad-hoc署名。第三者へ配布する場合はDeveloper ID Application証明書での署名とnotarizationが別途必要。

## 検証用コマンド

`.app` 内の実行ファイルを直接起動する(`swift run` では `.app` でないため更新判定まで確認できない)。

```sh
dist/TrueMem.app/Contents/MacOS/truemem --print           # 1回分のサンプルを出力
dist/TrueMem.app/Contents/MacOS/truemem --apps            # 使用量の多いアプリを出力
dist/TrueMem.app/Contents/MacOS/truemem --check-update    # 更新確認のみ
/Applications/TrueMem.app/Contents/MacOS/truemem --install-update   # 実際に適用
```

`--install-update` は常駐中に実行すると動作中のバンドルを置き換えてしまうため、**TrueMemが起動中は拒否される**。先に終了しておく。

## 開発

開発規約と実装上の注意は [AGENTS.md](AGENTS.md) を参照([agent-project-template](https://github.com/sugasaki/agent-project-template)ベース)。

## 使用量の多いアプリについて

各アプリの値は、そのアプリに属するプロセスの `phys_footprint` の合計です。これは**アクティビティモニタの「メモリ」列と同じ指標**で、同時刻の比較で一致することを確認しています。ヘルパープロセスは親アプリにまとめるため、Chrome のように多数の子プロセスを持つアプリも1行で見られます。

**合計が物理メモリを超えることがあります。** `phys_footprint` は圧縮済み・スワップ済みの分を含むためで、二重計上ではありません。

ヘルパープロセスは親アプリにまとめます。所有者の違うプロセス(端末が挟む `login` など)を経由していても辿れるようにしてあり、メニューバー常駐アプリ配下のプロセスも名前で表示されます。

他ユーザー所有のプロセスは権限の都合で取得できないため含まれません。取得できた分のうち上位に入らなかったものは「その他のプロセス」としてまとめ、黙って落とさないようにしています。
