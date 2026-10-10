# バックエンドのデプロイ手順

> **2026-10-09 にバックエンドを EC2 から AWS Lambda（コンテナイメージ＋Function URL）へ移行した（PR #1）。**
> 現在の手順は「1. Lambda」。「2. 旧EC2」は記録として残している。`deploy.bat` は EC2 用なので、今は使わない。

## 1. Lambda（現在）

### 構成

| 項目 | 値 |
|---|---|
| 実行形態 | Lambda コンテナイメージ（`public.ecr.aws/lambda/python:3.12`） |
| 入口 | `lambda_handler.handler`（Mangum。FastAPI を Lambda のイベントで動かす） |
| 公開 | Lambda Function URL（アプリの `lib/config/constants.dart` の `backendUrl`） |
| 依存 | `backend/requirements-lambda.txt` |
| APIキー | Lambda の環境変数（`JQUANTS_API_KEY` / `YOUTUBE_API_KEY` / `GEMINI_API_KEY` / `OPENAI_API_KEY`）。`.env` はイメージに入れない（`.dockerignore`） |
| ECR リポジトリ名 | `stock-backend`（`448161423247.dkr.ecr.ap-northeast-1.amazonaws.com/stock-backend`） |
| Lambda 関数名 | `stock-backend`（x86_64・メモリ 1024MB・タイムアウト 300秒。2026-10-10 確認） |
| イメージのタグ | `v1`・`v2`・`v3` …と1つずつ上げる（前の版を残して、すぐ戻せるようにする）。2026-10-10 時点で `v3` が本番 |
| アカウントの同時実行数の上限 | 10（2026-10-10 確認） |

### 手順

`backend/` をビルドコンテキストにしてイメージを作り、ECR に push して Lambda を更新する。

```bash
# 変数（TAG は前回より1つ上げる。前の版はそのまま残る）
ACCOUNT_ID=448161423247
REGION=ap-northeast-1
REPO=stock-backend
FUNC=stock-backend
TAG=v4
IMAGE=$ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO:$TAG

# 1. ECR にログイン
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# 2. ビルド（Lambda は x86_64 / arm64 のどちらで作ったかに合わせる）
docker build --platform linux/amd64 --provenance=false -t $IMAGE backend

# 3. push
docker push $IMAGE

# 4. Lambda のイメージを更新して、反映を待つ
aws lambda update-function-code --function-name $FUNC --image-uri $IMAGE --region $REGION
aws lambda wait function-updated --function-name $FUNC --region $REGION

# 5. 動作確認
curl -s https://<Function URL>/health
```

- **元に戻すとき**：前のタグ（例 `v2`）を指定して `aws lambda update-function-code` を実行する
- **push の前に、イメージの中で起動できるか確かめる**：`docker run --rm --entrypoint python -e OPENAI_API_KEY=dummy $IMAGE -c "import main"`（読み込みに失敗するイメージを出さないため）
- **デプロイ直後の J-Quants**：新しいコンテナが銘柄マスタを取りに行く。無料プランは1分5回までなので、取りに行くのは「取得中」の札を取れた1コンテナだけ（#52）。数分たっても `/health` が `jquants: error` のときは CloudWatch Logs で `429` を確認する
- AWS CLI のログインは `aws login`（初回はリージョンに `ap-northeast-1` を入れる）。Git Bash でロググループ名を指定するときは `MSYS_NO_PATHCONV=1` を付ける（`/aws/lambda/…` が Windows のパスに書き換えられるため）
- `--provenance=false` を付けないと、Docker のバージョンによっては Lambda が受け付けない形式のイメージになる
- `backend/` に新しいフォルダ（`config/` など）を足しても、Dockerfile は `COPY .` なので自動で入る

### 確認しておく Lambda の設定

| 設定 | 推奨 | 理由 |
|---|---|---|
| タイムアウト | 60〜120 秒 | 15分（上限）にしておくと、外部APIで詰まったときに15分待ってから失敗する。短くしておけば早く失敗してログで原因を追える。アプリは AI 系を120秒で打ち切る |
| メモリ | 1024 MB 以上 | pandas・numpy・yfinance を読み込む。Lambda はメモリに比例して CPU も増える |
| 実行ロール | DynamoDB の `market_cache` / `stock_cache` / `user_profiles` / `ai_predictions` への読み書き | |
| 環境変数 | 上の4つのAPIキー | |

### ログ

CloudWatch Logs のロググループ `/aws/lambda/<関数名>`。

```bash
aws logs tail /aws/lambda/<関数名> --follow --region ap-northeast-1
```

## 2. 旧EC2（〜2026-10-09。記録）

以下は EC2 で運用していたときの手順と経緯。


`stock_app` 直下で以下を実行するだけ。

```bash
deploy.bat
```

## deploy.bat が何をしているか

| 手順 | 内容 |
|---|---|
| 1 | `backend/main.py` と `backend/requirements.txt` を転送 |
| 2 | **`backend/` 配下のサブディレクトリを自動検出して転送**（`__pycache__` と `venv` は除外） |
| 3 | `pip install -r requirements.txt` と `__pycache__` の掃除 |
| 4 | **起動テスト（`python -c "import main"`）** |
| 5 | `sudo systemctl restart stockapp` でサービス再起動 |
| 6 | `systemctl is-active` と `/health` で起動確認、直近ログを表示 |

サーバー側の `.env` は転送対象に入れていないので上書きされない。

### 手順2：サブディレクトリの自動検出

`routers/` `services/` `config/` などをハードコードせず、`for /d` で自動的に拾う。

> **なぜこうしたか**：以前は `routers/` と `services/` を名前で指定していたため、
> 新しく `config/` を追加したときに転送されず、
> `ModuleNotFoundError: No module named 'config'` でサービスが起動不能になった。
> ディレクトリを追加するたびに deploy.bat を直す必要がある作りは事故のもとなので、自動検出にしている。

### 手順4：起動テスト（重要）

再起動する**前に**サーバー上で `import main` を実行し、失敗したらそこでデプロイを中止する。

```
import に失敗
     ↓
「IMPORT FAILED」を表示して終了（exit 1）
     ↓
稼働中のサービスには一切触れない  ← 旧バージョンのまま動き続ける
```

`stockapp.service` は `Restart=always` なので、壊れたコードを入れて再起動すると
**5秒ごとに起動失敗を繰り返す状態**になり、サービスが完全に停止する。
それを防ぐための安全装置。

## サーバー構成

| 項目 | 値 |
|---|---|
| ホスト | `ubuntu@13.114.75.49` |
| 配置先 | `/home/ubuntu/stock_backend` |
| Python仮想環境 | `/home/ubuntu/stock_backend/venv` |
| サービス | **systemd の `stockapp.service`**（`Restart=always`・自動起動有効） |
| ポート | 8000 |
| ログ | journald（`sudo journalctl -u stockapp -f`） |

`Restart=always` なので、`kill` や `pkill` でプロセスを落としても systemd が5秒後に自動で復活させる。**停止・再起動は必ず `systemctl` を使うこと。**

ログをリアルタイムで見る:

```bash
ssh -i "C:\Users\s_mor\Downloads\keypea.pem" ubuntu@13.114.75.49 "sudo journalctl -u stockapp -f"
```

再起動だけしたい:

```bash
ssh -i "C:\Users\s_mor\Downloads\keypea.pem" ubuntu@13.114.75.49 "sudo systemctl restart stockapp"
```

## 旧 deploy.bat の問題（`deploy.bat.bak` に退避済み）

### 1. `routers/` と `services/` を転送していなかった

`main.py` と `requirements.txt` しか送っていないため、ルーターやサービス層の修正は永久に反映されなかった。

### 2. 再起動処理が機能していなかった

`pkill -f uvicorn` → `nohup uvicorn ... &` という手順だったが、uvicorn は systemd 管理下にあるため実際にはこうなっていた。

```
pkill でプロセスを落とす
     ↓
systemd が5秒後に自動で再起動   ← 実際に反映していたのはコレ
     ↓
nohup 側は後発なのでポート競合で即死
（address already in use）
```

さらに `pkill -f uvicorn` のパターンが ssh のコマンド文字列自身にもマッチするため、ssh セッションごと落ちて exit 255 になっていた。

## 注意

**`deploy.bat` は ASCII のみで書くこと。** 日本語コメントを入れると cmd.exe がパースに失敗してコマンドが壊れる（Shift-JIS でも UTF-8 でも発生する）。説明はこの `DEPLOY.md` 側に書く。
