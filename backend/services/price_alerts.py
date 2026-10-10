# ===================================================
# 株価アラート（指定の株価になったらプッシュ通知）
#
# ・登録・一覧・変更・削除：routers/price_alerts.py から呼ぶ（price_alerts テーブル）
# ・判定：EventBridge Scheduler が5分おきに Lambda を起こし（lambda_handler.py）、
#   run_price_alert_check() が「有効なアラート」を全部読んで、市場が開いている銘柄だけ株価を取り、
#   条件を満たしたものを services/push.py で通知する
#
# 同じアラートは1日1回まで（その市場の日付で数える。米国株は日本時間の夜〜朝にまたがるため）。
# 「1回だけ」のアラートは、通知したら自動で OFF にする。
# 設定値は config/price_alerts.py
# ===================================================

import re
import uuid
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

from boto3.dynamodb.conditions import Attr, Key
from botocore.exceptions import ClientError

from config.price_alerts import (
    CONDITION_CHANGE_DOWN,
    CONDITION_CHANGE_UP,
    CONDITION_PRICE_ABOVE,
    CONDITION_PRICE_BELOW,
    CONDITIONS,
    MAX_ALERTS_PER_USER,
    MAX_CHANGE_PCT,
    PRICE_ALERT_MAX_WORKERS,
    REPEAT_DAILY,
    REPEAT_ONCE,
    REPEATS,
)
from services.cache import _from_decimal, _to_decimal, price_alerts_table
from services.clock import now_jst
from services.market_hours import is_market_open, market_date
from services.stock_code import is_jp_code

# 米国株のティッカー（英字で始まる。BRK-B・BRK.B なども通す）
_US_TICKER = re.compile(r"^[A-Z][A-Z0-9.\-]{0,9}$")


class AlertLimitError(Exception):
    """1人あたりの上限（MAX_ALERTS_PER_USER）を超えて登録しようとした"""


# ===================================================
# 入力のチェック
# ===================================================
def _to_number(value) -> float | None:
    try:
        number = float(value)
    except (TypeError, ValueError):
        return None
    return number if number == number else None  # NaN を除く


def validate_fields(body: dict, partial: bool = False) -> tuple[dict, str | None]:
    """
    アプリから受け取った条件をチェックして、保存する形にする

    戻り値: (保存する項目, エラーメッセージ)。エラーが無ければ None
    [partial] True のときは、渡された項目だけをチェックする（変更用）
    """
    fields = {}
    if not partial or "code" in body:
        code = str(body.get("code") or "").strip().upper()
        if not (is_jp_code(code) or _US_TICKER.match(code)):
            return {}, "銘柄コードが正しくありません"
        fields["code"] = code
        fields["name"] = str(body.get("name") or code).strip()[:100]

    if not partial or "condition" in body or "target" in body:
        condition = body.get("condition")
        if condition not in CONDITIONS:
            return {}, "条件の種類が正しくありません"
        target = _to_number(body.get("target"))
        if target is None or target <= 0:
            return {}, "金額（または%）は0より大きい数字を入れてください"
        if condition in (CONDITION_CHANGE_UP, CONDITION_CHANGE_DOWN) and target > MAX_CHANGE_PCT:
            return {}, f"前日比は{MAX_CHANGE_PCT}%以下で入れてください"
        fields["condition"] = condition
        fields["target"] = target

    if not partial or "repeat" in body:
        repeat = body.get("repeat", REPEAT_DAILY)
        if repeat not in REPEATS:
            return {}, "繰り返しの設定が正しくありません"
        fields["repeat"] = repeat

    if "enabled" in body:
        if not isinstance(body["enabled"], bool):
            return {}, "ON/OFF の値が正しくありません"
        fields["enabled"] = body["enabled"]
    return fields, None


# ===================================================
# 登録・一覧・変更・削除
# ===================================================
def list_alerts(user_id: str) -> list[dict]:
    """そのユーザーのアラート（作った順）"""
    res = price_alerts_table.query(KeyConditionExpression=Key("userId").eq(user_id))
    items = [_from_decimal(item) for item in res.get("Items", [])]
    return sorted(items, key=lambda a: a.get("created_at", ""))


def create_alert(user_id: str, fields: dict) -> dict:
    """アラートを登録して、保存した内容を返す。上限を超えるなら AlertLimitError"""
    if len(list_alerts(user_id)) >= MAX_ALERTS_PER_USER:
        raise AlertLimitError(f"アラートは{MAX_ALERTS_PER_USER}件まで登録できます")
    item = {
        "userId": user_id,
        "alert_id": uuid.uuid4().hex[:12],
        "enabled": True,
        "repeat": REPEAT_DAILY,
        **fields,
        "last_notified_date": "",
        "created_at": now_jst().isoformat(),
    }
    price_alerts_table.put_item(Item=_to_decimal(item))
    return item


def update_alert(user_id: str, alert_id: str, fields: dict) -> bool:
    """
    アラートを変更する。見つからなければ False

    条件・金額を変えたとき、OFF から ON に戻したときは「今日はもう通知した」の記録を消す
    （変えた条件でその日のうちに通知できるように）
    """
    if not fields:
        return True
    updates = dict(fields)
    if {"condition", "target"} & fields.keys() or fields.get("enabled") is True:
        updates["last_notified_date"] = ""
    names = {f"#k{i}": k for i, k in enumerate(updates)}
    values = {f":v{i}": v for i, v in enumerate(updates.values())}
    expression = "SET " + ", ".join(f"#k{i} = :v{i}" for i in range(len(updates)))
    try:
        price_alerts_table.update_item(
            Key={"userId": user_id, "alert_id": alert_id},
            UpdateExpression=expression,
            ExpressionAttributeNames=names,
            ExpressionAttributeValues=_to_decimal(values),
            # 無いアラートを新しく作ってしまわないように
            ConditionExpression="attribute_exists(alert_id)",
        )
    except ClientError as e:
        if e.response.get("Error", {}).get("Code") == "ConditionalCheckFailedException":
            return False
        raise
    return True


def delete_alert(user_id: str, alert_id: str) -> None:
    price_alerts_table.delete_item(Key={"userId": user_id, "alert_id": alert_id})


# ===================================================
# 判定
# ===================================================
def is_triggered(alert: dict, quote: dict) -> bool:
    """株価（quote：/stock/price と同じ形）がアラートの条件を満たしていれば True"""
    condition, target = alert.get("condition"), _to_number(alert.get("target"))
    price, change_pct = _to_number(quote.get("price")), _to_number(quote.get("change_pct"))
    if target is None:
        return False
    if condition == CONDITION_PRICE_ABOVE:
        return price is not None and price >= target
    if condition == CONDITION_PRICE_BELOW:
        return price is not None and price <= target
    if condition == CONDITION_CHANGE_UP:
        return change_pct is not None and change_pct >= target
    if condition == CONDITION_CHANGE_DOWN:
        return change_pct is not None and change_pct <= -target
    return False


def format_price(code: str, price: float) -> str:
    """表示用の株価（日本株は「3,012円」、米国株は「$123.45」）"""
    if is_jp_code(code):
        text = f"{price:,.0f}" if float(price).is_integer() else f"{price:,.1f}"
        return f"{text}円"
    return f"${price:,.2f}"


def notification_text(alert: dict, quote: dict) -> tuple[str, str]:
    """通知のタイトルと本文"""
    code, name = alert["code"], alert.get("name") or alert["code"]
    display_code = code[:4] if is_jp_code(code) else code
    title = f"{name}（{display_code}）"
    price, change_pct = quote.get("price"), quote.get("change_pct")
    now_text = f"現在 {format_price(code, price)}" if price is not None else ""
    if change_pct is not None:
        now_text += f"（前日比 {change_pct:+.2f}%）"
    target = float(alert["target"])
    condition = alert["condition"]
    if condition == CONDITION_PRICE_ABOVE:
        body = f"株価が {format_price(code, target)} 以上になりました。{now_text}"
    elif condition == CONDITION_PRICE_BELOW:
        body = f"株価が {format_price(code, target)} 以下になりました。{now_text}"
    elif condition == CONDITION_CHANGE_UP:
        body = f"前日比 +{target:g}% 以上に上がりました。{now_text}"
    else:
        body = f"前日比 -{target:g}% 以下に下がりました。{now_text}"
    return title, body


def scan_enabled_alerts() -> list[dict]:
    """全ユーザーの有効なアラート（ページングして全部読む）"""
    items, kwargs = [], {"FilterExpression": Attr("enabled").eq(True)}
    while True:
        res = price_alerts_table.scan(**kwargs)
        items.extend(_from_decimal(item) for item in res.get("Items", []))
        if "LastEvaluatedKey" not in res:
            return items
        kwargs["ExclusiveStartKey"] = res["LastEvaluatedKey"]


def mark_notified(alert: dict, notified_date: str, price) -> None:
    """通知した記録を残す。「1回だけ」なら OFF にする"""
    try:
        price_alerts_table.update_item(
            Key={"userId": alert["userId"], "alert_id": alert["alert_id"]},
            UpdateExpression="SET last_notified_date = :d, last_notified_price = :p, enabled = :e",
            ExpressionAttributeValues=_to_decimal({
                ":d": notified_date,
                ":p": price,
                ":e": alert.get("repeat") != REPEAT_ONCE,
            }),
            ConditionExpression="attribute_exists(alert_id)",
        )
    except Exception as e:
        print(f"アラートの通知記録エラー {alert.get('alert_id')}: {e}")


def run_price_alert_check(fetch_price, send, now_utc: datetime | None = None) -> dict:
    """
    有効なアラートを全部判定して、条件を満たしたものを通知する（5分おきに呼ばれる）

    [fetch_price] 銘柄コード → {price, change_pct, ...}（routers/stock.get_stock_price）
    [send]        (userId, title, body, data) → 届いた台数（services/push.send_to_user）
    戻り値: 件数のまとめ（ログ用）
    """
    now_utc = now_utc or datetime.now(timezone.utc)
    alerts = [
        a for a in scan_enabled_alerts()
        if is_market_open(a["code"], now_utc)
        and a.get("last_notified_date") != market_date(a["code"], now_utc)
    ]
    codes = sorted({a["code"] for a in alerts})
    with ThreadPoolExecutor(max_workers=PRICE_ALERT_MAX_WORKERS) as executor:
        quotes = dict(zip(codes, executor.map(lambda c: _safe_fetch(fetch_price, c), codes)))

    notified = 0
    for alert in alerts:
        quote = quotes.get(alert["code"]) or {}
        if not is_triggered(alert, quote):
            continue
        title, body = notification_text(alert, quote)
        data = {"type": "price_alert", "code": alert["code"], "name": alert.get("name", ""), "alert_id": alert["alert_id"]}
        try:
            sent = send(alert["userId"], title, body, data)
        except Exception as e:
            print(f"アラートの通知エラー {alert['alert_id']}: {e}")
            continue
        # 端末が1台も無い（通知を許可していない）ときは記録しない。許可したら次の判定で届く
        if sent:
            mark_notified(alert, market_date(alert["code"], now_utc), quote.get("price"))
            notified += 1
    summary = {"alerts": len(alerts), "codes": len(codes), "notified": notified}
    print(f"[price_alert] {summary}")
    return summary


def _safe_fetch(fetch_price, code: str) -> dict:
    try:
        return fetch_price(code) or {}
    except Exception as e:
        print(f"アラートの株価取得エラー {code}: {e}")
        return {}
