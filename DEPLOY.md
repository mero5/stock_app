# バックエンドのデプロイ手順

`stock_app` 直下で以下を実行するだけ。

```bash
deploy.bat
```

## deploy.bat が何をしているか

| 手順 | 内容 |
|---|---|
| 1 | `backend/main.py` と `backend/requirements.txt` を転送 |
| 2 | `backend/routers/` と `backend/services/` をディレクトリごと転送 |
| 3 | `pip install -r requirements.txt` と `__pycache__` の掃除 |
| 4 | `sudo systemctl restart stockapp` でサービス再起動 |
| 5 | `systemctl is-active` と `/health` で起動確認、直近ログを表示 |

サーバー側の `.env` は転送対象に入れていないので上書きされない。

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
