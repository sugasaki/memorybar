# TrueMem — AI エージェント向けガイド

このリポジトリで作業するすべての AI エージェント向けのガイド（特定製品に依存せず、`AGENTS.md` を読むエージェントすべてが対象。Claude Code / Codex / opencode / GLM / Cursor / Gemini など）。
**このファイルが正本**。`CLAUDE.md` は Claude Code 用の参照スタブで、中身はここに集約する。

## プロジェクト概要
TrueMem — macOS のメニューバーに常駐し、メモリの残量・使用量をリアルタイム表示するネイティブアプリ。名前は「既存の類似アプリのような乖離のない、真の(true)メモリ値を表示する」ことに由来する。
**アクティビティモニタと同じデータソース（Mach API `host_statistics64`）・同じ計算式**を使い、既存の類似アプリのような乖離のない正確な値を表示することが最重要の要件。

- 使用済みメモリ = アプリメモリ（internal − purgeable）+ 確保済み（wired）+ 圧縮（compressor）
- 残容量 = 物理メモリ合計（`hw.memsize`）− 使用済みメモリ
- メニューバー常時表示は 残容量GB / 使用量GB / 使用率% を設定で切替可能
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
scripts/make-app.sh    # 配布用 .app バンドルを dist/ に生成
```

## ファイル構成
- `Package.swift` — SPM マニフェスト
- `Sources/TrueMem/`
  - `App.swift` — エントリポイント（`MenuBarExtra`・アクセサリ化）
  - `MemorySampler.swift` — Mach / sysctl からの計測（副作用はここに隔離）
  - `MemorySnapshot.swift` — 計測値から使用量・残量を導出する純粋ロジック
  - `DisplayMode.swift` — メニューバー表示モードとフォーマット
  - `MenuContentView.swift` — クリック時の詳細パネル
- `Tests/TrueMemTests/` — ユニットテスト（純粋ロジック + 実機サンプリング・Mach ポートリーク回帰）
- `scripts/make-app.sh` — .app バンドル生成スクリプト

## 開発パターン
- **計算ロジックと計測を分離する**: Mach API 呼び出し（`MemorySampler`）と数値の導出（`MemorySnapshot`）を分け、導出側は生のページカウントを受け取る純粋関数としてテストする
- **値の正確性が最優先**: 表示値の計算式を変更する場合は、アクティビティモニタの表示と突き合わせて検証する（`swift run truemem --print` で1回分のサンプルを標準出力に出せる）
- ページサイズは `host_page_size` で取得する（Apple Silicon は 16KB。4096 をハードコードしない）
- **Mach ポート規律**: `mach_host_self()` 等で得た送信権は、同一スコープの `defer` で必ず `mach_port_deallocate` する。常駐アプリのためリークは蓄積する（回帰テスト `MemorySamplerTests` が参照数の増加を検出する）
- 外部ライブラリを追加しない（追加が必要と考える場合は利用者に確認）

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
  for i in 1 2 3 4 5 6; do
    gh pr checks <PR番号>; ec=$?
    case "$ec" in
      0) break ;;                        # 全pass → 次へ進む
      8) sleep 20 ;;                     # 実行中 → 20秒待って再確認
      *) echo "失敗/認証エラー: exit=$ec"; exit "$ec" ;;  # 中断
    esac
  done
  ```

