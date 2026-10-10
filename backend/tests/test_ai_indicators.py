# ===================================================
# AI に渡す指標（52週・ADX・配当落ち日）
#
# 以前は ①「52週」が3か月・6か月分の値 ②ADX が最新1日の DX
# ③アプリが送る配当落ち日を使っていない だった（K-50・K-51・K-52）。
# ===================================================

import numpy as np
import pandas as pd

from services import technical as t
from services.market_data import week52_range


# ---------------------------------------------------
# 52週の高値・安値
# ---------------------------------------------------
def test_week52_prefers_yfinance_info():
    info = {"fiftyTwoWeekHigh": 4000.0, "fiftyTwoWeekLow": 2200.5}
    assert week52_range(info, [3100, 3200], [2900, 3000]) == (4000.0, 2200.5)


def test_week52_falls_back_to_given_prices():
    assert week52_range({}, [3100, 3200], [2900, 3000]) == (3200.0, 2900.0)
    assert week52_range(None) == (None, None)


# ---------------------------------------------------
# テクニカル：1年分で計算・ADX は DX の14日平均
# ---------------------------------------------------
class FakeTicker:
    def __init__(self, hist):
        self._hist = hist
        self.periods = []

    def history(self, period):
        self.periods.append(period)
        return self._hist


def _hist(days=250):
    idx = pd.date_range("2025-10-01", periods=days, freq="B")
    rng = np.random.default_rng(0)
    close = 1000 + np.cumsum(rng.normal(0, 10, days))
    return pd.DataFrame({
        "Open": close, "High": close + 5, "Low": close - 5, "Close": close,
        "Volume": rng.integers(1000, 2000, days).astype(float),
    }, index=idx)


def test_technical_uses_one_year_and_smoothed_adx(monkeypatch):
    hist = _hist()
    fake = FakeTicker(hist)
    monkeypatch.setattr(t.yf, "Ticker", lambda code: fake)
    monkeypatch.setattr(t, "cache_get", lambda *a, **k: None)
    saved = {}
    monkeypatch.setattr(t, "cache_set", lambda table, key, data, ttl_minutes: saved.update(key=key))

    tech = t.get_technical_data("7203.T")

    assert fake.periods == ["1y"]
    assert saved["key"] == {"code": "7203.T", "cache_type": "technical_v2"}
    # 52週は1年分の終値の高値・安値
    assert tech["week52_high"] == round(hist["Close"].max(), 2)
    assert tech["momentum_6m"] is not None  # 6か月分のデータがあるので出る

    # ADX は DX の14日平均（最新1日の DX ではない）
    high, low, close = hist["High"], hist["Low"], hist["Close"]
    tr = pd.concat([high - low, (high - close.shift()).abs(), (low - close.shift()).abs()], axis=1).max(axis=1)
    atr = tr.rolling(14).mean()
    pdi = high.diff().clip(lower=0).rolling(14).mean() / atr * 100
    mdi = (-low.diff()).clip(lower=0).rolling(14).mean() / atr * 100
    dx = (pdi - mdi).abs() / (pdi + mdi) * 100
    assert tech["adx"] == round(dx.rolling(14).mean().iloc[-1], 2)


# ---------------------------------------------------
# 配当落ち日がプロンプトに入る
# ---------------------------------------------------
def test_prompts_include_ex_dividend_date():
    alert = {"exists": False, "level": "safe", "date": None, "days_to": None,
             "ex_dividend_date": "2027-03-30"}
    args = ("トヨタ自動車", "7203", {}, {}, {}, {}, alert, "なし", None, {})
    for build in (t.build_short_prompt, t.build_medium_prompt):
        assert "- 配当落ち日：2027-03-30" in build(*args)
    assert "- 配当落ち日：2027-03-30" in t.build_long_prompt(
        "トヨタ自動車", "7203", {}, {}, {}, earnings_alert=alert)


def test_prompt_version_bumped():
    assert t.PROMPT_VERSION == "v4-data-fix"
