# ===================================================
# AIに渡す指標の計算（services/technical.py）
# 再発防止：PR #10（騰落レシオの単位・金利の名前・RSIの計算方法の誤り）
#
# yfinance（株価API）とキャッシュは偽物に差し替え、決まった株価を渡して計算結果を確かめる。
# ===================================================

import numpy as np
import pandas as pd
import pytest

from services import technical as t


@pytest.fixture(autouse=True)
def no_cache(monkeypatch):
    """キャッシュは常に空・保存もしない（DynamoDB を触らない）"""
    monkeypatch.setattr(t, "cache_get", lambda table, key: None)
    monkeypatch.setattr(t, "cache_set", lambda *args, **kwargs: None)


# ---------------------------------------------------
# 騰落レシオ：%表記（上昇18・下落12 → 150.0）
# ---------------------------------------------------
def _download_result(closes: dict) -> pd.DataFrame:
    """yf.download(複数銘柄) と同じ形（列が ("Close", 銘柄)）の DataFrame を作る"""
    index = pd.to_datetime(["2026-10-07", "2026-10-08", "2026-10-09"])
    close = pd.DataFrame(closes, index=index)
    return pd.concat({"Close": close}, axis=1)


def test_breadth_ratio_is_percent(monkeypatch):
    closes = {}
    for i in range(18):   # 上昇
        closes[f"U{i}.T"] = [100, 100, 101]
    for i in range(12):   # 下落
        closes[f"D{i}.T"] = [100, 100, 99]
    monkeypatch.setattr(t.yf, "download", lambda *a, **k: _download_result(closes))

    res = t.get_nikkei225_breadth()

    assert res == {"advancers": 18, "decliners": 12, "advance_decline_ratio": 150.0}


def test_breadth_ignores_incomplete_latest_day(monkeypatch):
    # 最新日に空（NaN）の銘柄がある → その日は使わず、前の2日で比べる
    closes = {
        "A.T": [100, 110, np.nan],   # 100 → 110 で上昇
        "B.T": [100, 90, 95],        # 100 → 90 で下落
        "C.T": [100, 105, 120],      # 100 → 105 で上昇
    }
    monkeypatch.setattr(t.yf, "download", lambda *a, **k: _download_result(closes))

    res = t.get_nikkei225_breadth()

    assert res["advancers"] == 2
    assert res["decliners"] == 1
    assert res["advance_decline_ratio"] == 200.0


def test_breadth_no_decliners(monkeypatch):
    closes = {"A.T": [100, 100, 101]}
    monkeypatch.setattr(t.yf, "download", lambda *a, **k: _download_result(closes))
    assert t.get_nikkei225_breadth()["advance_decline_ratio"] is None


def test_breadth_download_error(monkeypatch):
    def boom(*a, **k):
        raise RuntimeError("network")
    monkeypatch.setattr(t.yf, "download", boom)
    assert t.get_nikkei225_breadth()["advance_decline_ratio"] is None


# ---------------------------------------------------
# マクロ：^IRX は「3ヶ月債」。金利差は 10年 - 3ヶ月
# ---------------------------------------------------
def test_macro_uses_3month_yield(monkeypatch):
    prices = {"^TNX": 4.2, "^IRX": 4.5, "^VIX": 15.0}
    monkeypatch.setattr(t, "get_latest_price", lambda code: prices.get(code))
    monkeypatch.setattr(t, "get_trend_label", lambda code, period="5d": "横ばい（0.0%）")

    macro = t.get_macro_data()

    assert macro["us3m"] == 4.5
    assert "us2y" not in macro
    assert macro["yield_spread"] == -0.3   # マイナス＝逆イールド


def test_macro_spread_none_when_missing(monkeypatch):
    monkeypatch.setattr(t, "get_latest_price", lambda code: None)
    monkeypatch.setattr(t, "get_trend_label", lambda code, period="5d": None)
    assert t.get_macro_data()["yield_spread"] is None


# ---------------------------------------------------
# RSI：ワイルダー方式（/stock/detail のチャートと同じ計算）
# ---------------------------------------------------
class FakeTicker:
    def __init__(self, hist):
        self._hist = hist

    def history(self, **kwargs):
        return self._hist


def _hist(closes) -> pd.DataFrame:
    closes = pd.Series(closes, dtype=float)
    index = pd.bdate_range("2026-04-01", periods=len(closes))
    return pd.DataFrame({
        "Open": closes.values, "High": closes.values + 1, "Low": closes.values - 1,
        "Close": closes.values, "Volume": np.full(len(closes), 1000.0),
    }, index=index)


def _wilder_rsi(closes, period=14):
    """
    ワイルダーのRSIをループで素直に計算した「答え」。
    最初の変化量から始めて、平均 = 前の平均 × 13/14 + 今回 × 1/14 で更新していく
    """
    deltas = np.diff(closes)
    avg_gain = max(deltas[0], 0)
    avg_loss = max(-deltas[0], 0)
    for d in deltas[1:]:
        avg_gain = avg_gain * (period - 1) / period + max(d, 0) / period
        avg_loss = avg_loss * (period - 1) / period + max(-d, 0) / period
    return 100 - 100 / (1 + avg_gain / avg_loss)


def test_rsi_matches_wilder(monkeypatch):
    rng = np.random.default_rng(0)
    closes = 1000 + np.cumsum(rng.normal(0, 10, 80))
    monkeypatch.setattr(t.yf, "Ticker", lambda code: FakeTicker(_hist(closes)))

    tech = t.get_technical_data("7203.T")

    assert tech["rsi"] == pytest.approx(_wilder_rsi(closes), abs=0.01)


def test_rsi_differs_from_simple_average(monkeypatch):
    # 単純移動平均（#10より前の計算）とは値が変わることを確かめる
    rng = np.random.default_rng(1)
    closes = 1000 + np.cumsum(rng.normal(0, 10, 80))
    monkeypatch.setattr(t.yf, "Ticker", lambda code: FakeTicker(_hist(closes)))

    delta = pd.Series(closes).diff()
    gain = delta.clip(lower=0).rolling(14).mean().iloc[-1]
    loss = (-delta.clip(upper=0)).rolling(14).mean().iloc[-1]
    old_rsi = 100 - 100 / (1 + gain / loss)

    assert abs(t.get_technical_data("7203.T")["rsi"] - old_rsi) > 0.01


def test_rsi_all_rising_is_100(monkeypatch):
    closes = np.arange(1000, 1060, dtype=float)
    monkeypatch.setattr(t.yf, "Ticker", lambda code: FakeTicker(_hist(closes)))
    assert t.get_technical_data("7203.T")["rsi"] == 100.0


def test_technical_needs_30_days(monkeypatch):
    monkeypatch.setattr(t.yf, "Ticker", lambda code: FakeTicker(_hist(np.arange(29.0) + 100)))
    assert t.get_technical_data("7203.T") == {}


def test_technical_drops_empty_latest_row(monkeypatch):
    # 日本株は最新行が NaN で返ることがある（#4）。その行は無視して直前の終値を使う
    hist = _hist(np.arange(1000, 1060, dtype=float))
    hist.loc[hist.index[-1], ["Open", "High", "Low", "Close"]] = np.nan
    monkeypatch.setattr(t.yf, "Ticker", lambda code: FakeTicker(hist))

    tech = t.get_technical_data("7203.T")

    assert tech["price"] == 1058.0
    assert tech["ma5"] == 1056.0


# ---------------------------------------------------
# プロンプト：AIに渡す説明文の単位・名前
# ---------------------------------------------------
def _prompt(builder):
    return builder(
        name="トヨタ", code="7203", tech={"price": 2500, "rsi": 55.0},
        fund={}, macro={"us10y": 4.2, "us3m": 4.5, "yield_spread": -0.3},
        breadth={"advance_decline_ratio": 150.0, "advancers": 18, "decliners": 12},
        earnings_alert={"level": "safe", "message": None}, news_summary="",
        score=None, user_profile=None,
        checks={"macro": True, "supply": True},
    )


@pytest.mark.parametrize("builder", [t.build_short_prompt, t.build_medium_prompt, t.build_long_prompt])
def test_prompt_breadth_is_percent(builder):
    assert "騰落レシオ（簡易：主要30銘柄・当日）：150.0%" in _prompt(builder)


@pytest.mark.parametrize("builder", [t.build_medium_prompt, t.build_long_prompt])
def test_prompt_uses_3month_yield(builder):
    prompt = _prompt(builder)
    assert "米3ヶ月債：4.5%" in prompt
    assert "2年債" not in prompt
