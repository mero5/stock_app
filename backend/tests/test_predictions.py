# ===================================================
# AI予測の記録と答え合わせ（services/predictions.py）
# ===================================================

from datetime import date, datetime
from decimal import Decimal

import pytest

from services import predictions


# ---------------------------------------------------
# classify_change：変化率 → up / sideways / down
# ---------------------------------------------------
@pytest.mark.parametrize("pct, expected", [
    (5.0, "up"),
    (3.01, "up"),
    (3.0, "sideways"),     # ちょうど3%はまだ様子見
    (0, "sideways"),
    (-3.0, "sideways"),
    (-3.01, "down"),
    (-10, "down"),
    (Decimal("4.5"), "up"),  # DynamoDB から来る Decimal でも動く
    (None, "sideways"),
    ("abc", "sideways"),
    (float("nan"), "sideways"),
])
def test_classify_change(pct, expected):
    assert predictions.classify_change(pct) == expected


# ---------------------------------------------------
# resolve_horizon_days：答え合わせまでの日数
# ---------------------------------------------------
def test_horizon_defaults_without_settings():
    assert predictions.resolve_horizon_days("短期") == 14
    assert predictions.resolve_horizon_days("中期") == 90
    assert predictions.resolve_horizon_days("不明な期間") == 90


def test_horizon_follows_user_settings():
    days = {"short_max": 7, "medium_max": 60}
    assert predictions.resolve_horizon_days("短期", days) == 7
    assert predictions.resolve_horizon_days("中期", days) == 60


def test_horizon_falls_back_on_invalid_settings():
    assert predictions.resolve_horizon_days("短期", {"short_max": "abc"}) == 14
    assert predictions.resolve_horizon_days("短期", {"short_max": None}) == 14
    assert predictions.resolve_horizon_days("短期", "壊れた値") == 14


# ---------------------------------------------------
# _scan_all：DynamoDB の scan を最後のページまで読む
# 再発防止：PR #11（Limit を使って取りこぼしていた）
# ---------------------------------------------------
def test_scan_all_reads_every_page(monkeypatch, fake_table):
    table = fake_table(scan_pages=[
        {"Items": [], "LastEvaluatedKey": {"k": 1}},        # 1ページ目：条件に合うものが0件でも
        {"Items": [{"id": "a"}], "LastEvaluatedKey": {"k": 2}},
        {"Items": [{"id": "b"}, {"id": "c"}]},              # 最後のページ
    ])
    monkeypatch.setattr(predictions, "predictions_table", table)

    items = predictions._scan_all(FilterExpression="f")

    assert [i["id"] for i in items] == ["a", "b", "c"]
    assert len(table.scan_calls) == 3
    # 2ページ目以降は続きの位置を渡している
    assert table.scan_calls[1]["ExclusiveStartKey"] == {"k": 1}
    assert table.scan_calls[2]["ExclusiveStartKey"] == {"k": 2}
    # Limit は使わない（絞り込み前の件数になってしまうため）
    assert all("Limit" not in c for c in table.scan_calls)


def test_scan_all_stops_at_max_items(monkeypatch, fake_table):
    table = fake_table(scan_pages=[
        {"Items": [{"id": "a"}, {"id": "b"}], "LastEvaluatedKey": {"k": 1}},
        {"Items": [{"id": "c"}, {"id": "d"}], "LastEvaluatedKey": {"k": 2}},
        {"Items": [{"id": "e"}]},
    ])
    monkeypatch.setattr(predictions, "predictions_table", table)

    items = predictions._scan_all(max_items=3)

    assert [i["id"] for i in items] == ["a", "b", "c"]
    assert len(table.scan_calls) == 2  # 3件集まった時点で打ち切る


# ---------------------------------------------------
# save_prediction：保存するかどうかの判定と中身
# ---------------------------------------------------
def _result(verdict="up"):
    return {
        "verdict": {"value": verdict},
        "probability": {"up": {"value": 60}, "sideways": 30, "down": {"value": 10}},
        "confidence": {"value": "中"},
    }


def _save(**overrides):
    args = dict(code="7203", ticker_code="7203.T", name="トヨタ", period="短期",
                result=_result(), price=2500, horizon_days=14, prompt_version="vX")
    args.update(overrides)
    return predictions.save_prediction(**args)


def test_save_prediction_writes_item(monkeypatch, fake_table):
    table = fake_table()
    monkeypatch.setattr(predictions, "predictions_table", table)
    monkeypatch.setattr(predictions, "now_jst", lambda: datetime(2026, 10, 10, 9, 0))

    assert _save() is True

    item = table.put_calls[0]
    assert item["verdict"] == "up"
    assert item["status"] == "pending"
    assert item["evaluate_at"] == "2026-10-24"  # 14日後
    assert item["prob_up"] == Decimal("60.0")
    assert item["prob_sideways"] == Decimal("30.0")


@pytest.mark.parametrize("overrides", [
    {"price": None},
    {"price": 0},
    {"price": "abc"},
    {"result": _result("buy")},  # up/sideways/down 以外
    {"result": {}},
])
def test_save_prediction_skips_invalid(monkeypatch, fake_table, overrides):
    table = fake_table()
    monkeypatch.setattr(predictions, "predictions_table", table)

    assert _save(**overrides) is False
    assert table.put_calls == []


def test_save_prediction_never_raises(monkeypatch):
    class BrokenTable:
        def put_item(self, Item):
            raise RuntimeError("DynamoDB down")

    monkeypatch.setattr(predictions, "predictions_table", BrokenTable())
    assert _save() is False  # 分析APIを落とさない


# ---------------------------------------------------
# evaluate_pending：期限が来た予測の答え合わせ
# ---------------------------------------------------
def _pending(code, verdict, base, evaluate_at="2026-10-01"):
    return {
        "code": code, "predicted_at": "2026-09-17T09:00:00", "ticker_code": f"{code}.T",
        "verdict": verdict, "price_at_prediction": Decimal(str(base)),
        "evaluate_at": evaluate_at, "status": "pending",
    }


def test_evaluate_pending(monkeypatch, fake_table):
    table = fake_table(scan_pages=[{"Items": [
        _pending("1111", "up", 100),        # 100 → 110（+10%）で up → 正解
        _pending("2222", "down", 100),      # 100 → 101（+1%）で sideways → 不正解
        _pending("3333", "up", 100),        # 株価が取れない → 保留
        _pending("4444", "up", 0),          # 基準価格が0 → 保留
    ]}])
    closes = {"1111.T": 110.0, "2222.T": 101.0, "3333.T": None, "4444.T": 50.0}

    monkeypatch.setattr(predictions, "predictions_table", table)
    monkeypatch.setattr(predictions, "today_jst", lambda: date(2026, 10, 10))
    monkeypatch.setattr(predictions, "now_jst", lambda: datetime(2026, 10, 10, 9, 0))
    monkeypatch.setattr(predictions, "_close_on_or_before", lambda t, d: closes[t])

    assert predictions.evaluate_pending() == {"evaluated": 2, "skipped": 2}

    updates = {u["Key"]["code"]: u["ExpressionAttributeValues"] for u in table.update_calls}
    assert updates["1111"][":a"] == "up"
    assert updates["1111"][":ok"] is True
    assert updates["1111"][":c"] == Decimal("10.0")
    assert updates["2222"][":a"] == "sideways"
    assert updates["2222"][":ok"] is False


def test_evaluate_pending_handles_scan_error(monkeypatch):
    class BrokenTable:
        def scan(self, **kwargs):
            raise RuntimeError("boom")

    monkeypatch.setattr(predictions, "predictions_table", BrokenTable())
    res = predictions.evaluate_pending()
    assert res["evaluated"] == 0
    assert "boom" in res["error"]


# ---------------------------------------------------
# get_recent_predictions：成績画面の履歴は自分の予測だけ（K-48）
# ---------------------------------------------------
HISTORY = [
    {"code": "7203", "predicted_at": "2026-10-03T10:00", "user_id": "me", "status": "pending"},
    {"code": "6758", "predicted_at": "2026-10-04T10:00", "user_id": "other", "status": "pending"},
    {"code": "7203", "predicted_at": "2026-10-01T10:00", "status": "pending"},   # user_id を記録する前の古い予測
    {"code": "7203", "predicted_at": "2026-10-05T10:00", "user_id": "other", "status": "pending"},
]


def test_recent_predictions_only_own(monkeypatch):
    monkeypatch.setattr(predictions, "_scan_all", lambda *a, **k: list(HISTORY))
    got = predictions.get_recent_predictions(limit=10, user_id="me")
    assert [p["predicted_at"] for p in got] == ["2026-10-03T10:00", "2026-10-01T10:00"]


def test_recent_predictions_own_and_code(monkeypatch):
    monkeypatch.setattr(predictions, "_scan_all", lambda *a, **k: list(HISTORY))
    got = predictions.get_recent_predictions(limit=1, code="7203", user_id="me")
    assert [p["predicted_at"] for p in got] == ["2026-10-03T10:00"]


def test_recent_predictions_without_user_returns_all(monkeypatch):
    # 古いアプリ（userId を送らない）には今までどおり全件を返す
    monkeypatch.setattr(predictions, "_scan_all", lambda *a, **k: list(HISTORY))
    assert len(predictions.get_recent_predictions(limit=10)) == 4



def test_stats_api_uses_token_user_when_user_id_missing(monkeypatch):
    # userId を送らない古いアプリでも、トークンの持ち主で絞る
    from types import SimpleNamespace
    import routers.stats as stats
    from services.auth import AuthResult

    calls = {}
    monkeypatch.setattr(stats, "get_recent_predictions",
                        lambda limit, code, user_id: calls.setdefault("user_id", user_id) and [])
    req = SimpleNamespace(state=SimpleNamespace(auth=AuthResult("valid", user_id="sub-123")))
    stats.list_predictions(req, limit=30, code="", userId="")
    assert calls["user_id"] == "sub-123"

    calls.clear()
    req = SimpleNamespace(state=SimpleNamespace(auth=AuthResult("none")))
    stats.list_predictions(req, limit=30, code="", userId="")
    assert calls["user_id"] == ""
