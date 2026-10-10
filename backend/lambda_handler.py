# ===================================================
# Lambda エントリポイント
# FastAPI アプリ（main.py）を Mangum で Lambda 用に変換する
#
# 同じ関数を2つの用途で使う：
#   ・アプリからの HTTP（Function URL）       → Mangum → FastAPI
#   ・EventBridge Scheduler の5分おきの合図   → 株価アラートの判定（services/price_alerts.py）
#     スケジュールの入力（Input）に {"task": "price_alert_check"} を入れて見分ける。
#     Mangum は HTTP 以外のイベントを受け取るとエラーになるので、先に振り分ける
# ===================================================

from mangum import Mangum

from config.price_alerts import PRICE_ALERT_TASK
from main import app
from routers.stock import get_stock_price
from services.price_alerts import run_price_alert_check
from services.push import send_to_user

# lifespan="auto" で main.py の startup（銘柄マスタ取得）がコールドスタート時に走る
_mangum = Mangum(app, lifespan="auto")


def handler(event, context):
    if isinstance(event, dict) and event.get("task") == PRICE_ALERT_TASK:
        # 株価はホーム画面と同じ /stock/price の処理で取る（日本株の空の行の除去なども同じになる）
        return run_price_alert_check(get_stock_price, send_to_user)
    return _mangum(event, context)
