# ===================================================
# キャッシュ・日付・株価データの後始末（services/cache.py, clock.py, market_data.py）
# ===================================================

from datetime import datetime, timedelta, timezone
from decimal import Decimal

import numpy as np
import pandas as pd

from services import cache, clock
from services.market_data import drop_empty_rows


# ---------------------------------------------------
# Decimal ⇔ float の変換（DynamoDB は float を保存できない）
# ---------------------------------------------------
def test_decimal_round_trip():
    data = {"price": 123.45, "list": [1.5, {"x": 0.1}], "name": "トヨタ", "n": 3}
    stored = cache._to_decimal(data)
    assert stored["price"] == Decimal("123.45")
    assert stored["list"][1]["x"] == Decimal("0.1")
    assert stored["n"] == 3  # int はそのまま
    assert cache._from_decimal(stored) == data


# ---------------------------------------------------
# cache_get：期限切れは返さない
# ---------------------------------------------------
def test_cache_get_returns_fresh_item(monkeypatch, fake_table):
    now = datetime(2026, 10, 10, 9, 0)
    monkeypatch.setattr(cache, "now_jst", lambda: now)
    table = fake_table(item={
        "key": "sectors", "value": Decimal("1.5"),
        "updated_at": "2026-10-10T08:50:00",
        "expires_at": (now + timedelta(minutes=5)).isoformat(),
    })

    assert cache.cache_get(table, {"key": "sectors"}) == {"key": "sectors", "value": 1.5}


def test_cache_get_ignores_expired_item(monkeypatch, fake_table):
    now = datetime(2026, 10, 10, 9, 0)
    monkeypatch.setattr(cache, "now_jst", lambda: now)
    table = fake_table(item={"key": "sectors", "expires_at": (now - timedelta(seconds=1)).isoformat()})

    assert cache.cache_get(table, {"key": "sectors"}) is None


def test_cache_get_missing_or_error(fake_table):
    assert cache.cache_get(fake_table(), {"key": "none"}) is None

    class BrokenTable:
        def get_item(self, Key):
            raise RuntimeError("DynamoDB down")

    assert cache.cache_get(BrokenTable(), {"key": "x"}) is None  # 例外を外に出さない


def test_cache_set_writes_expiry(monkeypatch, fake_table):
    now = datetime(2026, 10, 10, 9, 0)
    monkeypatch.setattr(cache, "now_jst", lambda: now)
    table = fake_table()

    cache.cache_set(table, {"key": "sectors"}, {"value": 1.5}, ttl_minutes=15)

    item = table.put_calls[0]
    assert item["key"] == "sectors"
    assert item["value"] == Decimal("1.5")
    assert item["expires_at"] == "2026-10-10T09:15:00"


# ---------------------------------------------------
# 日本時間（JST）
# 再発防止：PR #6（Lambda は UTC なので、朝9時前の日付が前日になっていた）
# ---------------------------------------------------
def test_now_jst_is_utc_plus_9():
    utc_now = datetime.now(timezone.utc).replace(tzinfo=None)
    diff = clock.now_jst() - utc_now
    assert abs(diff - timedelta(hours=9)) < timedelta(seconds=5)
    assert clock.now_jst().tzinfo is None  # DynamoDB の文字列と比べるので naive


def test_today_jst_matches_now_jst():
    assert clock.today_jst() == clock.now_jst().date()


# ---------------------------------------------------
# drop_empty_rows：終値が空の行を落とす
# 再発防止：PR #4（日本株の最新行が NaN で、株価が null になっていた）
# ---------------------------------------------------
def test_drop_empty_rows_removes_nan_close():
    hist = pd.DataFrame(
        {"Close": [100.0, 101.0, np.nan], "Volume": [10, 20, 30]},
        index=pd.to_datetime(["2026-10-07", "2026-10-08", "2026-10-09"]),
    )
    cleaned = drop_empty_rows(hist)
    assert len(cleaned) == 2
    assert cleaned["Close"].iloc[-1] == 101.0


def test_drop_empty_rows_passes_through_empty():
    assert drop_empty_rows(None) is None
    empty = pd.DataFrame()
    assert drop_empty_rows(empty) is empty
    no_close = pd.DataFrame({"Volume": [1]})
    assert drop_empty_rows(no_close) is no_close
