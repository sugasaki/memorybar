# TrueMem

macOSのメニューバーに常駐し、メモリの**残容量・使用量をアクティビティモニタと同じ計算式で正確に**リアルタイム表示するアプリ。

名前の由来: 既存の類似アプリのような乖離のない「真の(true)メモリ値」を表示すること。

## なぜ作ったか

既存のメニューバー系メモリ監視アプリの多くは`vm_stat`のfree pagesなどを表示するため、アクティビティモニタの値と大きく乖離する。macOSは空きメモリを積極的にファイルキャッシュへ回すので、「free pages」は実際に使える残容量を表さない。

TrueMemはアクティビティモニタと**同じデータソース(Mach API `host_statistics64`)・同じ計算式**を使う:

```
未使用   = free_count − speculative
残容量   = 未使用 + キャッシュされたファイル(external + purgeable)
使用済み = 物理メモリ(hw.memsize) − 残容量
```

**解放できる領域を残容量として先に定め、使用済みをそこから導出する。** こうすると両者の合計が必ず物理メモリに一致する。

`speculative`(先読みされたファイル内容を持つページ)を `free_count` から引いている点が重要で、これは `external` 側にも含まれるため、引かないと二重計上になる(`vm_stat` の「Pages free」も同じく `free_count − speculative` を表示している)。ファイル読み込みが走ると最大0.35GBほど残容量が過大に出る。

注意すべき点として、**アクティビティモニタの「使用済みメモリ」は、その右に並ぶ3つの内訳(アプリ+確保済み+圧縮)の合計ではない**。実測では約0.73GB大きく、この差はメモリの状態が大きく動く間もほぼ一定である。差分はVMがどの内訳にも計上していないページ(カーネル/ファームウェア予約領域など)で、TrueMemはこれを「その他」として表示するため、画面上で内訳の合計と使用済みが一致する。

この式はアクティビティモニタと同時刻に採取して照合している(詳細は [Issue #24](https://github.com/sugasaki/truemem/issues/24))。なおアクティビティモニタの表示更新は既定で5秒間隔のため、変動の速い項目では時間差による見かけ上の差が出る。

### 残容量の読み方

残容量にはファイルキャッシュを含む。キャッシュは必要に応じて解放されるが、**書き戻し前のページは即座には解放できない**ため、この値は「いますぐ確実に使える量」の上限にあたる。実際の逼迫度はメモリプレッシャーとスワップ使用量を併せて見るのが正確。

## 機能

- メニューバーに常時表示(約1秒間隔で更新)
- 表示モードを切替可能: **残容量GB / 使用量GB / 使用率%**
- クリックで詳細パネル: アプリメモリ / 確保済み / 圧縮 / キャッシュされたファイル / 使用済みスワップ / メモリプレッシャー
- ネイティブSwift + SwiftUI製。アプリ自体のメモリ消費は最小限、外部依存なし

## ダウンロード

最新版は次のリンクからダウンロードできる(GitHubにログインした状態で開く。privateリポジトリのため):

**[TrueMem.zip](https://github.com/sugasaki/truemem/releases/latest/download/TrueMem.zip)**

Apple SiliconとIntelの両方で動くUniversalビルド。`main`への変更ごとにGitHub Actionsが自動更新する。

展開して `TrueMem.app` を `/Applications` に置く。ログイン時に自動起動するには「システム設定 > 一般 > ログイン項目」に追加する。

### 初回起動時の許可(1回だけ必要)

ad-hoc署名のため、**ブラウザでダウンロードした場合のみ**macOSが初回起動をブロックする。次のいずれかで許可する:

- `TrueMem.app` を右クリック →「開く」→ ダイアログで「開く」
- または「システム設定 > プライバシーとセキュリティ」を開き、下部の「"TrueMem"は開発元を確認できないため…」の横の「このまま開く」
- またはターミナルで検疫属性を削除する:
  ```sh
  xattr -dr com.apple.quarantine /Applications/TrueMem.app
  ```

**2回目以降は不要**。アプリ内の自動アップデートは `gh` 経由でダウンロードするため検疫属性が付かず、警告は出ない。

## 自動アップデート

アプリが起動時に最新リリースを確認する。**確認するだけで、勝手にインストールはしない**。更新があるとメニューパネルに「新しいバージョンがあります」と表示され、「インストールして再起動」ボタンを押したときにだけ、ダウンロード・入れ替え・再起動を行う。

- メニューの「更新を確認」で手動確認もできる
- 「起動時に自動で確認」のチェックを外すと自動確認を止められる
- 差し替えに失敗した場合は自動で元のバージョンへ戻し、アプリを再起動する

privateリポジトリのため認証が必要だが、**アプリはトークンを一切保持しない**。認証済みの [GitHub CLI (`gh`)](https://cli.github.com/) に委譲する仕組みなので、次が前提になる:

```sh
brew install gh
gh auth login
```

更新確認だけを実行して結果を確認するには(インストールはしない):

```sh
dist/TrueMem.app/Contents/MacOS/truemem --check-update
```

`swift run truemem --check-update` でも実行できるが、その場合は `.app` ではないためビルド元コミットが不明になり、`gh` の疎通確認にしかならない。更新判定まで確認するには上記のように `.app` 内の実行ファイルを直接起動する。

実際にインストールまで行う場合(通常はメニューの「インストールして再起動」を使う):

```sh
# TrueMem を終了してから実行する
/Applications/TrueMem.app/Contents/MacOS/truemem --install-update
```

差し替え処理は起動元プロセスの終了を待つ仕組みのため、TrueMem が常駐したままこのコマンドを実行すると、動作中のバンドルを置き換えてしまう。そのため**常駐中は実行を拒否する**ようにしてある。

更新の適用時のログは `~/Library/Logs/TrueMem-update.log` に残る。

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

バージョンはリポジトリ直下の `VERSION` ファイルを唯一の出所とし、リリースビルドと手元ビルドで食い違わないようにしている。上書きしたい場合や Universal ビルドは環境変数で指定できる:

```sh
scripts/make-app.sh                                   # VERSION の値・自アーキテクチャのみ(高速)
UNIVERSAL=1 scripts/make-app.sh                       # arm64 + x86_64(配布用)
APP_VERSION=0.9.9 APP_BUILD=42 scripts/make-app.sh    # 明示指定
```

生成物はad-hoc署名で、同じMacでのローカル利用を想定している。第三者へ外部配布する場合は、Developer ID Application証明書での署名とAppleのnotarizationを別途行うこと。

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
3. スリープ・復帰後も約1秒間隔の数値更新とプレッシャー通知が続くことを確認する
4. InstrumentsのEnergy LogまたはActivity MonitorでIdle Wake Upsが過剰に増えないことを確認する

## 開発

開発規約は[AGENTS.md](AGENTS.md)を参照([agent-project-template](https://github.com/sugasaki/agent-project-template)ベース)。
