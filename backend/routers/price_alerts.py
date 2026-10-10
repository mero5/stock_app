# ===================================================
# 株価アラート・プッシュ通知の API
#
#   GET  /alerts             自分のアラートの一覧
#   POST /alerts             アラートを登録（1人 MAX_ALERTS_PER_USER 件まで）
#   POST /alerts/update      アラートの変更（ON/OFF・条件・金額・繰り返し）
#   POST /alerts/delete      アラートの削除
#   POST /push/token         この端末の通知の宛先（FCM トークン）を登録（アプリが起動のたびに送る）
#   POST /push/token/delete  この端末の宛先を削除（ログアウトしたとき）
#   POST /push/test          自分の全端末にテスト通知を送る
#
# 新しく作った API なので、古いアプリ（トークンを送らない）を考えなくてよい。
# ほかの API と違い、最初からログインのトークンを必須にし、userId はトークンの持ち主を使う
# （リクエストの userId は信じない。他人の端末に通知を送られないように）。
# 処理の本体は services/price_alerts.py・services/push.py
# ===================================================

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse

from services import push
from services.price_alerts import (
    AlertLimitError,
    create_alert,
    delete_alert,
    list_alerts,
    update_alert,
    validate_fields,
)

router = APIRouter()

TEST_TITLE = "テスト通知"
TEST_BODY = "株アプリからの通知は、このように届きます。"


def _require_user(request: Request) -> str:
    """確かめたトークンの持ち主（main.py のミドルウェアが request.state.auth に入れる）。無ければ空文字"""
    auth = getattr(request.state, "auth", None)
    if auth is not None and auth.status == "valid" and auth.user_id:
        return auth.user_id
    return ""


def _unauthorized() -> JSONResponse:
    return JSONResponse(status_code=401, content={"error": "ログインが必要です"})


async def _json_body(request: Request) -> dict:
    try:
        body = await request.json()
    except Exception:
        return {}
    return body if isinstance(body, dict) else {}


@router.get("/alerts")
def get_alerts(request: Request):
    user_id = _require_user(request)
    if not user_id:
        return _unauthorized()
    try:
        return {"alerts": list_alerts(user_id)}
    except Exception as e:
        print(f"アラート一覧エラー: {e}")
        return {"error": "アラートを読み込めませんでした", "alerts": []}


@router.post("/alerts")
async def post_alert(request: Request):
    user_id = _require_user(request)
    if not user_id:
        return _unauthorized()
    fields, error = validate_fields(await _json_body(request))
    if error:
        return {"error": error}
    try:
        return {"alert": create_alert(user_id, fields)}
    except AlertLimitError as e:
        return {"error": str(e)}
    except Exception as e:
        print(f"アラート登録エラー: {e}")
        return {"error": "アラートを登録できませんでした"}


@router.post("/alerts/update")
async def post_alert_update(request: Request):
    user_id = _require_user(request)
    if not user_id:
        return _unauthorized()
    body = await _json_body(request)
    alert_id = str(body.get("alert_id") or "")
    if not alert_id:
        return {"error": "alert_id が必要です"}
    fields, error = validate_fields(body, partial=True)
    if error:
        return {"error": error}
    # 銘柄は変えられない（変えるときは削除して作り直す）
    fields.pop("code", None)
    fields.pop("name", None)
    try:
        if not update_alert(user_id, alert_id, fields):
            return {"error": "アラートが見つかりません"}
        return {"success": True}
    except Exception as e:
        print(f"アラート変更エラー: {e}")
        return {"error": "アラートを変更できませんでした"}


@router.post("/alerts/delete")
async def post_alert_delete(request: Request):
    user_id = _require_user(request)
    if not user_id:
        return _unauthorized()
    alert_id = str((await _json_body(request)).get("alert_id") or "")
    if not alert_id:
        return {"error": "alert_id が必要です"}
    try:
        delete_alert(user_id, alert_id)
        return {"success": True}
    except Exception as e:
        print(f"アラート削除エラー: {e}")
        return {"error": "アラートを削除できませんでした"}


@router.post("/push/token")
async def post_push_token(request: Request):
    user_id = _require_user(request)
    if not user_id:
        return _unauthorized()
    body = await _json_body(request)
    token = str(body.get("token") or "")
    if not token:
        return {"error": "token が必要です"}
    try:
        push.save_token(user_id, token, str(body.get("platform") or "ios"))
        return {"success": True}
    except Exception as e:
        print(f"通知の宛先の登録エラー: {e}")
        return {"error": "通知の設定を保存できませんでした"}


@router.post("/push/token/delete")
async def post_push_token_delete(request: Request):
    user_id = _require_user(request)
    if not user_id:
        return _unauthorized()
    token = str((await _json_body(request)).get("token") or "")
    if not token:
        return {"error": "token が必要です"}
    try:
        push.delete_token(user_id, token)
        return {"success": True}
    except Exception as e:
        print(f"通知の宛先の削除エラー: {e}")
        return {"error": "通知の設定を削除できませんでした"}


@router.post("/push/test")
def post_push_test(request: Request):
    user_id = _require_user(request)
    if not user_id:
        return _unauthorized()
    try:
        sent = push.send_to_user(user_id, TEST_TITLE, TEST_BODY, {"type": "test"})
    except Exception as e:
        print(f"テスト通知エラー: {e}")
        return {"error": "テスト通知を送れませんでした"}
    if sent == 0:
        return {"error": "通知を送れる端末がありません。iPhone の設定で通知を許可してから、アプリを開き直してください"}
    return {"success": True, "sent": sent}
