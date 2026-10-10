# ===================================================
# プッシュ通知（Firebase Cloud Messaging：FCM）
#
# 送る流れ：
#   1. サービスアカウントの鍵で Google の認証トークン（1時間有効）を取る
#   2. FCM の HTTP v1 API（messages:send）に、端末ごとの宛先（FCM トークン）を指定して送る
#   3. FCM が Apple の APNs を通して iPhone に届ける
#
# 端末の宛先（FCM トークン）はアプリが起動のたびに /push/token で送ってくる（push_tokens テーブル）。
# 再インストール・機種変更で古いトークンは使えなくなるので、FCM が「もう無い」と返したら消す。
#
# firebase-admin（Firebase の公式ライブラリ）は大きいので使わず、
# 既に入っている google-auth と requests で HTTP v1 API を直接呼ぶ。
# ===================================================

import json
import time

import boto3
import requests
from boto3.dynamodb.conditions import Key

from config.price_alerts import (
    FCM_PROJECT_ID,
    FCM_SCOPE,
    FCM_SERVICE_ACCOUNT_PARAM,
    PUSH_TOKEN_TTL_DAYS,
)
from config.timeouts import FCM_TIMEOUT_SEC
from services.cache import push_tokens_table
from services.clock import now_jst

# FCM が「このトークンはもう使えない」と返すときのエラー（このときはトークンを消す）
#   UNREGISTERED : アプリが消された・トークンが古い
# INVALID_ARGUMENT はメッセージ側の誤りでも返るので、トークンは消さない
_DEAD_TOKEN_ERRORS = ("UNREGISTERED",)

# 認証情報はコンテナが生きている間使い回す（期限が近づいたら google-auth が取り直す）
_credentials = None


# ===================================================
# 端末の宛先（FCM トークン）の保存・取得・削除
# ===================================================
def save_token(user_id: str, token: str, platform: str = "ios") -> None:
    """端末の宛先を保存する。同じトークンなら更新日時と期限だけ延びる"""
    push_tokens_table.put_item(Item={
        "userId": user_id,
        "token": token,
        "platform": platform,
        "updated_at": now_jst().isoformat(),
        # DynamoDB の TTL（UNIX時刻の秒）。しばらく起動されていない端末のトークンは自動で消える
        "ttl": int(time.time()) + PUSH_TOKEN_TTL_DAYS * 24 * 60 * 60,
    })


def delete_token(user_id: str, token: str) -> None:
    """端末の宛先を消す（ログアウトしたとき・FCM が使えないと返したとき）"""
    push_tokens_table.delete_item(Key={"userId": user_id, "token": token})


def get_tokens(user_id: str) -> list[str]:
    """そのユーザーの全端末の宛先"""
    res = push_tokens_table.query(KeyConditionExpression=Key("userId").eq(user_id))
    return [item["token"] for item in res.get("Items", [])]


# ===================================================
# FCM への送信
# ===================================================
def _load_service_account() -> dict:
    """SSM パラメータストアからサービスアカウントの鍵（JSON）を読む"""
    ssm = boto3.client("ssm", region_name="ap-northeast-1")
    res = ssm.get_parameter(Name=FCM_SERVICE_ACCOUNT_PARAM, WithDecryption=True)
    return json.loads(res["Parameter"]["Value"])


def _access_token() -> str:
    """FCM を呼ぶための Google の認証トークン"""
    global _credentials
    # 送るときにだけ使うので、ここで読み込む（ローカルでテストするときに入っていなくても動くように）
    from google.auth.transport.requests import Request as GoogleRequest
    from google.oauth2 import service_account

    if _credentials is None:
        _credentials = service_account.Credentials.from_service_account_info(
            _load_service_account(), scopes=[FCM_SCOPE]
        )
    if not _credentials.valid:
        session = requests.Session()
        _credentials.refresh(GoogleRequest(session=session))
    return _credentials.token


def build_message(token: str, title: str, body: str, data: dict | None = None) -> dict:
    """FCM の HTTP v1 API に送る中身"""
    return {
        "message": {
            "token": token,
            "notification": {"title": title, "body": body},
            # アプリが通知をタップされたときに読む値（文字列だけ送れる）
            "data": {k: str(v) for k, v in (data or {}).items()},
            "apns": {"payload": {"aps": {"sound": "default"}}},
        }
    }


def is_dead_token_error(response: requests.Response) -> bool:
    """FCM の応答が「このトークンはもう使えない」なら True"""
    if response.status_code not in (400, 404):
        return False
    try:
        details = response.json().get("error", {}).get("details", [])
    except ValueError:
        return False
    return any(d.get("errorCode") in _DEAD_TOKEN_ERRORS for d in details)


def send_to_token(token: str, title: str, body: str, data: dict | None = None) -> str:
    """
    1台に送る。戻り値は "sent"（送れた）/ "dead"（トークンが使えない）/ "error"（その他の失敗）
    """
    if not FCM_PROJECT_ID:
        print("プッシュ通知エラー: FCM_PROJECT_ID が未設定")
        return "error"
    url = f"https://fcm.googleapis.com/v1/projects/{FCM_PROJECT_ID}/messages:send"
    try:
        response = requests.post(
            url,
            headers={"Authorization": f"Bearer {_access_token()}"},
            json=build_message(token, title, body, data),
            timeout=FCM_TIMEOUT_SEC,
        )
    except Exception as e:
        print(f"プッシュ通知エラー: {e}")
        return "error"
    if response.ok:
        return "sent"
    if is_dead_token_error(response):
        return "dead"
    print(f"プッシュ通知エラー: {response.status_code} {response.text[:300]}")
    return "error"


def send_to_user(user_id: str, title: str, body: str, data: dict | None = None) -> int:
    """
    そのユーザーの全端末に送る。届けられた台数を返す（0なら誰にも届いていない）

    使えなくなったトークンは、ここで消す。
    """
    sent = 0
    for token in get_tokens(user_id):
        result = send_to_token(token, title, body, data)
        if result == "sent":
            sent += 1
        elif result == "dead":
            print(f"使えないトークンを削除: userId={user_id}")
            try:
                delete_token(user_id, token)
            except Exception as e:
                print(f"トークン削除エラー: {e}")
    return sent
