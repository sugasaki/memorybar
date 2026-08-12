# MemoryBar — AI エージェント向けガイド

このリポジトリで作業するすべての AI エージェント向けのガイド（特定製品に依存せず、`AGENTS.md` を読むエージェントすべてが対象。Claude Code / Codex / opencode / GLM / Cursor / Gemini など）。
**このファイルが正本**。`CLAUDE.md` は Claude Code 用の参照スタブで、中身はここに集約する。

## プロジェクト概要
MemoryBar — macOS のメニューバーに常駐し、メモリの残量・使用量をリアルタイム表示するネイティブアプリ。
**アクティビティモニタと同じデータソース（Mach API `host_statistics64`）・同じ計算式**で正確な値を表示することが最重要の要件。

- 未使用 = `free_count − speculative` / 残容量 = 未使用 + キャッシュされたファイル（external + purgeable）/ 使用済み = 物理メモリ − 残容量
- **`free_count` は speculative を含み、speculative は `external` にも含まれる**。引かないと二重計上になり、ファイル読み込み時に残容量が最大0.35GB過大になる（`vm_stat` の「Pages free」も `free_count − speculative`）
- **アクティビティモニタの「使用済みメモリ」は3内訳（アプリ+確保済み+圧縮）の合計ではない**。約0.73GB大きく、この差はメモリ状態が動く間もほぼ一定。差分はVMがどの内訳にも計上しないページで、「その他」として表示する（Issue #24）
- 計算式を変えたときは、**speculative を意図的に増やした状態**（大きなファイルを連続読み）でも照合すること。静穏時は両式の差が小さく、誤りを見逃す
- 内訳: アプリメモリ = internal − purgeable / 確保済み = wired / 圧縮 = compressor
- 表示する値は 残容量GB / 使用量GB / 使用率% を設定で切替可能。**メニューバーと要約表示の両方に同じ値を出す**(片方だけ変わると同じ画面で違う値が並び混乱する。Issue #63)
- クリックで詳細（アプリ/確保済み/圧縮/キャッシュ/スワップ/メモリプレッシャー）を表示

## Tech Stack
- Swift 6 + SwiftUI（`MenuBarExtra` によるメニューバー常駐）
- Swift Package Manager（Xcode プロジェクトファイルは使わない）
- 外部依存なし（標準フレームワーク + Mach / sysctl API のみ）
- 対応 OS: macOS 14 以降

## ビルド・実行
```sh
swift build            # デバッグビルド
swift test             # テスト実行
swift run              # そのまま実行（メニューバーに常駐）
scripts/make-app.sh    # ローカル利用向け .app バンドルを dist/ に生成
```

## ファイル構成
- `Package.swift` — SPM マニフェスト
- `Sources/MemoryBar/`
  - `App.swift` — エントリポイント（`MenuBarExtra`・アクセサリ化）
  - `MemorySampler.swift` — Mach / sysctl からの計測（副作用はここに隔離）
  - `MemorySnapshot.swift` — 計測値から使用量・残量を導出する純粋ロジック
  - `DisplayMode.swift` — メニューバー表示モードとフォーマット
  - `MenuContentView.swift` — クリック時の詳細パネル
  - `Updater.swift` — GitHub Releases からの更新確認・適用（`gh` CLI に認証を委譲）
  - `UpdateController.swift` — 更新の進行状態と確認ダイアログ
- `Sources/CMachSupport/` — Swift へ import できない Mach 定数を公開する最小 C shim
- `Tests/MemoryBarTests/` — ユニットテスト（純粋ロジック + 実機サンプリング・Mach ポートリーク回帰）
- `scripts/make-app.sh` — .app バンドル生成スクリプト

## 開発パターン
- **計算ロジックと計測を分離する**: Mach API 呼び出し（`MemorySampler`）と数値の導出（`MemorySnapshot`）を分け、導出側は生のページカウントを受け取る純粋関数としてテストする
- **値の正確性が最優先**: 表示値の計算式を変更する場合は、アクティビティモニタの表示と突き合わせて検証する（`swift run memorybar --print` で1回分のサンプルを標準出力に出せる）
- ページサイズは `vm_kernel_page_size` を使う（`vm_statistics64` のカウントはカーネルページ単位。Apple Silicon は 16KB。4096 をハードコードしない）
- **Mach ポート規律**: `mach_host_self()` 等で得た送信権は、**同一スコープの `defer`** で必ず `mach_port_deallocate` する。解放しないと上限（65535）まで蓄積する規約違反になる。回帰テスト `MemorySamplerTests` は成功パスしか通らないため、各 return 直前で解放する形にすると早期 return のリークを検出できなくなる
- メモリプレッシャーの状態遷移は公開 API の `DispatchSource` を中心にし、非公開 sysctl を使う場合は小さな互換レイヤーへ隔離して失敗を `.unknown` として扱う
  - `DispatchSource` の `data` は**必ずイベントハンドラ内で読む**。非同期ホップ後に読むと上書き・クリアされ、正常なのに「取得不能」と誤表示する
  - **取得できなかった値を正常値（`.normal` や 0）に置換しない**。「分からないのに正常と表示する」より「分からないと表示する」方を選ぶ
  - プレッシャー周りを変更したときの手動確認: ①起動直後の表示 ②負荷を変えて通常・注意・危険の遷移 ③スリープ復帰後も約1秒間隔の更新と通知が続くか ④Idle Wake Ups が過剰に増えていないか
- 外部ライブラリを追加しない（追加が必要と考える場合は利用者に確認）
- **配布と自動アップデート**: リポジトリは private のまま、`main` への push で GitHub Actions が Universal ビルドを `latest` リリースへ公開する（`.github/workflows/release.yml`）
  - **アプリにトークンを埋め込まない**。認証は利用者の `gh` CLI に委譲する（Sparkle は appcast 取得に認証が要るため private では使わない）
  - **GUI から起動した .app は PATH を継承しない**（Finder 起動時は `/usr/bin:/bin:/usr/sbin:/sbin` のみ）。`gh` などの外部コマンドは既定パスを明示的に探索する
  - 更新判定は `make-app.sh` が Info.plist へ埋め込む `MBSourceCommit` とリリースの `targetCommitish` の比較で行う。**判定不能なときは更新を促さない**（ビルド元コミットが不明、`targetCommitish` がブランチ名など）。判定不能なまま促すと同じビルドの更新を延々と繰り返す
  - **`MenuBarExtra` のパネルはウィンドウの大きさを内容の固有サイズから決める**。`ScrollView` で包んで高さを実測・指定するとウィンドウと内容が別々に決まり、潰れたり(#41)差分が露出したり(#55)する。内容の自然な大きさに任せること
- **バージョンは Git タグ(`vX.Y.Z`)が唯一の出所**。CI が main へのマージごとにパッチ番号を進めてタグを打つ。`VERSION` のようなファイルを CI が書き換えて push する方式は、無限ループ回避やローカルとの乖離といった問題を招くため使わない
  - **未コミットの変更を含むビルドには `MBSourceCommit` へ `-dirty` を付ける**。HEAD をそのまま刻むと、実際には別物なのに「そのコミットのリリース版」を名乗ってしまう（実際にレビューで前提を誤らせた）。SHA として不正な値になるため更新判定からも自動的に外れる
  - GitHub API は**タグが既存だと `target_commitish` を無視する**ため、リリースは `edit` せず毎回タグごと作り直す。加えて差し替え直前に新バンドルの `MBSourceCommit` と `CFBundleIdentifier` を検証する（API の仕様に依存しない歯止め）
  - **差し替えは「退避 → 展開 → 削除」で置換する**。`ditto` は既存バンドルへマージするため、そのまま上書きすると旧版のファイルが残り署名シールが壊れる
  - 差し替えスクリプトは失敗時に必ず旧バンドルへロールバックし、アプリを再起動する（黙って消えるのが最悪の失敗）。ログは `~/Library/Logs/MemoryBar-update.log`
  - **インストールの同意はメニューパネルのボタン操作で取る**。メニューバー常駐（`.accessory`）アプリでは `NSAlert.runModal()` が操作を待たずに先頭ボタンの応答を返すことがあり、同意の確認手段として使えない（Issue #22 で実際に無操作のまま自動インストールされた）。更新確認とインストールは必ず分けること
  - 動作確認は `dist/MemoryBar.app/Contents/MacOS/memorybar --check-update`（インストールはしない）と `--install-update`（実際に適用する）。`swift run` では `.app` でないため更新判定まで確認できない

## 開発規約

### Issue 運用ルール
| 変更の種類 | Issue | 例 |
|-----------|-------|----|
| 機能追加・バグ修正 | **必須** | 新機能、バグ修正 |
| 小規模な改善・リファクタ | 任意（推奨） | パフォーマンス改善、コード整理 |
| chore/docs/CI/typo | 不要 | ドキュメント更新、依存更新、タイポ修正 |

- 要件にない機能を無断で追加しない（提案は歓迎、実装は利用者の確認後）
- **エージェントがIssueを作成する場合、Issue本文の最上部（先頭）に `作成者: <エージェント名>` を必ず明記**する
  - エージェント名は `<ツール名>` または `<ツール名> (<モデル名>)` で統一（例: `作成者: Claude Code` / `作成者: Codex (GPT-5)`）
  - 署名漏れに気づいた場合は別コメントを追加せず、Issue本文を編集して最上部へ追記する

### ブランチ運用
- **mainブランチへの直接プッシュは禁止**。必ずブランチを作成し、PRを経由してマージすること
- Issue あり: `feature/{issue番号}-{概要}` (例: `feature/3-add-login`)
- Issue なし: `chore/{概要}` (例: `chore/update-dependencies`)
- **`{概要}` は半角英数字とハイフンを基本にする**（URL や CI で問題が出にくい。日本語は避ける）
- **Git worktree を使う条件**: 複数ブランチを同時に触る、または現在の作業とは別の作業を新しく始めるとき。単一タスクでブランチを切り替えるだけなら通常の `git switch` でよい
  - `git worktree add` で作成（Claude Code の場合は `EnterWorktree` コマンドでも可）
  - **`.env.local` は Git 管理外のため worktree に自動コピーされない**。環境変数が必要な場合は手動でコピーすること:
    ```sh
    cp /path/to/main-repo/.env.local /path/to/worktree/.env.local
    ```

#### スタック PR とベースブランチ削除
- スタック PR には依存先 PR とマージ順を本文へ明記する
- PR をマージしてブランチを削除する前に、そのブランチを base とする未完了 PR を必ず確認する:
  ```sh
  gh pr list --state open --base <削除予定ブランチ>
  ```
- 依存 PR がある場合は、元の base ブランチを削除する前に `gh pr edit <PR番号> --base main` などで retarget する
- retarget 後は `gh pr diff <PR番号>` で意図しない差分がないことを確認し、CI を再実行・再確認してから元ブランチを削除する
- base ブランチの削除を先に行うと依存 PR が自動クローズされ、レビューと CI の履歴が分断されるため順序を逆にしない

### コミットメッセージ
- 日本語で記述
- 1行目: 変更の要約
- 空行後に詳細 (必要に応じて)
- Issue がある場合は `Closes #{issue番号}` で自動クローズ

### PR
- タイトル: 日本語OK、70文字以内
- `gh pr create` で作成
- **PR 本文の先頭（上段）に `作成者: <エージェント名>` を必ず明記**する
  - エージェント名は `<ツール名>` または `<ツール名> (<モデル名>)` で統一（例: `作成者: Claude Code` / `作成者: Codex (GPT-5)`）
- **Issue がある場合**: body に `Closes #{issue番号}` を **必ず** 含める
- **Issue がない場合**: body に変更理由と変更内容を書く（最低限このテンプレート）:
  ```markdown
  作成者: <エージェント名>

  ## 変更理由
  - 何のために / どの問題を解決するか
  ## 変更内容
  - 主な変更点
  ```
- **PRのマージ**: 利用者の指示（2026-08-11）により、当面は次の条件を**すべて**満たせばエージェントがマージまで実施してよい:
  1. CI が green であること
  2. Copilot、または作成エージェントとは独立したエージェント（別セッション・サブエージェント可）によるコードレビューが完了し、指摘に対応済みであること
  3. 未解決のレビュースレッドが 0 件であること
  利用者が「PR必須」と再宣言した時点で、マージ前に利用者の明示的な承認を得る運用（PR必須 Ruleset の再適用を含む）に戻すこと

### レビュー対応
- PRにはGitHub Copilotの自動レビューが入る
- **エージェントがPRレビュー/コメントを投稿する場合、本文の先頭（上段）に `レビュアー: <エージェント名>` を必ず明記**する
  （例: `レビュアー: Claude Code` / `レビュアー: Codex (GPT-5)`。署名漏れは別コメントではなく既存本文を編集して直す）
- レビュー指摘への修正をpushした後は、**必ず以下の2つを行う**:
  1. PRコメント欄に対応内容のサマリーを投稿する
  2. 対応した（コード修正で解消した）レビュースレッドを Resolve する。推奨 ruleset は未解決スレッドのままでもマージ可能だが、対応済みを未対応に見せないための作業規律として行う:
     ```sh
     # スレッドID一覧を取得
     gh api graphql -f query='
       { repository(owner:"<owner>",name:"<repo>"){ pullRequest(number:<PR番号>){
         reviewThreads(first:50){ nodes{ id isResolved path } } } } }'
     # 対応済みスレッドを Resolve
     gh api graphql -f query='
       mutation($id:ID!){ resolveReviewThread(input:{threadId:$id}){ thread{ id isResolved } } }' \
       -f id=<スレッドID>
     ```

### ビルド・テスト確認
- 実装後は必ず `swift build` でエラーがないことを確認する
- **push前に必ず `swift test` を実行し、全テストが pass することを確認する**

### CLIツールの注意点
- **`gh` を使う前に `gh auth status` で認証を確認する**（未認証だと `Bad credentials` で詰まる）
- `gh pr checks` の終了コード: 0=全pass / 8=保留(実行中) / それ以外=失敗
- **`|| true` を付けて失敗を握り潰さない**。終了コードを退避して分岐し、保留(8)はポーリングで待つ:
  ```sh
  checks_passed=false
  for attempt in 1 2 3 4 5 6; do
    gh pr checks <PR番号>; ec=$?
    case "$ec" in
      0)
        checks_passed=true
        break
        ;;
      8)
        if [ "$attempt" -eq 6 ]; then
          echo "CIが待機上限まで pending でした" >&2
          exit 8
        fi
        sleep 20
        ;;
      *)
        echo "失敗/認証エラー: exit=$ec" >&2
        exit "$ec"
        ;;
    esac
  done
  if [ "$checks_passed" != true ]; then
    exit 8
  fi
  ```

### GitHub Actions の更新方針
- GitHub 公式 Action は、Node.js ランタイムやセキュリティ修正を取り込むため、検証済みの最新メジャータグ（例: `actions/checkout@v6`）を使用する
- メジャーバージョンを更新した PR では、非推奨警告が消え、既存の build / test / .app 検証がすべて成功することを CI ログで確認する

