# ===================================================
# ウォッチリスト用のまとめ取得API（routers/stock.get_stock_quotes）
#
# 以前のアプリは銘柄ごとに /stock/name と /stock/price を同時に呼び、
# Lambda の同時実行数の上限を超えた分が断られて株価「---」・名前がコードになっていた。
# ===================================================

import routers.stock as stock


def _fake_name(code):
    return {"code": code, "name": {"72030": "トヨタ自動車", "AAPL": "Apple Inc."}.get(code, code)}


def _fake_price(code):
    if code == "BROKEN":
        raise RuntimeError("yfinance error")
    return {"code": code, "price": 100.0, "change": 1.0, "change_pct": 1.01}


def test_quotes_returns_name_and_price_in_request_order(monkeypatch):
    monkeypatch.setattr(stock, "get_stock_name", _fake_name)
    monkeypatch.setattr(stock, "get_stock_price", _fake_price)
    monkeypatch.setattr(stock, "ensure_stocks_master", lambda: None)

    result = stock.get_stock_quotes("AAPL, 72030,,")
    assert result == {"quotes": [
        {"code": "AAPL", "name": "Apple Inc.", "price": 100.0, "change": 1.0, "change_pct": 1.01},
        {"code": "72030", "name": "トヨタ自動車", "price": 100.0, "change": 1.0, "change_pct": 1.01},
    ]}


def test_one_failure_does_not_break_others(monkeypatch):
    monkeypatch.setattr(stock, "get_stock_name", _fake_name)
    monkeypatch.setattr(stock, "get_stock_price", _fake_price)
    monkeypatch.setattr(stock, "ensure_stocks_master", lambda: None)

    quotes = stock.get_stock_quotes("BROKEN,72030")["quotes"]
    assert quotes[0] == {"code": "BROKEN", "name": "BROKEN", "price": None, "change": None, "change_pct": None}
    assert quotes[1]["price"] == 100.0


def test_empty_codes(monkeypatch):
    monkeypatch.setattr(stock, "ensure_stocks_master", lambda: None)
    assert stock.get_stock_quotes("") == {"quotes": []}


def test_codes_are_capped(monkeypatch):
    monkeypatch.setattr(stock, "get_stock_name", _fake_name)
    monkeypatch.setattr(stock, "get_stock_price", _fake_price)
    monkeypatch.setattr(stock, "ensure_stocks_master", lambda: None)

    codes = ",".join(str(10000 + i) for i in range(stock.QUOTES_MAX_CODES + 5))
    assert len(stock.get_stock_quotes(codes)["quotes"]) == stock.QUOTES_MAX_CODES
