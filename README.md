# つづり（tsuzuri）

日記から始まる、友達と、その先の出会い。同性・異性どちらにも対応（仮称・仮説段階）。
設計は `docs/DESIGN.md`。

v0 は端末内だけで動くデモです。架空の書き手10人を同梱し、感想を送ると約8秒後に返事をします。
クラウド、ログイン、分析、課金、広告は入っていません。

```
lib/
  main.dart                 起動（iOS/Android は SQLite、Web はメモリ）
  src/domain/models.dart    型（Profile, DiaryEntry, Letter, Connection, SharedPage, Report）
  src/domain/rules.dart     上限・双方向の性別一致・連絡先検出・紹介の選定・写真の状態遷移
  src/data/backend.dart     UI が依存する唯一の窓口 TsuzuriBackend
  src/data/demo_backend.dart 端末内デモ実装（app_core の LocalStore に保存）
  src/data/seed.dart        架空の書き手と日記
  src/ui/                   はじめに・読む・書く・ふたり・写真の同時公開・安全メニュー・設定
test/                       ルール・デモ実装・画面遷移のテスト
functions/                  Cloud Functions（TypeScript）。サーバー側の上限・一致・写真同意・ブロックの検証
firestore.rules など          セキュリティルールとインデックス（クライアントは直接書き込まない）
prototype/web/index.html    触れる試作（単体の HTML。ブラウザで開くだけで動く）
```

このリポジトリは `app-factory-harness` ワークスペースの `services/tsuzuri` に clone して使います（`../../packages/app_core` に依存）。

```sh
cd app-factory-harness/services && git clone https://github.com/koseirving/tsuzuri
```

ワークスペース内のこのディレクトリで:

```sh
python3 ../../ops.py bootstrap-mobile tsuzuri --org com.koseirving   # ios/ android/ を生成（初回のみ）
python3 ../../scripts/flutter.py pub get
python3 ../../scripts/flutter.py analyze
python3 ../../scripts/flutter.py test --reporter expanded
python3 ../../scripts/flutter.py run -d chrome                       # Web で試す場合
```

**2026-09-30 時点で、analyze と test はまだ一度も実行していません**（作成環境に Flutter を入れられなかったため）。
コードは静的レビューのみ済み。最初の実行で出た指摘は、バックログのタスクで直してください。

## サーバー（functions/）

```sh
cd functions
npm install
npm test            # ロジックのテスト（Node 22.18 以上。TypeScript をそのまま実行）
npm run typecheck   # tsc
npx firebase-tools emulators:exec --only firestore --project demo-tsuzuri "npm --prefix functions run test:rules"
```

Firebase プロジェクトの作成とデプロイは、まだしていません（支出とアカウント作成の承認が必要です）。
CI の Flutter ジョブには、app-factory-harness を読めるトークンを `HARNESS_TOKEN` シークレットとして登録してください。
登録がないあいだ、Flutter ジョブは「スキップ」と表示されます。合格ではありません。
