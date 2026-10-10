# ===================================================
# ポートフォリオ診断（routers/ai.portfolio_diagnosis）
#
# 以前は ①回答の上限が銘柄数に関係なく4000で途中で切れやすい
# ②アプリが送るセクターのデータを使っていない ③長期の業績推移が常に空 だった（K-49）。
# ===================================================

import asyncio

import routers.ai as ai

SECTOR_DATA = {"jp": [{"name": "自動車・輸送機", "change_pct": 1.2, "trend_5d": -0.4}], "us": []}


def _fake_fetchers(monkeypatch):
    monkeypatch.setattr(ai, "get_technical_data", lambda t: {"price": 3000.0, "rsi": 55})
    monkeypatch.setattr(ai, "get_fundamental_data", lambda t: {
        "sector": "Consumer Cyclical", "industry": "Auto Manufacturers",
        "revenue_trend": {"2024": 450000.0, "2025": 480000.0},
        "op_income_trend": {"2024": 53000.0, "2025": 48000.0},
    })
    monkeypatch.setattr(ai, "get_macro_data", lambda: {})
    # セクター名の対応表は別のテスト（test_technical_helpers）で確かめるので、ここでは
    # 「アプリが送ったセクターのデータが渡っているか」だけを見る
    monkeypatch.setattr(ai, "resolve_sector_trend",
                        lambda sector, industry, sector_data, ticker: (
                            "自動車・輸送機 +1.20%（5日:-0.40%）" if sector_data == SECTOR_DATA else "不明"))


def test_max_tokens_grows_with_holdings():
    assert ai.portfolio_max_tokens(1) == 2700
    assert ai.portfolio_max_tokens(10) == 13500
    assert ai.portfolio_max_tokens(0) == 2700  # 0件でも最低1銘柄分


def test_enrich_holding_adds_sector_trend_and_trends(monkeypatch):
    _fake_fetchers(monkeypatch)
    h = ai._enrich_holding({"code": "7203", "ticker_code": "7203.T", "cost_price": 2500, "shares": 100},
                           SECTOR_DATA)
    assert h["sector_trend"] == "自動車・輸送機 +1.20%（5日:-0.40%）"
    assert h["revenue_trend"] == {"2024": 450000.0, "2025": 480000.0}
    assert h["profit_loss_pct"] == 20.0
    assert h["profit_loss_yen"] == 50000


def test_enrich_holding_never_raises(monkeypatch):
    def boom(t):
        raise RuntimeError("yfinance error")
    monkeypatch.setattr(ai, "get_technical_data", boom)
    h = ai._enrich_holding({"code": "7203", "ticker_code": "7203.T"}, {})
    assert h["current_price"] is None and "error" in h


class FakeRequest:
    def __init__(self, body):
        self._body = body

    async def json(self):
        return self._body


def test_prompt_has_sector_trend_and_long_trends(monkeypatch):
    _fake_fetchers(monkeypatch)
    captured = {}

    def fake_call(prompt, system, max_tokens=4000, **kwargs):
        captured["prompt"] = prompt
        captured["max_tokens"] = max_tokens
        return {"holdings": []}, {}

    monkeypatch.setattr(ai, "call_openai_json", fake_call)
    holdings = [{"code": f"72{i:02d}", "name": "テスト", "ticker_code": "7203.T"} for i in range(5)]
    asyncio.run(ai.portfolio_diagnosis(FakeRequest(
        {"holdings": holdings, "period": "長期", "sector_data": SECTOR_DATA}
    )))
    assert "セクター騰落：自動車・輸送機 +1.20%" in captured["prompt"]
    assert "売上高推移(億円)：{'2024': 450000.0, '2025': 480000.0}" in captured["prompt"]
    assert captured["max_tokens"] == ai.portfolio_max_tokens(5)
