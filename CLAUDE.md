# stock_app - Claude Code 向けメモ

株価分析アプリ。Flutter（フロント）＋ FastAPI on AWS Lambda（バックエンド）。
AI分析がメイン機能。

**このファイルは毎回自動で読み込まれる。短く保つこと。詳細は下のドキュメントへ。**

## コードを書く前に必ず読む

チャットを新しくするたびに書き方がばらつかないよう、**コードを変える前に下の2つを読み、それに沿って書く。**

| ドキュメント | 内容 | いつ読む |
|---|---|---|
| [docs/CODING_RULES.md](docs/CODING_RULES.md) | コーディング規約（名前の付け方・書き方・エラーの返し方・リファクタリングの決まり） | コードを1行でも変える前 |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | 基本設計（どの層に何を書くか・共通部品の一覧・「ここを変えたらここも直す」） | 新しいファイル・関数・APIを足す前 |
| [DEPLOY.md](DEPLOY.md) | デプロイ手順 | デプロイするとき |

- 規約と違う書き方が既存コードにあっても、**新しく書く部分は規約に合わせる**（既存部分の直しは別PR。CODING_RULES.md の「リファクタリング」参照）
- 規約にないことで判断に迷ったら、近くの既存コードに合わせ、作業報告で「規約に足すべきこと」として伝える
- 新しい共通部品・新しい約束ごとを作ったら、**同じPRで** CODING_RULES.md / ARCHITECTURE.md に追記する

## 作業の流れ

1. `main` から新しいブランチを切る（`fix/…` `feat/…` `perf/…` `chore/…` `docs/…`）。1つの目的につき1PR
2. 上の2つのドキュメントを読んでから実装する
3. テスト・確認コマンドを実行する（下記）
4. PRは `.github/pull_request_template.md` の見出しをすべて埋める
5. **PRのマージはしない。** マージはオーナー（mero5）がレビューしてから行う

## 構成（概要）

```
lib/            Flutter（screens / viewmodels / services / widgets / config / models / utils / theme）
backend/        FastAPI（main.py + routers/ + services/ + config/）
                → Lambda コンテナイメージ（lambda_handler.py が入口、Mangum で変換）
DynamoDB        キャッシュ・ユーザー設定・AI予測の記録
Lambda(別)      ウォッチリストの保存/取得/削除（API Gateway経由）
認証            AWS Cognito（Amplify）
```

## 踏みやすい地雷（詳しくは docs/ARCHITECTURE.md）

- **Lambda は UTC。** `datetime.now()` / `date.today()` を直接使わず `services/clock.py` を使う
- **外部APIは必ずタイムアウトを付ける。** 値は `config/timeouts.py`
- **yfinance の結果は `services/market_data.drop_empty_rows()` を通す**（日本株は最新日が空の行で返ることがある）
- **AI分析系のエラーは HTTP 200 + `{error, error_type, error_detail}`。** `classify_error()` + `error_response()` を使う
- **プロンプトを変えたら `services/technical.py` の `PROMPT_VERSION` を上げる**
- **依存ライブラリは `requirements.txt` と `requirements-lambda.txt` の両方に書く**
- 銘柄コードは3形式ある（`72030` / `7203` / `7203.T`）
- ソースの改行は **CRLF**。書き換えスクリプトを使うときは `newline=''` で読み書きする

## 確認コマンド

```bash
flutter analyze --no-pub
```

```bash
cd backend && python -m pytest
```

（`backend/tests/` がある場合）

## ローカル専用のメモ

サーバーのIPアドレス・鍵ファイルの場所など、**公開リポジトリに載せたくない情報は `CLAUDE.local.md`（Git管理外）に書く。** このファイルには書かない。
