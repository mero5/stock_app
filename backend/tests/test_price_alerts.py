# ===================================================
# 株価アラート（services/price_alerts.py・services/market_hours.py・lambda_handler.py）
#
# DynamoDB は手元の辞書で動く偽物（MemoryTable）に差し替える。株価・通知も偽物を渡す。
# ===================================================

import os
from datetime import datetime, timezone

import pytest
from botocore.exceptions import ClientError

from config.price_alerts import MAX_ALERTS_PER_USER
from services import market_hours
from services import price_alerts as pa


class MemoryTable:
    """price_alerts テーブルの偽物（キー：userId + alert_id）"""

    def __init__(self):
        self.items = {}

    def _key(self, key):
        return (key["userId"], key["alert_id"])

    def put_item(self, Item):
        self.items[self._key(Item)] = dict(Item)

    def query(self, KeyConditionExpression):
        user_id = KeyConditionExpression.get_expression()["values"][1]
        return {"Items": [v for (u, _), v in self.items.items() if u == user_id]}

    def scan(self, **kwargs):
        return {"Items": [v for v in self.items.values() if v.get("enabled") is True]}

    def update_item(self, Key, UpdateExpression, ExpressionAttributeValues,
                    ConditionExpression=None, ExpressionAttributeNames=None):
        k = self._key(Key)
        if k not in self.items:
            raise ClientError({"Error": {"Code": "ConditionalCheckFailedException"}}, "UpdateItem")
        names = ExpressionAttributeNames or {}
        for part in UpdateExpression.removeprefix("SET ").split(", "):
            name, value = (s.strip() for s in part.split("="))
            self.items[k][names.get(name, name)] = ExpressionAttributeValues[value]

    def delete_item(self, Key):
        self.items.pop(self._key(Key), None)


@pytest.fixture
def table(monkeypatch):
    t = MemoryTable()
    monkeypatch.setattr(pa, "price_alerts_table", t)
    return t


def _utc(*args):
    return datetime(*args, tzinfo=timezone.utc)


# 2026-10-13（火）10:00 JST ＝ 01:00 UTC。東証は開いている
JP_OPEN = _utc(2026, 10, 13, 1, 0)
# 2026-10-13（火）11:00 EDT ＝ 15:00 UTC。米国は開いている・東証は閉まっている
US_OPEN = _utc(2026, 10, 13, 15, 0)


# ===================================================
# 入力のチェック
# ===================================================
def test_validate_accepts_price_alert():
    fields, error = pa.validate_fields({"code": "7203", "name": "トヨタ", "condition": "price_above", "target": "3000"})
    assert error is None
    assert fields == {"code": "7203", "name": "トヨタ", "condition": "price_above", "target": 3000.0, "repeat": "daily"}


@pytest.mark.parametrize("body", [
    {"code": "", "condition": "price_above", "target": 1},
    {"code": "トヨタ", "condition": "price_above", "target": 1},
    {"code": "7203", "condition": "unknown", "target": 1},
    {"code": "7203", "condition": "price_above", "target": 0},
    {"code": "7203", "condition": "price_above", "target": "abc"},
    {"code": "7203", "condition": "change_pct_above", "target": 80},
    {"code": "7203", "condition": "price_above", "target": 1, "repeat": "weekly"},
])
def test_validate_rejects_bad_input(body):
    _, error = pa.validate_fields(body)
    assert error


def test_validate_partial_only_checks_given_fields():
    fields, error = pa.validate_fields({"enabled": False}, partial=True)
    assert error is None and fields == {"enabled": False}


# ===================================================
# 登録・変更・削除
# ===================================================
def test_create_list_update_delete(table):
    fields, _ = pa.validate_fields({"code": "AAPL", "condition": "price_below", "target": 150})
    alert = pa.create_alert("u1", fields)
    assert [a["alert_id"] for a in pa.list_alerts("u1")] == [alert["alert_id"]]
    assert pa.list_alerts("u2") == []

    assert pa.update_alert("u1", alert["alert_id"], {"enabled": False}) is True
    assert table.items[("u1", alert["alert_id"])]["enabled"] is False
    # 他人のアラート・無いアラートは変えられない（新しく作られない）
    assert pa.update_alert("u2", alert["alert_id"], {"enabled": False}) is False
    assert ("u2", alert["alert_id"]) not in table.items

    pa.delete_alert("u1", alert["alert_id"])
    assert pa.list_alerts("u1") == []


def test_create_respects_limit(table):
    fields, _ = pa.validate_fields({"code": "7203", "condition": "price_above", "target": 1})
    for _ in range(MAX_ALERTS_PER_USER):
        pa.create_alert("u1", fields)
    with pytest.raises(pa.AlertLimitError):
        pa.create_alert("u1", fields)


def test_changing_target_resets_today_record(table):
    fields, _ = pa.validate_fields({"code": "7203", "condition": "price_above", "target": 1})
    alert = pa.create_alert("u1", fields)
    table.items[("u1", alert["alert_id"])]["last_notified_date"] = "2026-10-13"
    pa.update_alert("u1", alert["alert_id"], {"condition": "price_above", "target": 2.0})
    assert table.items[("u1", alert["alert_id"])]["last_notified_date"] == ""


# ===================================================
# 判定・通知の文面
# ===================================================
@pytest.mark.parametrize("condition,target,quote,expected", [
    ("price_above", 3000, {"price": 3000}, True),
    ("price_above", 3000, {"price": 2999.9}, False),
    ("price_below", 3000, {"price": 2999}, True),
    ("price_below", 3000, {"price": None}, False),
    ("change_pct_above", 5, {"change_pct": 5.2}, True),
    ("change_pct_above", 5, {"change_pct": -6}, False),
    ("change_pct_below", 5, {"change_pct": -5.0}, True),
    ("change_pct_below", 5, {"change_pct": 6}, False),
])
def test_is_triggered(condition, target, quote, expected):
    assert pa.is_triggered({"condition": condition, "target": target}, quote) is expected


def test_notification_text_jp_and_us():
    title, body = pa.notification_text(
        {"code": "72030", "name": "トヨタ自動車", "condition": "price_above", "target": 3000.0},
        {"price": 3012.0, "change_pct": 1.5},
    )
    assert title == "トヨタ自動車（7203）"
    assert body == "株価が 3,000円 以上になりました。現在 3,012円（前日比 +1.50%）"

    _, body = pa.notification_text(
        {"code": "AAPL", "name": "Apple", "condition": "change_pct_below", "target": 3.0},
        {"price": 150.5, "change_pct": -3.2},
    )
    assert body == "前日比 -3% 以下に下がりました。現在 $150.50（前日比 -3.20%）"


# ===================================================
# 市場の時間
# ===================================================
@pytest.mark.parametrize("now,expected", [
    (_utc(2026, 10, 13, 0, 0), True),     # 9:00 JST 寄り付き
    (_utc(2026, 10, 12, 23, 55), False),  # 8:55 JST
    (_utc(2026, 10, 13, 3, 0), False),    # 12:00 JST 昼休み
    (_utc(2026, 10, 13, 6, 50), True),    # 15:50 JST（遅れて届く引けの値を拾う余裕の中）
    (_utc(2026, 10, 13, 7, 0), False),    # 16:00 JST
    (_utc(2026, 10, 12, 1, 0), False),    # 2026-10-12 はスポーツの日（祝日）
    (_utc(2026, 10, 10, 1, 0), False),    # 土曜
])
def test_jp_market_hours(now, expected):
    assert market_hours.is_market_open("7203", now) is expected


@pytest.mark.parametrize("now,expected", [
    (_utc(2026, 10, 13, 13, 30), True),   # 夏時間：9:30 EDT
    (_utc(2026, 10, 13, 13, 25), False),  # 9:25 EDT
    (_utc(2026, 12, 15, 14, 30), True),   # 冬時間：9:30 EST
    (_utc(2026, 12, 15, 13, 30), False),  # 冬時間：8:30 EST
    (_utc(2026, 10, 17, 15, 0), False),   # 土曜
])
def test_us_market_hours(now, expected):
    assert market_hours.is_market_open("AAPL", now) is expected


def test_market_date_uses_market_local_day():
    # 2026-10-14 03:00 UTC ＝ 日本は 10/14 の 12:00、ニューヨークは 10/13 の 23:00
    now = _utc(2026, 10, 14, 3, 0)
    assert market_hours.market_date("7203", now) == "2026-10-14"
    assert market_hours.market_date("AAPL", now) == "2026-10-13"


# ===================================================
# 5分おきの判定（run_price_alert_check）
# ===================================================
def _add(table, user, alert_id, code, condition, target, repeat="daily", **extra):
    table.put_item({"userId": user, "alert_id": alert_id, "code": code, "name": code,
                    "condition": condition, "target": target, "repeat": repeat,
                    "enabled": True, "last_notified_date": "", **extra})


def test_run_notifies_once_per_day_and_turns_off_once_alerts(table):
    _add(table, "u1", "a1", "7203", "price_above", 3000)                  # 条件を満たす（毎日）
    _add(table, "u1", "a2", "7203", "price_below", 2000)                  # 満たさない
    _add(table, "u2", "a3", "7203", "price_above", 2500, repeat="once")   # 満たす（1回だけ）
    _add(table, "u2", "a4", "AAPL", "price_above", 1)                     # 米国株：今は閉まっている

    fetched, sent = [], []

    def fetch(code):
        fetched.append(code)
        return {"price": 3010.0, "change_pct": 1.0}

    def send(user_id, title, body, data):
        sent.append((user_id, data["alert_id"]))
        return 1

    summary = pa.run_price_alert_check(fetch, send, now_utc=JP_OPEN)
    assert fetched == ["7203"]  # 閉まっている米国株は株価を取りに行かない
    assert sorted(sent) == [("u1", "a1"), ("u2", "a3")]
    assert summary == {"alerts": 3, "codes": 1, "notified": 2}
    assert table.items[("u1", "a1")]["last_notified_date"] == "2026-10-13"
    assert table.items[("u1", "a1")]["enabled"] is True
    assert table.items[("u2", "a3")]["enabled"] is False

    # 同じ日の2回目は通知しない
    sent.clear()
    pa.run_price_alert_check(fetch, send, now_utc=JP_OPEN)
    assert sent == []


def test_run_does_not_record_when_no_device(table):
    _add(table, "u1", "a1", "AAPL", "price_above", 100)
    pa.run_price_alert_check(lambda c: {"price": 120.0}, lambda *a: 0, now_utc=US_OPEN)
    # 端末が無くて届かなかったので、許可したあとの判定で届くよう記録しない
    assert table.items[("u1", "a1")]["last_notified_date"] == ""


def test_run_survives_price_and_send_errors(table):
    _add(table, "u1", "a1", "7203", "price_above", 1)
    _add(table, "u1", "a2", "6758", "price_above", 1)

    def fetch(code):
        if code == "7203":
            raise RuntimeError("yfinance error")
        return {"price": 10.0}

    def send(*args):
        raise RuntimeError("fcm error")

    summary = pa.run_price_alert_check(fetch, send, now_utc=JP_OPEN)
    assert summary["notified"] == 0


# ===================================================
# Lambda の入口の振り分け
# ===================================================
def test_lambda_handler_routes_scheduler_event(monkeypatch):
    os.environ.setdefault("OPENAI_API_KEY", "testing")
    import lambda_handler

    called = {}
    monkeypatch.setattr(lambda_handler, "run_price_alert_check",
                        lambda fetch, send: called.setdefault("check", {"notified": 0}))
    monkeypatch.setattr(lambda_handler, "_mangum", lambda event, context: called.setdefault("http", True))

    assert lambda_handler.handler({"task": "price_alert_check"}, None) == {"notified": 0}
    assert "http" not in called
    lambda_handler.handler({"rawPath": "/health", "requestContext": {}}, None)
    assert called["http"] is True
