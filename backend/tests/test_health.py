# ===================================================
# /health（main.health_check）
#
# 以前は、このコンテナの銘柄マスタが空だと取り直さずに jquants: error を返し、
# アプリに「J-Quantsに接続できません」と出ていた。判定の前に取り直す。
# ===================================================

import os

import pandas as pd

# main.py は import した瞬間に OpenAI のクライアントを作り、鍵が無いとエラーになる（通信はしない）
os.environ.setdefault("OPENAI_API_KEY", "testing")

import main  # noqa: E402
import routers.stock as stock  # noqa: E402


class FakeTicker:
    def __init__(self, symbol):
        pass

    def history(self, period):
        return pd.DataFrame({"Close": [40000.0]})


def test_health_reloads_empty_master_before_judging(monkeypatch):
    monkeypatch.setattr(main.yf, "Ticker", FakeTicker)
    monkeypatch.setattr(main, "stocks_master", [])
    monkeypatch.setattr(stock, "stocks_master", main.stocks_master)
    monkeypatch.setattr(stock, "_last_master_retry", 0.0)

    def fake_reload():
        main.stocks_master[:] = [{"Code": "72030", "CoName": "トヨタ自動車"}]
        return True

    monkeypatch.setattr(stock, "reload_stocks_master", fake_reload)
    assert main.health_check() == {"yfinance": "ok", "jquants": "ok"}


def test_health_reports_error_when_reload_fails(monkeypatch):
    monkeypatch.setattr(main.yf, "Ticker", FakeTicker)
    monkeypatch.setattr(main, "stocks_master", [])
    monkeypatch.setattr(stock, "stocks_master", main.stocks_master)
    monkeypatch.setattr(stock, "_last_master_retry", 0.0)
    monkeypatch.setattr(stock, "reload_stocks_master", lambda: False)
    assert main.health_check()["jquants"] == "error"
