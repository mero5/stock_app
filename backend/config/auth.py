# ===================================================
# ログイン（Cognito）のトークン確認の設定
#
# アプリは Cognito でログインしている。リクエストの Authorization ヘッダーに
# Cognito のアクセストークンを付けてもらい、バックエンドで本物か確かめる。
# 以前は何も確かめておらず、公開リポジトリに載っている URL さえ分かれば、
# 誰でも AI 系の API を呼べた（OpenAI の料金がかかる）うえ、
# 他人の userId を名乗ってプロファイルや成績を読み書きできた（課題 K-06）。
#
# 段階的に入れる：
#   1. AUTH_ENFORCE = False … 確かめてログに出すだけ（拒否しない）
#      古いアプリ（トークンを送らない）も今までどおり使える。
#      CloudWatch Logs の "[auth]" の行で、トークン付きの割合を見る
#   2. ほとんどがトークン付きになったら、AI 系とユーザーデータの API で拒否する（別PR）
#
# ユーザープールIDとアプリクライアントIDは秘密の値ではない
# （アプリの lib/amplifyconfiguration.dart にも入っている）。
# ===================================================

import os

COGNITO_REGION = os.getenv("COGNITO_REGION", "ap-northeast-1")
COGNITO_USER_POOL_ID = os.getenv("COGNITO_USER_POOL_ID", "ap-northeast-1_tixdcoGxf")
COGNITO_APP_CLIENT_ID = os.getenv("COGNITO_APP_CLIENT_ID", "16220l3a1h4fntitodi8l42d74")

COGNITO_ISSUER = f"https://cognito-idp.{COGNITO_REGION}.amazonaws.com/{COGNITO_USER_POOL_ID}"
COGNITO_JWKS_URL = f"{COGNITO_ISSUER}/.well-known/jwks.json"

# Cognito の公開鍵（JWKS）を取りに行くときのタイムアウト（秒）
JWKS_TIMEOUT_SEC = 5

# True にすると、トークンが無い・正しくないリクエストを拒否する（段階2）
AUTH_ENFORCE = False
